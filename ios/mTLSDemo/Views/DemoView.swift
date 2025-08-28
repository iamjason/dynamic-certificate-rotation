//
//  DemoView.swift
//  mTLSDemo
//
//  Complete Demo Flow Interface
//

import SwiftUI

struct DemoView: View {
    @StateObject private var certificateManager = CertificateManager.shared
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var rotationService = CertificateRotationService.shared
    
    @State private var demoSteps: [DemoStep] = []
    @State private var currentStepIndex = 0
    @State private var isDemoRunning = false
    @State private var demoCompleted = false
    @State private var showingDemoResults = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    demoHeaderSection
                    
                    if isDemoRunning || demoCompleted {
                        demoProgressSection
                    } else {
                        demoDescriptionSection
                    }
                    
                    demoControlSection
                    
                    if demoCompleted {
                        demoResultsSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Full Demo")
            .sheet(isPresented: $showingDemoResults) {
                DemoResultsView(steps: demoSteps)
            }
        }
        .onAppear {
            setupDemoSteps()
        }
    }
    
    private var demoHeaderSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("mTLS Demo Flow")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Complete end-to-end demonstration of mutual TLS authentication with certificate rotation")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
    }
    
    private var demoDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.green)
                Text("Demo Steps")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(demoSteps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.blue))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text(step.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    private var demoProgressSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.orange)
                Text("Demo Progress")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                ProgressView(value: Double(currentStepIndex), total: Double(demoSteps.count))
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text("Step \(currentStepIndex) of \(demoSteps.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if demoCompleted {
                        Text("Completed")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    } else if isDemoRunning {
                        Text("Running...")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                
                if currentStepIndex < demoSteps.count {
                    let currentStep = demoSteps[currentStepIndex]
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: currentStep.status.icon)
                                .foregroundColor(currentStep.status.color)
                            
                            Text(currentStep.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if currentStep.status == .running {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        
                        Text(currentStep.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if let result = currentStep.result {
                            Text(result)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(currentStep.status == .completed ? .green : .red)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var demoControlSection: some View {
        VStack(spacing: 12) {
            if !isDemoRunning && !demoCompleted {
                Button {
                    startDemo()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Full Demo")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
            
            if demoCompleted {
                HStack(spacing: 12) {
                    Button {
                        showingDemoResults = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View Results")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button {
                        resetDemo()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Reset Demo")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }
            
            if isDemoRunning {
                Button {
                    stopDemo()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Demo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var demoResultsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Demo Results")
                    .font(.headline)
                Spacer()
            }
            
            let completedSteps = demoSteps.filter { $0.status == .completed }.count
            let failedSteps = demoSteps.filter { $0.status == .failed }.count
            
            VStack(spacing: 12) {
                HStack {
                    Text("Completed Steps:")
                    Spacer()
                    Text("\(completedSteps)/\(demoSteps.count)")
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                if failedSteps > 0 {
                    HStack {
                        Text("Failed Steps:")
                        Spacer()
                        Text("\(failedSteps)")
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                }
                
                HStack {
                    Text("Success Rate:")
                    Spacer()
                    Text(String(format: "%.1f%%", Double(completedSteps) / Double(demoSteps.count) * 100))
                        .fontWeight(.bold)
                        .foregroundColor(failedSteps == 0 ? .green : .orange)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func setupDemoSteps() {
        demoSteps = [
            DemoStep(
                title: "Load Certificates",
                description: "Load and validate client certificates from bundle and keychain",
                status: .pending
            ),
            DemoStep(
                title: "Validate Current Certificate",
                description: "Ensure a valid certificate is available for authentication",
                status: .pending
            ),
            DemoStep(
                title: "Test Server Connectivity",
                description: "Verify HTTPS connection to mTLS server with CA pinning",
                status: .pending
            ),
            DemoStep(
                title: "Authenticate via mTLS",
                description: "Perform mutual TLS authentication using client certificate",
                status: .pending
            ),
            DemoStep(
                title: "Fetch Secure Data",
                description: "Request protected data from authenticated endpoint",
                status: .pending
            ),
            DemoStep(
                title: "Check Certificate Status",
                description: "Verify certificate expiry and rotation requirements",
                status: .pending
            ),
            DemoStep(
                title: "Evaluate Rotation Policy",
                description: "Determine if certificate rotation is needed",
                status: .pending
            )
        ]
    }
    
    private func startDemo() {
        isDemoRunning = true
        demoCompleted = false
        currentStepIndex = 0
        
        Task {
            await runDemoSteps()
        }
    }
    
    private func stopDemo() {
        isDemoRunning = false
        
        for i in currentStepIndex..<demoSteps.count {
            demoSteps[i].status = .pending
            demoSteps[i].result = nil
        }
    }
    
    private func resetDemo() {
        isDemoRunning = false
        demoCompleted = false
        currentStepIndex = 0
        
        for i in 0..<demoSteps.count {
            demoSteps[i].status = .pending
            demoSteps[i].result = nil
        }
    }
    
    private func runDemoSteps() async {
        for i in 0..<demoSteps.count {
            guard isDemoRunning else { break }
            
            currentStepIndex = i
            demoSteps[i].status = .running
            
            await MainActor.run {
                // Trigger UI update
            }
            
            let success = await executeStep(i)
            
            demoSteps[i].status = success ? .completed : .failed
            
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        }
        
        isDemoRunning = false
        demoCompleted = true
        currentStepIndex = demoSteps.count
    }
    
    private func executeStep(_ stepIndex: Int) async -> Bool {
        switch stepIndex {
        case 0: // Load Certificates
            await certificateManager.loadCertificates()
            let success = !certificateManager.certificates.isEmpty
            demoSteps[stepIndex].result = success ? "Loaded \(certificateManager.certificates.count) certificates" : "No certificates found"
            return success
            
        case 1: // Validate Current Certificate
            let success = certificateManager.currentCertificate != nil
            demoSteps[stepIndex].result = success ? "Valid certificate: \(certificateManager.currentCertificate?.commonName ?? "")" : "No valid certificate available"
            return success
            
        case 2: // Test Server Connectivity
            await networkService.testHealth()
            let success = networkService.isConnected
            demoSteps[stepIndex].result = success ? "Server connected successfully" : "Connection failed: \(networkService.error ?? "Unknown error")"
            return success
            
        case 3: // Authenticate via mTLS
            await networkService.getClientInfo()
            let success: Bool = {
                if let text = networkService.lastResponse,
                   let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let authenticated = json["authenticated"] as? Bool {
                    return authenticated
                }
                // Fallback to a whitespace-agnostic string check for pretty-printed JSON
                let compact = networkService.lastResponse?
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "\n", with: "") ?? ""
                return compact.contains("\"authenticated\":true")
            }()
            demoSteps[stepIndex].result = success ? "mTLS authentication successful" : "Authentication failed"
            return success
            
        case 4: // Fetch Secure Data
            await networkService.getSecureData()
            let success = networkService.lastResponse?.contains("secretValue") ?? false
            demoSteps[stepIndex].result = success ? "Secure data retrieved" : "Failed to fetch secure data"
            return success
            
        case 5: // Check Certificate Status
            await networkService.checkCertificateStatus()
            let success = networkService.lastResponse?.contains("daysUntilExpiry") ?? false
            demoSteps[stepIndex].result = success ? "Certificate status checked" : "Status check failed"
            return success
            
        case 6: // Evaluate Rotation Policy
            await rotationService.checkRotationNeeded()
            let result = rotationService.rotationRequired ? "Rotation required" : (rotationService.rotationRecommended ? "Rotation recommended" : "Certificate valid")
            demoSteps[stepIndex].result = result
            return true
            
        default:
            return false
        }
    }
}

struct DemoStep {
    let title: String
    let description: String
    var status: DemoStepStatus
    var result: String?
    
    init(title: String, description: String, status: DemoStepStatus) {
        self.title = title
        self.description = description
        self.status = status
        self.result = nil
    }
}

enum DemoStepStatus {
    case pending
    case running
    case completed
    case failed
    
    var icon: String {
        switch self {
        case .pending:
            return "circle"
        case .running:
            return "clock"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .pending:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

struct DemoResultsView: View {
    let steps: [DemoStep]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Step \(index + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Image(systemName: step.status.icon)
                                .foregroundColor(step.status.color)
                        }
                        
                        Text(step.title)
                            .font(.headline)
                        
                        Text(step.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if let result = step.result {
                            Text(result)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(step.status.color)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Demo Results")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}