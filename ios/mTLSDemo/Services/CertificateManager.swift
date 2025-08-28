//
//  CertificateManager.swift
//  mTLSDemo
//
//  mTLS Certificate Management with Bundle and Keychain Support
//

import Foundation
import Security
import CommonCrypto
import Combine

@MainActor
public class CertificateManager: ObservableObject {
    public static let shared = CertificateManager()
    private let keychainManager = KeychainManager.shared
    
    @Published public var certificates: [CertificateInfo] = []
    @Published public var currentCertificate: CertificateInfo?
    @Published public var isLoading = false
    @Published public var error: String?
    
    private init() {
        Task {
            print("DEBUG: CertificateManager initializing...")
            await loadCertificates()
            print("DEBUG: CertificateManager initialization complete. Certificates loaded: \(certificates.count)")
            print("DEBUG: Current certificate: \(currentCertificate?.commonName ?? "none")")
        }
    }
    
    public func loadCertificates() async {
        isLoading = true
        error = nil
        
        do {
            var allCerts: [CertificateInfo] = []
            
            allCerts.append(contentsOf: try await loadBundledCertificates())
            allCerts.append(contentsOf: try await loadKeychainCertificates())
            
            certificates = allCerts.sorted { $0.validTo > $1.validTo }
            
            if let current = certificates.first(where: { $0.isValid }) {
                currentCertificate = current
            }
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadBundledCertificates() async throws -> [CertificateInfo] {
        var bundledCerts: [CertificateInfo] = []
        
        let certNames = ["ios-client-v1", "ios-client-v2"]
        
        for certName in certNames {
            print("DEBUG: Loading bundled certificate: \(certName)")
            
            guard let p12Data = loadP12FromBundle(named: certName) else {
                print("DEBUG: Failed to load P12 data for \(certName)")
                continue
            }
            print("DEBUG: P12 data loaded for \(certName), size: \(p12Data.count) bytes")
            
            do {
                let identity = try extractIdentityFromP12(p12Data, password: "demo123")
                print("DEBUG: Identity extracted for \(certName)")
                
                let certificate = try extractCertificateFromIdentity(identity)
                print("DEBUG: Certificate extracted for \(certName)")
                
                let certInfo = try parseCertificateInfo(certificate, source: .bundle)
                print("DEBUG: Certificate info parsed for \(certName): \(certInfo.commonName)")
                
                bundledCerts.append(certInfo)
            } catch {
                print("DEBUG: Error processing \(certName): \(error)")
            }
        }
        
        print("DEBUG: Loaded \(bundledCerts.count) bundled certificates")
        return bundledCerts
    }
    
    private func loadKeychainCertificates() async throws -> [CertificateInfo] {
        let labels = try await keychainManager.listIdentities()
        var keychainCerts: [CertificateInfo] = []
        
        for label in labels {
            if let identity = try await keychainManager.retrieveIdentity(withLabel: label),
               let certificate = try? extractCertificateFromIdentity(identity),
               let certInfo = try? parseCertificateInfo(certificate, source: .keychain) {
                keychainCerts.append(certInfo)
            }
        }
        
        return keychainCerts
    }
    
    private func loadP12FromBundle(named name: String) -> Data? {
        print("DEBUG: Looking for P12 file: \(name).p12")
        
        guard let url = Bundle.main.url(forResource: name, withExtension: "p12") else {
            print("DEBUG: P12 file not found in bundle: \(name).p12")
            
            // List all resources in bundle for debugging
            if let resourcePath = Bundle.main.resourcePath {
                print("DEBUG: Bundle resource path: \(resourcePath)")
                do {
                    let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("DEBUG: Bundle contents: \(contents)")
                } catch {
                    print("DEBUG: Error listing bundle contents: \(error)")
                }
            }
            
            return nil
        }
        
        print("DEBUG: Found P12 URL: \(url)")
        
        do {
            let data = try Data(contentsOf: url)
            print("DEBUG: P12 data loaded successfully, size: \(data.count) bytes")
            return data
        } catch {
            print("DEBUG: Error loading P12 data: \(error)")
            return nil
        }
    }
    
    private func extractIdentityFromP12(_ p12Data: Data, password: String) throws -> SecIdentity {
        print("DEBUG: Extracting identity from P12, data size: \(p12Data.count), password: \(password)")
        
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]
        
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        print("DEBUG: SecPKCS12Import status: \(status)")
        
        if status != errSecSuccess {
            let errorString = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            print("DEBUG: SecPKCS12Import failed: \(errorString)")
            throw CertificateError.invalidP12Data
        }
        
        guard let itemsArray = items as? [[String: Any]] else {
            print("DEBUG: Failed to cast items to array")
            throw CertificateError.invalidP12Data
        }
        
        print("DEBUG: P12 import returned \(itemsArray.count) items")
        
        guard let firstItem = itemsArray.first else {
            print("DEBUG: No items in P12 import result")
            throw CertificateError.invalidP12Data
        }
        
        print("DEBUG: First item keys: \(firstItem.keys)")
        
        guard let identityRef = firstItem[kSecImportItemIdentity as String] else {
            print("DEBUG: No identity found in P12 import result")
            throw CertificateError.invalidP12Data
        }
        
        guard CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID() else {
            print("DEBUG: Invalid identity type")
            throw CertificateError.invalidP12Data
        }
        
        print("DEBUG: Successfully extracted identity from P12")
        return (identityRef as! SecIdentity)
    }
    
    private func extractCertificateFromIdentity(_ identity: SecIdentity) throws -> SecCertificate {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess, let cert = certificate else {
            throw CertificateError.certificateExtractionFailed
        }
        
        return cert
    }
    
    private func parseCertificateInfo(_ certificate: SecCertificate, source: CertificateSource) throws -> CertificateInfo {
        guard let summary = SecCertificateCopySubjectSummary(certificate) as? String else {
            throw CertificateError.certificateParsingFailed
        }
        
        let data = SecCertificateCopyData(certificate)
        let certData = CFDataGetBytePtr(data)!
        let certLength = CFDataGetLength(data)
        let certBytes = Data(bytes: certData, count: certLength)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        
        let validFrom = Date()
        let validTo = Calendar.current.date(byAdding: .day, value: 90, to: validFrom) ?? validFrom
        
        let fingerprint = certBytes.sha256Hash
        let serialNumber = "demo-serial"
        
        return CertificateInfo(
            commonName: summary,
            organization: "mTLS Demo iOS",
            organizationalUnit: "Mobile",
            validFrom: validFrom,
            validTo: validTo,
            source: source,
            fingerprint: fingerprint,
            serialNumber: serialNumber
        )
    }
    
    public func installCertificate(from p12Data: Data, password: String, label: String) async throws {
        let identity = try extractIdentityFromP12(p12Data, password: password)
        try await keychainManager.storeIdentity(identity, withLabel: label)
        await loadCertificates()
    }
    
    public func deleteCertificate(withLabel label: String) async throws {
        try await keychainManager.deleteIdentity(withLabel: label)
        await loadCertificates()
    }
    
    public func cleanupExpiredCertificates() async {
        do {
            let labels = try await keychainManager.listIdentities()
            for label in labels {
                if let identity = try await keychainManager.retrieveIdentity(withLabel: label),
                   let certificate = try? extractCertificateFromIdentity(identity),
                   let certInfo = try? parseCertificateInfo(certificate, source: .keychain),
                   !certInfo.isValid {
                    try await keychainManager.deleteIdentity(withLabel: label)
                }
            }
            await loadCertificates()
        } catch {
            self.error = "Failed to cleanup expired certificates: \(error.localizedDescription)"
        }
    }
    
    public func getCurrentIdentity() async -> SecIdentity? {
        print("DEBUG: getCurrentIdentity called")
        
        guard let currentCert = currentCertificate else { 
            print("DEBUG: No current certificate available")
            return nil 
        }
        
        print("DEBUG: Current certificate: \(currentCert.commonName) from \(currentCert.source)")
        
        // Always try to get identity from Keychain first (proper mTLS approach)
        print("DEBUG: Loading identity from keychain for: \(currentCert.commonName)")
        if let identity = try? await keychainManager.retrieveIdentity(withLabel: currentCert.commonName) {
            print("DEBUG: Identity successfully retrieved from keychain")
            return identity
        } else {
            print("DEBUG: Identity not found in keychain, attempting to install from bundle")
        }
        
        // If not in keychain, try to install from bundle P12
        if currentCert.source == .bundle {
            print("DEBUG: Installing P12 from bundle to keychain for: \(currentCert.commonName)")
            if let p12Data = loadP12FromBundle(named: currentCert.commonName) {
                print("DEBUG: P12 data loaded, size: \(p12Data.count) bytes")
                do {
                    let identity = try extractIdentityFromP12(p12Data, password: "demo123")
                    print("DEBUG: Identity extracted from P12, installing to keychain")
                    
                    // Install identity to keychain
                    try await keychainManager.storeIdentity(identity, withLabel: currentCert.commonName)
                    print("DEBUG: Identity successfully installed to keychain")
                    
                    // Now retrieve it from keychain
                    if let keychainIdentity = try? await keychainManager.retrieveIdentity(withLabel: currentCert.commonName) {
                        print("DEBUG: Identity successfully retrieved from keychain after installation")
                        return keychainIdentity
                    } else {
                        print("DEBUG: Failed to retrieve identity from keychain after installation")
                    }
                } catch {
                    print("DEBUG: Failed to extract or install identity: \(error)")
                }
            } else {
                print("DEBUG: Failed to load P12 from bundle")
            }
        }
        
        print("DEBUG: No identity available")
        return nil
    }
}

public enum CertificateError: Error, LocalizedError {
    case invalidP12Data
    case certificateExtractionFailed
    case certificateParsingFailed
    case noCertificateFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidP12Data:
            return "Invalid P12 certificate data"
        case .certificateExtractionFailed:
            return "Failed to extract certificate from identity"
        case .certificateParsingFailed:
            return "Failed to parse certificate information"
        case .noCertificateFound:
            return "No certificate found"
        }
    }
}

extension Data {
    var sha256Hash: String {
        let digest = self.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: 32)
            CC_SHA256(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(self.count), &hash)
            return hash
        }
        return digest.map { String(format: "%02x", $0) }.joined().uppercased()
    }
}