//
//  CertificatesView.swift
//  mTLSDemo
//
//  Certificate Management Interface
//

import SwiftUI

struct CertificatesView: View {
    @StateObject private var certificateManager = CertificateManager.shared
    @StateObject private var rotationService = CertificateRotationService.shared
    @StateObject private var enrollmentService = EnrollmentService.shared
    @State private var showingCleanupAlert = false
    @State private var showingEnrollAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if certificateManager.isLoading {
                    ProgressView("Loading certificates...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            currentCertificateSection

                            rotationStatusSection

                            enrollmentStatusSection

                            certificateListSection
                            
                            actionButtonsSection
                        }
                        .padding(.horizontal)
                        .padding(.top)
                    }
                }
            }
            .navigationTitle("Certificates")
            .refreshable {
                await certificateManager.loadCertificates()
                await rotationService.checkRotationNeeded()
            }
            .alert("Cleanup Expired", isPresented: $showingCleanupAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Cleanup", role: .destructive) {
                    Task {
                        await certificateManager.cleanupExpiredCertificates()
                    }
                }
            } message: {
                Text("This will remove all expired certificates from the keychain. This action cannot be undone.")
            }
            .alert("Enroll New Certificate", isPresented: $showingEnrollAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Enroll") {
                    Task {
                        await performEnrollment()
                    }
                }
            } message: {
                Text("This will generate a new keypair in the Secure Enclave and request a certificate from the server. The private key will never leave the device.")
            }
        }
        .task {
            await certificateManager.loadCertificates()
            await rotationService.checkRotationNeeded()
            enrollmentService.resetEnrollment()
        }
    }

    private func performEnrollment() async {
        do {
            let certificateInfo = try await certificateManager.enrollCertificate()
            // Enrollment successful, refresh the certificate list
            await certificateManager.loadCertificates()
            await rotationService.checkRotationNeeded()
        } catch {
            // Error is already handled by the enrollment service and displayed in the UI
            print("Enrollment failed: \(error)")
        }
    }
    
    private var currentCertificateSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                Text("Current Certificate")
                    .font(.headline)
                Spacer()
            }
            
            if let currentCert = certificateManager.currentCertificate {
                CertificateCard(certificate: currentCert, isCurrentCertificate: true)
            } else {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "No Valid Certificate",
                    message: "No valid certificate is currently available for mTLS authentication."
                )
            }
        }
    }
    
    private var rotationStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text("Rotation Status")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(rotationService.rotationStatus)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(rotationStatusColor)
                }
                
                if rotationService.rotationRequired {
                    Label("Rotation Required", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if rotationService.rotationRecommended {
                    Label("Rotation Recommended", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if let lastCheck = rotationService.lastCheckDate {
                    HStack {
                        Text("Last Check:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var enrollmentStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.green)
                Text("Certificate Enrollment")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                // Enrollment status
                HStack {
                    Text("Status:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(enrollmentService.enrollmentState.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(enrollmentStatusColor)
                }

                // Progress indicator if active
                if enrollmentService.enrollmentState.isActive {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: enrollmentProgressValue, total: 1.0)
                            .progressViewStyle(.linear)

                        Text(enrollmentService.enrollmentProgress)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Error display
                if let error = enrollmentService.enrollmentError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(nil)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                // Enroll button
                if !enrollmentService.enrollmentState.isActive {
                    Button(action: {
                        showingEnrollAlert = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Request New Certificate")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var certificateListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.circle")
                    .foregroundColor(.green)
                Text("All Certificates")
                    .font(.headline)
                Spacer()
                Text("\(certificateManager.certificates.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            
            if certificateManager.certificates.isEmpty {
                EmptyStateView(
                    icon: "doc.badge.plus",
                    title: "No Certificates",
                    message: "No certificates found in bundle or keychain."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(certificateManager.certificates, id: \.commonName) { certificate in
                        CertificateCard(
                            certificate: certificate,
                            isCurrentCertificate: certificate.commonName == certificateManager.currentCertificate?.commonName
                        )
                    }
                }
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        await certificateManager.loadCertificates()
                        await rotationService.checkRotationNeeded()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    showingCleanupAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Cleanup Expired")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
        .padding(.bottom)
    }
    
    private var rotationStatusColor: Color {
        if rotationService.rotationRequired {
            return .red
        } else if rotationService.rotationRecommended {
            return .orange
        } else {
            return .green
        }
    }

    private var enrollmentStatusColor: Color {
        switch enrollmentService.enrollmentState {
        case .idle:
            return .gray
        case .starting, .generatingKeys, .generatingCSR, .submittingCSR, .receivingCertificate:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var enrollmentProgressValue: Double {
        switch enrollmentService.enrollmentState {
        case .idle:
            return 0.0
        case .starting:
            return 0.1
        case .generatingKeys:
            return 0.3
        case .generatingCSR:
            return 0.5
        case .submittingCSR:
            return 0.7
        case .receivingCertificate:
            return 0.9
        case .completed:
            return 1.0
        case .failed:
            return 0.0
        }
    }
}

struct CertificateCard: View {
    let certificate: CertificateInfo
    let isCurrentCertificate: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(certificate.commonName)
                            .font(.headline)
                            .lineLimit(1)
                        
                        if isCurrentCertificate {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        StatusBadge(status: certificate.expiryStatus)
                    }
                    
                    Text("\(certificate.organization) • \(certificate.organizationalUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Divider()
            
            VStack(spacing: 4) {
                InfoRow(label: "Source", value: sourceDisplayText)
                InfoRow(label: "Valid Until", value: certificate.validTo, style: .date)
                InfoRow(label: "Days Left", value: "\(certificate.daysUntilExpiry)")
                InfoRow(label: "Fingerprint", value: String(certificate.fingerprint.prefix(16)) + "...")
            }
        }
        .padding()
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isCurrentCertificate ? 2 : 1)
        )
    }
    
    private var sourceDisplayText: String {
        switch certificate.source {
        case .bundle:
            return "App Bundle"
        case .keychain:
            return "Keychain"
        case .downloaded:
            return "Downloaded"
        }
    }
    
    private var cardBackgroundColor: Color {
        if isCurrentCertificate {
            return Color.blue.opacity(0.05)
        } else {
            return Color.white
        }
    }
    
    private var borderColor: Color {
        if isCurrentCertificate {
            return .blue
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

struct StatusBadge: View {
    let status: ExpiryStatus
    
    var body: some View {
        Text(status.displayText)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(6)
    }
    
    private var backgroundColor: Color {
        switch status {
        case .valid:
            return .green.opacity(0.2)
        case .rotationRequired:
            return .orange.opacity(0.2)
        case .expiresSoon:
            return .red.opacity(0.2)
        case .expired:
            return .gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .valid:
            return .green
        case .rotationRequired:
            return .orange
        case .expiresSoon:
            return .red
        case .expired:
            return .gray
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String?
    let dateValue: Date?
    let dateStyle: Text.DateStyle?

    init(label: String, value: String) {
        self.label = label
        self.value = value
        self.dateValue = nil
        self.dateStyle = nil
    }
    
    init(label: String, value: Date, style: Text.DateStyle) {
        self.label = label
        self.value = nil
        self.dateValue = value
        self.dateStyle = style
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let dateValue = dateValue, let dateStyle = dateStyle {
                Text(dateValue, style: dateStyle)
                    .font(.caption)
                    .fontWeight(.medium)
            } else if let value = value {
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
    }
}