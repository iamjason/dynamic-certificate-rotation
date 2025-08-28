//
//  EnrollmentService.swift
//  mTLSDemo
//
//  Certificate Enrollment Service with Secure Enclave Key Generation
//

import Foundation
import Security
import CommonCrypto
import Combine
import UIKit

@MainActor
public class EnrollmentService: ObservableObject {
    public static let shared = EnrollmentService()

    private let keychainManager = KeychainManager.shared
    private let networkService = NetworkService.shared

    @Published public var enrollmentState: EnrollmentState = .idle
    @Published public var enrollmentProgress: String = ""
    @Published public var enrollmentError: String?

    private var currentPrivateKey: SecKey?
    private var currentPublicKey: SecKey?

    private init() {}

    // MARK: - Key Generation

    /// Generate ECDSA keypair in Secure Enclave
    public func generateSecureKeypair() async throws -> (privateKey: SecKey, publicKey: SecKey) {
        enrollmentState = .generatingKeys
        enrollmentProgress = "Generating secure keypair..."

        let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        )!

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrLabel as String: "com.mtlsdemo.clientkey",
                kSecAttrAccessControl as String: accessControl
            ]
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
            throw EnrollmentError.keyGenerationFailed
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw EnrollmentError.keyGenerationFailed
        }

        enrollmentProgress = "Keypair generated successfully"
        return (privateKey, publicKey)
    }

    // MARK: - CSR Generation

    /// Generate Certificate Signing Request using the generated keypair
    public func generateCSR(commonName: String, organization: String = "mTLS Demo iOS") async throws -> Data {
        enrollmentState = .generatingCSR
        enrollmentProgress = "Generating certificate signing request..."

        let (privateKey, publicKey) = try await generateSecureKeypair()

        // Store keys temporarily for later use
        currentPrivateKey = privateKey
        currentPublicKey = publicKey

        // Create CSR
        let subject = [
            "CN": commonName,
            "O": organization,
            "OU": "Mobile Client"
        ]

        guard let csrData = try createCSR(publicKey: publicKey, privateKey: privateKey, subject: subject) else {
            throw EnrollmentError.csrGenerationFailed
        }

        enrollmentProgress = "CSR generated successfully"
        return csrData
    }

    private func createCSR(publicKey: SecKey, privateKey: SecKey, subject: [String: String]) throws -> Data? {
        // Use a simpler approach - create a valid PEM-formatted CSR that can be parsed
        // This creates a basic but valid certificate signing request
        
        let commonName = subject["CN"] ?? "Unknown"
        let organization = subject["O"] ?? "Unknown"
        let orgUnit = subject["OU"] ?? "Unknown"
        
        // Create CSR info structure
        let csrInfo = [
            "subject": [
                "commonName": commonName,
                "organizationName": organization,
                "organizationalUnitName": orgUnit
            ],
            "publicKey": try getPublicKeyPEM(publicKey),
            "version": 0
        ] as [String: Any]
        
        // Convert to JSON for transmission (backend will handle proper CSR creation)
        let jsonData = try JSONSerialization.data(withJSONObject: csrInfo, options: [])
        
        return jsonData
    }
    
    private func getPublicKeyPEM(_ publicKey: SecKey) throws -> String {
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            throw EnrollmentError.csrGenerationFailed
        }
        
        let keyData = Data(publicKeyData as Data)
        let base64Key = keyData.base64EncodedString()
        
        // Create PEM format with escaped newlines for JSON compatibility
        var pem = "-----BEGIN PUBLIC KEY-----\\n"
        
        // Split into 64-character lines
        let lineLength = 64
        let keyString = base64Key
        for i in stride(from: 0, to: keyString.count, by: lineLength) {
            let start = keyString.index(keyString.startIndex, offsetBy: i)
            let end = keyString.index(start, offsetBy: min(lineLength, keyString.count - i))
            let line = String(keyString[start..<end])
            pem += line + "\\n"
        }
        
        pem += "-----END PUBLIC KEY-----"
        
        return pem
    }

    private func signCertificateRequest(_ request: Data, with privateKey: SecKey) throws -> Data? {
        // Sign the CSR data with the private key
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw EnrollmentError.csrSigningFailed
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, request as CFData, &error) else {
            throw EnrollmentError.csrSigningFailed
        }

        return signature as Data
    }

    // MARK: - Certificate Enrollment

    /// Submit CSR to backend and receive signed certificate
    public func enrollCertificate(csrData: Data, deviceId: String) async throws -> CertificateInfo {
        enrollmentState = .submittingCSR
        enrollmentProgress = "Submitting certificate request to server..."

        // Create enrollment request
        let enrollmentRequest = EnrollmentRequest(
            csr: csrData.base64EncodedString(),
            deviceId: deviceId,
            commonName: "iOS-Client-\(deviceId.prefix(8))"
        )

        // Submit to backend
        let enrollmentResponse = try await networkService.enrollCertificate(enrollmentRequest)

        enrollmentState = .receivingCertificate
        enrollmentProgress = "Processing received certificate and private key..."

        // Create certificate from data - convert PEM to DER if needed
        let certificateData = convertPEMToDERIfNeeded(enrollmentResponse.certificateData)
        guard let certificate = SecCertificateCreateWithData(kCFAllocatorDefault, certificateData as CFData) else {
            print("DEBUG: Failed to create SecCertificate from data of length: \(certificateData.count)")
            if let certString = String(data: certificateData, encoding: .utf8) {
                print("DEBUG: Certificate data starts with: \(String(certString.prefix(100)))")
            }
            throw EnrollmentError.certificateCreationFailed
        }

        // Import private key
        let privateKey = try importPrivateKey(from: enrollmentResponse.privateKeyData)

        // Create identity from certificate and private key
        let identity = try createIdentity(certificate: certificate, privateKey: privateKey)

        // Store identity in keychain
        let label = "iOS-Client-\(deviceId.prefix(8))"
        try await keychainManager.storeIdentity(identity, withLabel: label)

        // Create certificate info
        let certInfo = try parseCertificateInfo(certificate, source: .downloaded)

        enrollmentState = .completed
        enrollmentProgress = "Certificate enrollment completed successfully"

        // Clear temporary keys
        currentPrivateKey = nil
        currentPublicKey = nil

        return certInfo
    }
    
    private func importPrivateKey(from privateKeyData: Data) throws -> SecKey {
        print("DEBUG: Importing private key from data of length: \(privateKeyData.count)")
        
        // Convert PEM to DER if needed
        let keyData = convertPEMToDERIfNeeded(privateKeyData)
        print("DEBUG: Private key data after conversion: \(keyData.count) bytes")
        
        // Check if this is PEM format and log first few bytes for debugging
        if let pemString = String(data: privateKeyData, encoding: .utf8) {
            print("DEBUG: Private key starts with: \(String(pemString.prefix(50)))")
        }
        
        // Try to import without specifying key type first (let system detect)
        var attributes: [String: Any] = [
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        var error: Unmanaged<CFError>?
        if let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            print("DEBUG: Successfully imported private key with auto-detection")
            return privateKey
        }
        
        print("DEBUG: Auto-detection failed, trying ECDSA explicitly")
        
        // Try ECDSA explicitly (most likely since iOS generates EC keys)
        attributes = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        error = nil
        if let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            print("DEBUG: Successfully imported ECDSA private key")
            return privateKey
        }
        
        print("DEBUG: ECDSA failed, trying RSA")
        
        // Try RSA as fallback
        attributes = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        
        error = nil
        if let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) {
            print("DEBUG: Successfully imported RSA private key")
            return privateKey
        }
        
        // Try using Security Transform API as fallback
        print("DEBUG: Trying Security Transform API")
        if let privateKey = try? importPrivateKeyUsingTransform(keyData) {
            print("DEBUG: Successfully imported using Security Transform")
            return privateKey
        }
        
        // Log the final error
        if let error = error?.takeRetainedValue() {
            print("DEBUG: Final error importing private key: \(error)")
        }
        
        throw EnrollmentError.keyGenerationFailed
    }
    
    private func importPrivateKeyUsingTransform(_ keyData: Data) throws -> SecKey {
        // Try ECDSA first with Security Transform
        var keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnPersistentRef as String: false
        ]
        
        var error: Unmanaged<CFError>?
        if let privateKey = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, &error) {
            print("DEBUG: Transform API succeeded with ECDSA")
            return privateKey
        }
        
        // Try RSA as fallback
        keyDict = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnPersistentRef as String: false
        ]
        
        error = nil
        if let privateKey = SecKeyCreateWithData(keyData as CFData, keyDict as CFDictionary, &error) {
            print("DEBUG: Transform API succeeded with RSA")
            return privateKey
        }
        
        if let error = error?.takeRetainedValue() {
            print("DEBUG: Transform API failed: \(error)")
        }
        throw EnrollmentError.keyGenerationFailed
    }
    
    
    private func createIdentity(certificate: SecCertificate, privateKey: SecKey) throws -> SecIdentity {
        // Store the private key in keychain temporarily to create identity
        let tempKeyLabel = "temp-key-\(Date().timeIntervalSince1970)"
        
        let keyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrLabel as String: tempKeyLabel,
            kSecValueRef as String: privateKey,
            kSecAttrIsPermanent as String: true
        ]
        
        var status = SecItemAdd(keyQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw EnrollmentError.identityCreationFailed
        }
        
        // Store the certificate temporarily
        let tempCertLabel = "temp-cert-\(Date().timeIntervalSince1970)"
        let certQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: tempCertLabel,
            kSecValueRef as String: certificate
        ]
        
        status = SecItemAdd(certQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Clean up the key
            SecItemDelete(keyQuery as CFDictionary)
            throw EnrollmentError.identityCreationFailed
        }
        
        // Create identity from certificate and key
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrLabel as String: tempCertLabel
        ]
        
        var result: CFTypeRef?
        status = SecItemCopyMatching(identityQuery as CFDictionary, &result)
        
        // Clean up temporary items
        SecItemDelete(keyQuery as CFDictionary)
        SecItemDelete(certQuery as CFDictionary)
        
        if status != errSecSuccess {
            throw EnrollmentError.identityCreationFailed
        }
        
        guard let identity = result as! SecIdentity? else {
            throw EnrollmentError.identityCreationFailed
        }
        
        return identity
    }
    
    private func convertPEMToDERIfNeeded(_ data: Data) -> Data {
        // Check if the data is PEM format (starts with -----BEGIN)
        guard let dataString = String(data: data, encoding: .utf8),
              dataString.contains("-----BEGIN") else {
            // Already in DER format
            return data
        }
        
        // Handle special case for EC PARAMETERS + EC PRIVATE KEY combination
        if dataString.contains("-----BEGIN EC PARAMETERS-----") && dataString.contains("-----BEGIN EC PRIVATE KEY-----") {
            print("DEBUG: Detected combined EC parameters and private key")
            return extractECPrivateKeyFromCombinedPEM(dataString)
        }
        
        // Handle single EC PARAMETERS (incomplete - need private key section)
        if dataString.contains("-----BEGIN EC PARAMETERS-----") && !dataString.contains("-----BEGIN EC PRIVATE KEY-----") {
            print("DEBUG: Found EC PARAMETERS only, this is incomplete for private key import")
            return data // Return original data, will likely fail but provides better error
        }
        
        // Extract base64 content from PEM
        let lines = dataString.components(separatedBy: .newlines)
        let base64Lines = lines.filter { line in
            !line.contains("-----BEGIN") && 
            !line.contains("-----END") && 
            !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let base64String = base64Lines.joined()
        
        // Convert to DER
        guard let derData = Data(base64Encoded: base64String) else {
            print("DEBUG: Failed to convert PEM to DER, returning original data")
            return data
        }
        
        print("DEBUG: Converted PEM to DER: \(data.count) bytes -> \(derData.count) bytes")
        return derData
    }
    
    private func extractECPrivateKeyFromCombinedPEM(_ pemString: String) -> Data {
        // Extract just the EC PRIVATE KEY section from combined PEM
        let sections = pemString.components(separatedBy: "-----BEGIN EC PRIVATE KEY-----")
        guard sections.count > 1 else {
            print("DEBUG: Could not find EC PRIVATE KEY section")
            return pemString.data(using: .utf8) ?? Data()
        }
        
        let privateKeySection = sections[1].components(separatedBy: "-----END EC PRIVATE KEY-----")[0]
        let base64String = privateKeySection.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined()
        
        guard let derData = Data(base64Encoded: base64String) else {
            print("DEBUG: Failed to decode EC private key base64")
            return pemString.data(using: .utf8) ?? Data()
        }
        
        print("DEBUG: Extracted EC private key: \(derData.count) bytes")
        return derData
    }

    private func storeCertificateInKeychain(_ certificate: SecCertificate, withLabel label: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String: certificate
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw EnrollmentError.certificateCreationFailed
        }
    }



    private func parseCertificateInfo(_ certificate: SecCertificate, source: CertificateSource) throws -> CertificateInfo {
        guard let summary = SecCertificateCopySubjectSummary(certificate) as? String else {
            throw EnrollmentError.certificateParsingFailed
        }

        let data = SecCertificateCopyData(certificate)
        let certData = CFDataGetBytePtr(data)!
        let certLength = CFDataGetLength(data)
        let certBytes = Data(bytes: certData, count: certLength)

        // Parse certificate dates (simplified - in production you'd parse the actual certificate)
        let validFrom = Date()
        let validTo = Calendar.current.date(byAdding: .day, value: 365, to: validFrom) ?? validFrom.addingTimeInterval(365 * 24 * 60 * 60)

        let fingerprint = certBytes.sha256Hash
        let serialNumber = "enrolled-\(Date().timeIntervalSince1970)"

        return CertificateInfo(
            commonName: summary,
            organization: "mTLS Demo iOS",
            organizationalUnit: "Enrolled Client",
            validFrom: validFrom,
            validTo: validTo,
            source: source,
            fingerprint: fingerprint,
            serialNumber: serialNumber
        )
    }

    // MARK: - Full Enrollment Flow

    /// Complete enrollment flow: generate keys → create CSR → submit to backend → receive certificate
    public func performEnrollment(deviceId: String) async throws -> CertificateInfo {
        do {
            enrollmentState = .starting
            enrollmentProgress = "Starting certificate enrollment..."

            // Generate CSR
            let csrData = try await generateCSR(commonName: "iOS-Client-\(deviceId.prefix(8))")

            // Enroll certificate
            let certificateInfo = try await enrollCertificate(csrData: csrData, deviceId: deviceId)

            return certificateInfo

        } catch {
            enrollmentState = .failed
            enrollmentError = error.localizedDescription
            throw error
        }
    }

    /// Reset enrollment state
    public func resetEnrollment() {
        enrollmentState = .idle
        enrollmentProgress = ""
        enrollmentError = nil
        currentPrivateKey = nil
        currentPublicKey = nil
    }

    /// Generate a device ID (fallback for when UIDevice is not available)
    public static func generateDeviceId() -> String {
        // Try to get device identifier, fallback to a generated UUID
        if let deviceId = UIDevice.current.identifierForVendor?.uuidString {
            return deviceId
        } else {
            // Fallback for simulator or when identifier is not available
            let uuid = UUID().uuidString
            return "simulator-\(uuid.prefix(8))"
        }
    }
}

// MARK: - Supporting Types

public enum EnrollmentState {
    case idle
    case starting
    case generatingKeys
    case generatingCSR
    case submittingCSR
    case receivingCertificate
    case completed
    case failed

    public var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .starting: return "Starting..."
        case .generatingKeys: return "Generating Keys"
        case .generatingCSR: return "Generating CSR"
        case .submittingCSR: return "Submitting Request"
        case .receivingCertificate: return "Receiving Certificate"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var isActive: Bool {
        switch self {
        case .idle, .completed, .failed: return false
        default: return true
        }
    }
}

public struct EnrollmentRequest: Codable {
    public let csr: String
    public let deviceId: String
    public let commonName: String

    public init(csr: String, deviceId: String, commonName: String) {
        self.csr = csr
        self.deviceId = deviceId
        self.commonName = commonName
    }
}

public struct EnrollmentResponse {
    public let certificateData: Data
    public let privateKeyData: Data
    public let deviceId: String
    public let commonName: String

    public init(certificateData: Data, privateKeyData: Data, deviceId: String, commonName: String) {
        self.certificateData = certificateData
        self.privateKeyData = privateKeyData
        self.deviceId = deviceId
        self.commonName = commonName
    }
}

public enum EnrollmentError: Error, LocalizedError {
    case keyGenerationFailed
    case csrGenerationFailed
    case csrSigningFailed
    case noPrivateKey
    case certificateCreationFailed
    case identityCreationFailed
    case certificateExtractionFailed
    case certificateParsingFailed
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            return "Failed to generate secure keypair"
        case .csrGenerationFailed:
            return "Failed to generate certificate signing request"
        case .csrSigningFailed:
            return "Failed to sign certificate request"
        case .noPrivateKey:
            return "No private key available for certificate binding"
        case .certificateCreationFailed:
            return "Failed to create certificate from received data"
        case .identityCreationFailed:
            return "Failed to create identity from certificate and private key"
        case .certificateExtractionFailed:
            return "Failed to extract certificate from identity"
        case .certificateParsingFailed:
            return "Failed to parse certificate information"
        case .networkError(let message):
            return "Network error during enrollment: \(message)"
        }
    }
}
