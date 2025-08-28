//
//  NetworkView.swift
//  mTLSDemo
//
//  Network Testing Interface
//

import SwiftUI

struct NetworkView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var showingResponseDetail = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    connectionStatusSection
                    
                    networkActionsSection
                    
                    responseSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Network")
            .refreshable {
                await networkService.testHealth()
            }
        }
    }
    
    private var connectionStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                Text("Connection Status")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: connectionStatusIcon)
                        .foregroundColor(connectionStatusColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(networkService.connectionStatus)
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 12, height: 12)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                if let error = networkService.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var networkActionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "play.circle")
                    .foregroundColor(.green)
                Text("Network Tests")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                NetworkActionButton(
                    title: "Test Health",
                    description: "Basic connectivity test",
                    icon: "heart.circle",
                    action: {
                        await networkService.testHealth()
                    }
                )
                
                NetworkActionButton(
                    title: "Get Client Info",
                    description: "Retrieve mTLS client certificate details",
                    icon: "person.crop.circle.badge.checkmark",
                    action: {
                        await networkService.getClientInfo()
                    }
                )
                
                NetworkActionButton(
                    title: "Get Secure Data",
                    description: "Fetch protected data using mTLS",
                    icon: "lock.shield",
                    action: {
                        await networkService.getSecureData()
                    }
                )
                
                NetworkActionButton(
                    title: "Check Certificate Status",
                    description: "Verify certificate expiry and rotation status",
                    icon: "doc.badge.clock",
                    action: {
                        await networkService.checkCertificateStatus()
                    }
                )
            }
        }
    }
    
    private var responseSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.purple)
                Text("Last Response")
                    .font(.headline)
                Spacer()
                
                if networkService.lastResponse != nil {
                    Button("View Details") {
                        showingResponseDetail = true
                    }
                    .font(.caption)
                }
            }
            
            if let response = networkService.lastResponse {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(response)
                            .font(.system(size: 12, design: .monospaced))
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if response.count > 200 {
                        Text("Response truncated. Tap 'View Details' for full content.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                EmptyStateView(
                    icon: "doc.text.below.ecg",
                    title: "No Response Yet",
                    message: "Execute a network test to see the server response here."
                )
            }
        }
        .sheet(isPresented: $showingResponseDetail) {
            ResponseDetailView(response: networkService.lastResponse ?? "")
        }
    }
    
    private var connectionStatusIcon: String {
        networkService.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var connectionStatusColor: Color {
        networkService.isConnected ? .green : .red
    }
}

struct NetworkActionButton: View {
    let title: String
    let description: String
    let icon: String
    let action: () async -> Void
    
    @State private var isLoading = false
    
    var body: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(isLoading)
    }
}

struct ResponseDetailView: View {
    let response: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(response)
                    .font(.system(size: 12, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Response Details")
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