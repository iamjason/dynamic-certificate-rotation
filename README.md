# mTLS Demo with Dynamic Certificate Rotation

A complete demonstration project showcasing Mutual TLS (mTLS) authentication with dynamic certificate pinning and certificate rotation between an iOS SwiftUI app and a Node.js HTTPS server.

## 🎯 Features

- **Mutual TLS Authentication**: Client and server authenticate each other using X.509 certificates
- **Certificate Pinning**: iOS app validates server certificates against a pinned CA
- **Dynamic Certificate Rotation**: Automatic detection and handling of certificate expiry
- **Swift 6.1 & SwiftUI**: Modern iOS development with Swift Package Manager architecture
- **TLS 1.3 Support**: Latest TLS protocol with secure cipher suites
- **Real-time Monitoring**: Certificate status monitoring and rotation alerts

## 🏗️ Architecture

```
├── server/                     # Node.js mTLS server
│   ├── server.js              # Express HTTPS server with mTLS
│   └── package.json           # Dependencies and scripts
├── scripts/                   # PKI and server management
│   ├── setup-pki.sh          # Generate CA, server, and client certificates
│   ├── rotate-client-cert.sh # Create new client certificate
│   ├── cert-info.sh          # Display certificate information
│   └── start-server.sh       # Start server with dependencies
├── pki/                       # PKI infrastructure
│   ├── certs/                # CA, server, and client certificates
│   └── private/              # Private keys
├── mTLSDemo.xcworkspace/      # Xcode workspace
├── mTLSDemoApp/              # iOS app target (minimal)
└── mTLSDemoPackage/          # Swift Package with all logic
    └── Sources/mTLSDemoFeature/
        ├── Models/           # Certificate models and data structures
        ├── Services/         # Certificate, Network, and Rotation services
        └── Views/           # SwiftUI views with three tabs
```

## 🚀 Quick Start

### 1. Generate Certificates

```bash
./scripts/setup-pki.sh
```

This creates:
- Root CA certificate and private key
- Server certificate for `localhost:8443`
- Two iOS client certificates (`ios-client-v1`, `ios-client-v2`)
- PKCS#12 bundles for iOS (password: `demo123`)

### 2. Start the Server

```bash
./scripts/start-server.sh
```

The server runs on `https://localhost:8443` with the following endpoints:
- `GET /health` - Basic health check
- `GET /api/client-info` - Client certificate details
- `GET /api/secure-data` - Protected data endpoint  
- `GET /api/certificates/current` - Certificate status
- `GET /api/certificates/download/:name` - Download certificate bundle

### 3. Test with curl

```bash
# Test with client certificate
curl --cert pki/certs/ios-client-v1-cert.pem \\
     --key pki/private/ios-client-v1-key.pem \\
     --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/api/client-info

# Test without client certificate (should fail)
curl --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/health
```

### 4. Build and Run iOS App

1. Open `mTLSDemo.xcworkspace` in Xcode
2. Build and run on iOS Simulator or device
3. The app includes three tabs:
   - **Certificates**: View and manage client certificates
   - **Network**: Test mTLS connections to the server
   - **Demo**: Run complete end-to-end demonstration

## 📱 iOS App Features

### Certificates Tab
- Current certificate display with validity status
- Certificate rotation status and recommendations
- List of all available certificates (bundle + keychain)
- Certificate cleanup and refresh functionality

### Network Tab
- Connection status indicator
- Interactive API endpoint testing
- Real-time response display
- Error handling and debugging information

### Demo Tab
- Guided step-by-step demonstration
- Progress tracking for each step:
  1. Load certificates
  2. Validate current certificate
  3. Test server connectivity
  4. Authenticate via mTLS
  5. Fetch secure data
  6. Check certificate status
  7. Evaluate rotation policy

## 🔐 Security Features

### Certificate Pinning
- iOS app validates server certificates against bundled CA
- Rejects connections to servers with invalid/untrusted certificates
- Protects against man-in-the-middle attacks

### Keychain Integration
- Secure storage of client certificates in iOS Keychain
- Device-only accessibility (not backed up to iCloud)
- Automatic certificate cleanup

### Mutual TLS
- Both client and server authenticate each other
- Server validates client certificates against trusted CA
- Client certificates stored securely in PKCS#12 format

### Rotation Policy
- Configurable rotation threshold (default: 14 days)
- Automatic monitoring of certificate expiry
- Server-side rotation status coordination
- Background certificate health checks

## 🛠️ Development

### PKI Management

```bash
# View certificate details
./scripts/cert-info.sh

# Create a new client certificate
./scripts/rotate-client-cert.sh ios-client-v3

# Regenerate all certificates (delete ca-cert.pem first)
rm pki/certs/ca-cert.pem
./scripts/setup-pki.sh
```

### Server Development

```bash
cd server
npm install
npm run dev  # Start with file watching
```

### iOS Development

The iOS app uses a Swift Package Manager architecture:
- Main app target is minimal (just launches the SwiftUI view)
- All business logic is in `mTLSDemoPackage`
- Supports modern Swift 6.1 concurrency and SwiftUI patterns

## 🧪 Testing

### Browser Testing
Opening `https://localhost:8443` in a browser should show:
`ERR_BAD_SSL_CLIENT_AUTH_CERT` - This is expected since browsers don't provide client certificates.

### Certificate Validation
```bash
# Verify certificate chain
openssl verify -CAfile pki/certs/ca-cert.pem pki/certs/server-cert.pem
openssl verify -CAfile pki/certs/ca-cert.pem pki/certs/ios-client-v1-cert.pem

# Check certificate details
openssl x509 -in pki/certs/server-cert.pem -text -noout
openssl pkcs12 -in pki/certs/ios-client-v1.p12 -info -noout
```

### Network Testing
```bash
# Test TLS handshake
openssl s_client -connect localhost:8443 \\
  -cert pki/certs/ios-client-v1-cert.pem \\
  -key pki/private/ios-client-v1-key.pem \\
  -CAfile pki/certs/ca-cert.pem
```

## 🎯 Demo Scenarios

1. **Basic mTLS Connection**: App connects to server using bundled client certificate
2. **Certificate Rotation**: Demonstrate rotation when certificate nears expiry
3. **CA Pinning**: Show connection failure with invalid server certificate  
4. **Multi-Certificate Management**: Switch between different client certificates
5. **Expiry Handling**: Automatic cleanup of expired certificates

## 📋 Requirements

- **Server**: Node.js 18+ with OpenSSL
- **iOS**: Xcode 15+, iOS 17+, Swift 6.1
- **Development**: macOS with command line tools

## 🔍 Troubleshooting

### Common Issues

**Server won't start**:
- Check if certificates exist: `ls pki/certs/`
- Run `./scripts/setup-pki.sh` if certificates are missing
- Verify port 8443 is available

**iOS app can't connect**:
- Ensure server is running on `localhost:8443`
- Check iOS Simulator can reach localhost
- Verify CA certificate is bundled in app

**Certificate errors**:
- Check certificate validity: `./scripts/cert-info.sh`
- Verify CA chain with `openssl verify`
- Ensure client certificate hasn't expired

**Keychain issues**:
- Reset iOS Simulator to clear keychain
- Check certificate installation logs
- Verify proper PKCS#12 format and password

See [DEMO_GUIDE.md](DEMO_GUIDE.md) for detailed step-by-step instructions.

## 📄 License

MIT License - see LICENSE file for details.

---

🔐 **Security Note**: This is a demonstration project. In production environments, use proper certificate authorities, secure key storage, and follow your organization's security policies.