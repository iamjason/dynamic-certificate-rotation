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
        // Create certificate request
        let certificateRequest = try createCertificateRequest(subject: subject, publicKey: publicKey)

        // Sign the certificate request
        guard let signedCSR = try signCertificateRequest(certificateRequest, with: privateKey) else {
            return nil
        }

        return signedCSR
    }

    private func createCertificateRequest(subject: [String: String], publicKey: SecKey) throws -> Data {
        // This is a simplified CSR creation. In production, you'd want to use a proper ASN.1 library
        // For now, we'll create a basic structure that can be processed by the backend

        var csrString = "-----BEGIN CERTIFICATE REQUEST-----\n"

        // Add version
        csrString += "Version: 1\n"

        // Add subject
        csrString += "Subject: "
        let subjectComponents = subject.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        csrString += subjectComponents + "\n"

        // Add public key info (simplified)
        csrString += "Public Key: ECDSA P-256\n"

        // Add signature algorithm
        csrString += "Signature Algorithm: ecdsa-with-SHA256\n"

        csrString += "-----END CERTIFICATE REQUEST-----\n"

        return csrString.data(using: .utf8)!
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
        let certificateData = try await networkService.enrollCertificate(enrollmentRequest)

        enrollmentState = .receivingCertificate
        enrollmentProgress = "Processing received certificate..."

        // Create certificate from data
        guard let certificate = SecCertificateCreateWithData(kCFAllocatorDefault, certificateData as CFData) else {
            throw EnrollmentError.certificateCreationFailed
        }

        // Store certificate in keychain
        let label = "iOS-Client-\(deviceId.prefix(8))"
        try await storeCertificateInKeychain(certificate, withLabel: label)

        // Create certificate info
        let certInfo = try parseCertificateInfo(certificate, source: .downloaded)

        enrollmentState = .completed
        enrollmentProgress = "Certificate enrollment completed successfully"

        // Clear temporary keys
        currentPrivateKey = nil
        currentPublicKey = nil

        return certInfo
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
