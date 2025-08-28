//
//  CertificateRotationService.swift
//  mTLSDemo
//
//  Automatic Certificate Rotation Management Service
//

import Foundation
import Combine

@MainActor
public class CertificateRotationService: ObservableObject {
    public static let shared = CertificateRotationService()
    
    @Published public var rotationRequired = false
    @Published public var rotationRecommended = false
    @Published public var nextRotationDate: Date?
    @Published public var rotationThresholdDays = 14
    @Published public var isCheckingRotation = false
    @Published public var lastCheckDate: Date?
    @Published public var rotationStatus = "Not Checked"
    
    private let certificateManager = CertificateManager.shared
    private let networkService = NetworkService.shared
    private var rotationTimer: Timer?
    
    private init() {
        startRotationMonitoring()
    }
    
    deinit {
        rotationTimer?.invalidate()
    }
    
    public func startRotationMonitoring() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task {
                await self.checkRotationNeeded()
            }
        }
        
        Task {
            await checkRotationNeeded()
        }
    }
    
    public func stopRotationMonitoring() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
    
    public func checkRotationNeeded() async {
        isCheckingRotation = true
        lastCheckDate = Date()
        
        defer {
            isCheckingRotation = false
        }
        
        guard let currentCert = certificateManager.currentCertificate else {
            rotationStatus = "No Certificate"
            return
        }
        
        let daysUntilExpiry = currentCert.daysUntilExpiry
        
        rotationRequired = daysUntilExpiry <= rotationThresholdDays
        rotationRecommended = daysUntilExpiry <= 30
        
        if daysUntilExpiry > 0 {
            nextRotationDate = Calendar.current.date(byAdding: .day, value: -(rotationThresholdDays), to: currentCert.validTo)
        }
        
        rotationStatus = determineRotationStatus(daysUntilExpiry: daysUntilExpiry)
        
        await checkServerRotationStatus()
    }
    
    private func checkServerRotationStatus() async {
        await networkService.checkCertificateStatus()
        
        if let responseData = networkService.lastResponse?.data(using: .utf8),
           let response = try? JSONDecoder().decode(NetworkResponse.self, from: responseData) {
            
            if let serverRotationRequired = response.rotationRequired {
                rotationRequired = rotationRequired || serverRotationRequired
            }
            
            if let serverRotationRecommended = response.rotationRecommended {
                rotationRecommended = rotationRecommended || serverRotationRecommended
            }
        }
    }
    
    private func determineRotationStatus(daysUntilExpiry: Int) -> String {
        if daysUntilExpiry <= 0 {
            return "Certificate Expired"
        } else if daysUntilExpiry <= 7 {
            return "Rotation Urgent (\(daysUntilExpiry) days left)"
        } else if daysUntilExpiry <= rotationThresholdDays {
            return "Rotation Required (\(daysUntilExpiry) days left)"
        } else if daysUntilExpiry <= 30 {
            return "Rotation Recommended (\(daysUntilExpiry) days left)"
        } else {
            return "Certificate Valid (\(daysUntilExpiry) days left)"
        }
    }
    
    public func performRotation(newCertName: String) async throws {
        guard rotationRequired || rotationRecommended else {
            throw RotationError.rotationNotNeeded
        }
        
        await networkService.downloadCertificate(named: newCertName)
        
        guard let responseData = networkService.lastResponse?.data(using: .utf8) else {
            throw RotationError.downloadFailed
        }
        
        try await certificateManager.installCertificate(from: responseData, password: "demo123", label: newCertName)
        
        await certificateManager.loadCertificates()
        await checkRotationNeeded()
    }
    
    public func scheduleRotation(for date: Date) {
        nextRotationDate = date
        
        let timer = Timer(fireAt: date, interval: 0, target: self, selector: #selector(performScheduledRotation), userInfo: nil, repeats: false)
        RunLoop.current.add(timer, forMode: .common)
    }
    
    @objc private func performScheduledRotation() {
        Task {
            do {
                let newCertName = generateNewCertName()
                try await performRotation(newCertName: newCertName)
                rotationStatus = "Rotation Completed Successfully"
            } catch {
                rotationStatus = "Rotation Failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func generateNewCertName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "ios-client-rotated-\(dateFormatter.string(from: Date()))"
    }
    
    public func resetRotationThreshold(_ days: Int) {
        rotationThresholdDays = max(1, min(90, days))
        Task {
            await checkRotationNeeded()
        }
    }
}

public enum RotationError: Error, LocalizedError {
    case rotationNotNeeded
    case downloadFailed
    case installationFailed
    case noCertificateAvailable
    
    public var errorDescription: String? {
        switch self {
        case .rotationNotNeeded:
            return "Certificate rotation is not currently needed"
        case .downloadFailed:
            return "Failed to download new certificate from server"
        case .installationFailed:
            return "Failed to install new certificate"
        case .noCertificateAvailable:
            return "No certificate available for rotation"
        }
    }
}