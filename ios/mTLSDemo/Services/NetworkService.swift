//
//  NetworkService.swift
//  mTLSDemo
//
//  mTLS Network Service with CA Pinning and Client Certificate Authentication
//

import Foundation
import Network
import Security
import Combine

@MainActor
public class NetworkService: NSObject, ObservableObject {
    public static let shared = NetworkService()
    
    @Published public var isConnected = false
    @Published public var connectionStatus = "Disconnected"
    @Published public var lastResponse: String?
    @Published public var error: String?
    
    private let baseURL = "https://localhost:8443"
    private var urlSession: URLSession
    
    private override init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        
        // Initialize with placeholder first
        self.urlSession = URLSession(configuration: configuration)
        super.init()
        
        // Replace with properly configured session with delegate
        self.urlSession = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
    }
    
    public func testHealth() async {
        await performRequest(endpoint: "/health", method: "GET")
    }
    
    public func getClientInfo() async {
        await performRequest(endpoint: "/api/client-info", method: "GET")
    }
    
    public func getSecureData() async {
        await performRequest(endpoint: "/api/secure-data", method: "GET")
    }
    
    public func checkCertificateStatus() async {
        await performRequest(endpoint: "/api/certificates/current", method: "GET")
    }
    
    public func downloadCertificate(named name: String) async {
        await performRequest(endpoint: "/api/certificates/download/\(name)", method: "GET")
    }

    /// Enroll a new certificate using CSR
    public func enrollCertificate(_ enrollmentRequest: EnrollmentRequest) async throws -> Data {
        guard let url = URL(string: baseURL + "/api/certificates/enroll") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let jsonData = try JSONEncoder().encode(enrollmentRequest)
        request.httpBody = jsonData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse JSON response to extract certificate data
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool, success,
              let certificateBase64 = jsonResponse["certificate"] as? String else {
            throw NetworkError.invalidResponse
        }

        // Decode the base64 certificate data
        guard let certificateData = Data(base64Encoded: certificateBase64) else {
            throw NetworkError.invalidResponse
        }

        return certificateData
    }
    
    private func performRequest(endpoint: String, method: String, body: Data? = nil) async {
        guard let url = URL(string: baseURL + endpoint) else {
            await MainActor.run {
                self.error = "Invalid URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        do {
            print("DEBUG: Starting URLSession request to: \(request.url?.absoluteString ?? "unknown")")
            let (data, response) = try await urlSession.data(for: request)
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseString = String(data: data, encoding: .utf8) ?? "No response data"
            
            await MainActor.run {
                self.isConnected = (200...299).contains(statusCode)
                self.connectionStatus = self.isConnected ? "Connected" : "Failed (\(statusCode))"
                self.lastResponse = responseString
                self.error = nil
                
                if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let prettyJsonData = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
                   let prettyJsonString = String(data: prettyJsonData, encoding: .utf8) {
                    self.lastResponse = prettyJsonString
                }
            }
            
        } catch {
            await MainActor.run {
                self.isConnected = false
                self.connectionStatus = "Failed"
                self.error = error.localizedDescription
                self.lastResponse = nil
            }
        }
    }
}

extension NetworkService: URLSessionDelegate {
    nonisolated public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        print("DEBUG: *** URLSessionDelegate challenge received ***")
        print("DEBUG: Authentication method: \(challenge.protectionSpace.authenticationMethod)")
        print("DEBUG: Challenge host: \(challenge.protectionSpace.host)")
        
        Task {
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodServerTrust:
                print("DEBUG: Handling server trust challenge")
                if await validateServerTrust(challenge.protectionSpace.serverTrust) {
                    let credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.rejectProtectionSpace, nil)
                }
                
            case NSURLAuthenticationMethodClientCertificate:
                print("DEBUG: Handling client certificate challenge at session level")
                if let identity = await CertificateManager.shared.getCurrentIdentity() {
                    print("DEBUG: Client certificate identity found at session level - providing credential")
                    let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
                    completionHandler(.useCredential, credential)
                } else {
                    print("DEBUG: No client certificate identity available at session level")
                    completionHandler(.rejectProtectionSpace, nil)
                }
                
            default:
                print("DEBUG: Unknown challenge method: \(challenge.protectionSpace.authenticationMethod)")
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, didFinishCollecting metrics: URLSessionTaskMetrics) {
        Task { @MainActor in
            if let transaction = metrics.transactionMetrics.first {
                let tlsVersion = transaction.negotiatedTLSProtocolVersion?.rawValue ?? 0
                self.connectionStatus = "Connected via TLS \(tlsVersion > 0 ? "v\(tlsVersion)" : "Unknown")"
            }
        }
    }
}

extension NetworkService: URLSessionTaskDelegate {
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        print("DEBUG: *** URLSessionTaskDelegate challenge received ***")
        print("DEBUG: Authentication method: \(challenge.protectionSpace.authenticationMethod)")
        print("DEBUG: URL: \(task.originalRequest?.url?.absoluteString ?? "unknown")")
        print("DEBUG: Challenge host: \(challenge.protectionSpace.host)")
        print("DEBUG: All challenge methods available: \(challenge.protectionSpace)")
        
        // Log all available authentication methods for debugging
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            print("DEBUG: This is a server trust challenge")
        }
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            print("DEBUG: This is a client certificate challenge")
        }
        
        Task {
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodClientCertificate:
                print("DEBUG: Client certificate challenge detected at task level")
                
                if let identity = await CertificateManager.shared.getCurrentIdentity() {
                    print("DEBUG: Client certificate identity found at task level - providing credential")
                    let credential = URLCredential(identity: identity, certificates: nil, persistence: .forSession)
                    completionHandler(.useCredential, credential)
                } else {
                    print("DEBUG: No client certificate identity available at task level")
                    completionHandler(.rejectProtectionSpace, nil)
                }
                
            case NSURLAuthenticationMethodServerTrust:
                print("DEBUG: Server trust challenge at task level - using default handling")
                completionHandler(.performDefaultHandling, nil)
                
            default:
                print("DEBUG: Unknown challenge method at task level: \(challenge.protectionSpace.authenticationMethod)")
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}

extension NetworkService {
    private func validateServerTrust(_ serverTrust: SecTrust?) async -> Bool {
        guard let serverTrust = serverTrust else { 
            print("DEBUG: No server trust provided")
            await MainActor.run {
                self.error = "No server trust provided"
            }
            return false 
        }
        
        print("DEBUG: Starting server trust validation")
        
        // Get server certificate chain info
        let certCount = SecTrustGetCertificateCount(serverTrust)
        print("DEBUG: Server certificate chain has \(certCount) certificates")
        
        guard let caCertData = loadCACertificate() else {
            print("DEBUG: CA certificate not found in bundle")
            await MainActor.run {
                self.error = "CA certificate not found in bundle"
            }
            return false
        }
        
        guard let caCert = SecCertificateCreateWithData(nil, caCertData as CFData) else {
            print("DEBUG: Failed to create CA certificate from bundle data")
            await MainActor.run {
                self.error = "Failed to create CA certificate from bundle data"
            }
            return false
        }
        
        print("DEBUG: CA certificate loaded successfully")
        
        // Approach 1: Try direct certificate pinning validation
        // Compare the CA certificate in the chain with our pinned CA
        if certCount > 1 {
            // Get the CA certificate from the server chain (usually the last one)
            if let serverCaCert = SecTrustGetCertificateAtIndex(serverTrust, certCount - 1) {
                let serverCaData = SecCertificateCopyData(serverCaCert)
                
                // Compare with our pinned CA
                if CFEqual(serverCaData, caCertData as CFData) {
                    print("DEBUG: CA certificate pinning validation succeeded - certificates match")
                    return true
                } else {
                    print("DEBUG: CA certificate mismatch - server CA differs from pinned CA")
                }
            }
        }
        
        // Approach 2: If direct pinning failed, try SecTrust evaluation with our CA as anchor
        print("DEBUG: Trying SecTrust evaluation with custom CA")
        
        // Create SSL policy for localhost
        let policy = SecPolicyCreateSSL(true, "localhost" as CFString)
        let policyStatus = SecTrustSetPolicies(serverTrust, policy)
        
        guard policyStatus == errSecSuccess else {
            print("DEBUG: Failed to set SSL policy: \(policyStatus)")
            await MainActor.run {
                self.error = "Failed to set SSL policy: \(policyStatus)"
            }
            return false
        }
        
        // Set our CA as an additional trusted anchor (don't override system anchors completely)
        let anchorStatus = SecTrustSetAnchorCertificates(serverTrust, [caCert] as CFArray)
        guard anchorStatus == errSecSuccess else {
            print("DEBUG: Failed to set anchor certificates: \(anchorStatus)")
            await MainActor.run {
                self.error = "Failed to set anchor certificates: \(anchorStatus)"
            }
            return false
        }
        
        // Note: We're NOT calling SecTrustSetAnchorCertificatesOnly(true) to allow fallback
        print("DEBUG: Custom anchor set, evaluating trust")
        
        // Evaluate the trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        print("DEBUG: Trust evaluation result: \(isValid)")
        
        if !isValid {
            let errorDesc = error?.localizedDescription ?? "Unknown trust error"
            let errorCode = error.map { CFErrorGetCode($0) } ?? 0
            print("DEBUG: Trust evaluation failed with error: \(errorDesc) (code: \(errorCode))")
            await MainActor.run {
                self.error = "Server certificate failed CA pinning validation: \(errorDesc)"
            }
        } else {
            print("DEBUG: Trust evaluation succeeded!")
        }
        
        return isValid
    }
    
    private func loadCACertificate() -> Data? {
        guard let url = Bundle.main.url(forResource: "ca-cert", withExtension: "pem") else {
            print("DEBUG: CA certificate file not found in bundle")
            return nil
        }
        
        guard let pemContent = try? String(contentsOf: url) else {
            print("DEBUG: Failed to read CA certificate file")
            return nil
        }
        
        print("DEBUG: CA certificate PEM content loaded, length: \(pemContent.count)")
        
        let lines = pemContent.components(separatedBy: .newlines)
        var base64String = ""
        var insideCertificate = false
        
        for line in lines {
            if line.contains("-----BEGIN CERTIFICATE-----") {
                insideCertificate = true
                continue
            }
            if line.contains("-----END CERTIFICATE-----") {
                break
            }
            if insideCertificate {
                base64String += line.trimmingCharacters(in: .whitespaces)
            }
        }
        
        guard !base64String.isEmpty else {
            print("DEBUG: No certificate data extracted from PEM file")
            return nil
        }
        
        guard let certData = Data(base64Encoded: base64String) else {
            print("DEBUG: Failed to decode base64 certificate data")
            return nil
        }
        
        print("DEBUG: Successfully loaded CA certificate data, size: \(certData.count) bytes")
        return certData
    }
}

// MARK: - Network Errors

public enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}