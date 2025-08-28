//
//  CertificateModel.swift
//  mTLSDemo
//
//  mTLS Demo Certificate Models and Data Structures
//

import Foundation
import Security

@Observable
public class CertificateInfo {
    public let commonName: String
    public let organization: String
    public let organizationalUnit: String
    public let validFrom: Date
    public let validTo: Date
    public let source: CertificateSource
    public let fingerprint: String
    public let serialNumber: String
    
    public init(commonName: String, organization: String, organizationalUnit: String, validFrom: Date, validTo: Date, source: CertificateSource, fingerprint: String, serialNumber: String) {
        self.commonName = commonName
        self.organization = organization
        self.organizationalUnit = organizationalUnit
        self.validFrom = validFrom
        self.validTo = validTo
        self.source = source
        self.fingerprint = fingerprint
        self.serialNumber = serialNumber
    }
    
    public var isValid: Bool {
        let now = Date()
        return now >= validFrom && now <= validTo
    }
    
    public var daysUntilExpiry: Int {
        let now = Date()
        let timeInterval = validTo.timeIntervalSince(now)
        return max(0, Int(timeInterval / 86400))
    }
    
    public var expiryStatus: ExpiryStatus {
        let days = daysUntilExpiry
        if !isValid {
            return .expired
        } else if days <= 7 {
            return .expiresSoon
        } else if days <= 14 {
            return .rotationRequired
        } else {
            return .valid
        }
    }
}

public enum CertificateSource {
    case bundle
    case keychain
    case downloaded
}

public enum ExpiryStatus {
    case valid
    case rotationRequired
    case expiresSoon
    case expired
    
    public var displayText: String {
        switch self {
        case .valid:
            return "Valid"
        case .rotationRequired:
            return "Rotation Required"
        case .expiresSoon:
            return "Expires Soon"
        case .expired:
            return "Expired"
        }
    }
    
    public var color: String {
        switch self {
        case .valid:
            return "green"
        case .rotationRequired:
            return "orange"
        case .expiresSoon:
            return "red"
        case .expired:
            return "red"
        }
    }
}

public struct NetworkResponse: Codable {
    public let status: String?
    public let message: String?
    public let authenticated: Bool?
    public let client: ClientInfo?
    public let certificate: CertificateDetails?
    public let data: SecureData?
    public let timestamp: String?
    public let certName: String?
    public let validTo: String?
    public let daysUntilExpiry: Int?
    public let rotationRequired: Bool?
    public let rotationRecommended: Bool?
    
    public init(status: String? = nil, message: String? = nil, authenticated: Bool? = nil, client: ClientInfo? = nil, certificate: CertificateDetails? = nil, data: SecureData? = nil, timestamp: String? = nil, certName: String? = nil, validTo: String? = nil, daysUntilExpiry: Int? = nil, rotationRequired: Bool? = nil, rotationRecommended: Bool? = nil) {
        self.status = status
        self.message = message
        self.authenticated = authenticated
        self.client = client
        self.certificate = certificate
        self.data = data
        self.timestamp = timestamp
        self.certName = certName
        self.validTo = validTo
        self.daysUntilExpiry = daysUntilExpiry
        self.rotationRequired = rotationRequired
        self.rotationRecommended = rotationRecommended
    }
}

public struct ClientInfo: Codable {
    public let commonName: String
    public let organization: String
    public let organizationalUnit: String
    public let country: String
    public let state: String
    public let locality: String
}

public struct CertificateDetails: Codable {
    public let validFrom: String
    public let validTo: String
    public let issuer: IssuerInfo
    public let fingerprint: String
    public let serialNumber: String
}

public struct IssuerInfo: Codable {
    public let commonName: String
    public let organization: String
    public let organizationalUnit: String
}

public struct SecureData: Codable {
    public let secretValue: String
    public let permissions: [String]
    public let sessionId: String
}