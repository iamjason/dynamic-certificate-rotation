//
//  MainView.swift
//  mTLSDemo
//
//  Main Three-Tab Interface for mTLS Demo
//

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            CertificatesView()
                .tabItem {
                    Image(systemName: "doc.badge.gearshape.fill")
                    Text("Certificates")
                }
            
            NetworkView()
                .tabItem {
                    Image(systemName: "network")
                    Text("Network")
                }
            
            DemoView()
                .tabItem {
                    Image(systemName: "play.rectangle.on.rectangle")
                    Text("Demo")
                }
        }
        .preferredColorScheme(.light)
    }
}