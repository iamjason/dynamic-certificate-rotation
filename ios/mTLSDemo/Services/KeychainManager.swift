//
//  KeychainManager.swift
//  mTLSDemo
//
//  Secure keychain management for mTLS certificates
//

import Foundation
import Security
import Combine

@MainActor
public class KeychainManager: ObservableObject {
    public static let shared = KeychainManager()
    
    private init() {}
    
    public func storeIdentity(_ identity: SecIdentity, withLabel label: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueRef as String: identity
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try await updateIdentity(identity, withLabel: label)
        } else if status != errSecSuccess {
            throw KeychainError.storageError(status)
        }
    }
    
    private func updateIdentity(_ identity: SecIdentity, withLabel label: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label
        ]
        
        let update: [String: Any] = [
            kSecValueRef as String: identity
        ]
        
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        
        if status != errSecSuccess {
            throw KeychainError.updateError(status)
        }
    }
    
    public func retrieveIdentity(withLabel label: String) async throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        if status != errSecSuccess {
            throw KeychainError.retrievalError(status)
        }
        
        return result as! SecIdentity?
    }
    
    public func listIdentities() async throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return []
        }
        
        if status != errSecSuccess {
            throw KeychainError.listError(status)
        }
        
        guard let items = result as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { item in
            item[kSecAttrLabel as String] as? String
        }
    }
    
    public func deleteIdentity(withLabel label: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deletionError(status)
        }
    }
    
    public func deleteAllIdentities() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deletionError(status)
        }
    }
}

public enum KeychainError: Error, LocalizedError {
    case storageError(OSStatus)
    case retrievalError(OSStatus)
    case updateError(OSStatus)
    case listError(OSStatus)
    case deletionError(OSStatus)
    case invalidIdentity
    
    public var errorDescription: String? {
        switch self {
        case .storageError(let status):
            return "Failed to store identity in keychain: \(status)"
        case .retrievalError(let status):
            return "Failed to retrieve identity from keychain: \(status)"
        case .updateError(let status):
            return "Failed to update identity in keychain: \(status)"
        case .listError(let status):
            return "Failed to list identities in keychain: \(status)"
        case .deletionError(let status):
            return "Failed to delete identity from keychain: \(status)"
        case .invalidIdentity:
            return "Invalid identity provided"
        }
    }
}