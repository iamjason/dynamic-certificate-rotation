# mTLS Demo Guide

This guide walks you through setting up and running the complete mTLS demonstration with dynamic certificate rotation.

## 📋 Prerequisites

- macOS with Xcode 15+
- Node.js 18+ installed
- OpenSSL available in PATH
- iOS Simulator or physical iOS device

## 🎬 Step-by-Step Demo

### Phase 1: Environment Setup

#### 1.1 Generate PKI Infrastructure

```bash
# Navigate to project directory
cd dynamic-certificate-rotation

# Generate all certificates and keys
./scripts/setup-pki.sh
```

**Expected Output:**
```
🔧 Setting up PKI infrastructure...
📋 Generating Certificate Authority (CA)...
🖥️  Generating Server Certificate...
📱 Generating Client Certificate: ios-client-v1...
📦 Creating PKCS#12 bundle for ios-client-v1...
📱 Generating Client Certificate: ios-client-v2...
📦 Creating PKCS#12 bundle for ios-client-v2...
✅ PKI Setup Complete!
```

#### 1.2 Verify Certificate Generation

```bash
# View certificate details
./scripts/cert-info.sh
```

**What to Look For:**
- CA certificate valid for 10 years
- Server certificate valid for 1 year with `localhost` SAN
- Client certificates valid for 90 days
- PKCS#12 bundles created with password `demo123`

#### 1.3 Start the mTLS Server

```bash
# Start server with automatic dependency installation
./scripts/start-server.sh
```

**Expected Output:**
```
🚀 mTLS Demo Server Starting...
🌐 Server running on https://localhost:8443
🔐 Mutual TLS authentication required

📡 Available endpoints:
  GET /health                           - Health check
  GET /api/client-info                  - Client certificate information
  GET /api/secure-data                  - Protected data
  GET /api/certificates/current         - Current certificate status
  GET /api/certificates/download/:name  - Download certificate bundle
```

### Phase 2: Server Validation

#### 2.1 Test Basic Connectivity

```bash
# Test with valid client certificate
curl --cert pki/certs/ios-client-v1-cert.pem \\
     --key pki/private/ios-client-v1-key.pem \\
     --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/health
```

**Expected Response:**
```json
{"status":"ok"}
```

**Server Log Should Show:**
```
✅ Client authenticated: ios-client-v1 (mTLS Demo iOS)
```

#### 2.2 Test mTLS Requirement

```bash
# Test without client certificate (should fail)
curl --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/health
```

**Expected Result:** Connection refused or SSL handshake failure

#### 2.3 Test Client Certificate Info

```bash
curl --cert pki/certs/ios-client-v1-cert.pem \\
     --key pki/private/ios-client-v1-key.pem \\
     --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/api/client-info
```

**Expected Response:**
```json
{
  "authenticated": true,
  "client": {
    "commonName": "ios-client-v1",
    "organization": "mTLS Demo iOS",
    "organizationalUnit": "Mobile"
  },
  "certificate": {
    "validFrom": "Dec  1 10:30:00 2024 GMT",
    "validTo": "Mar  1 10:30:00 2025 GMT",
    "fingerprint": "AA:BB:CC:...",
    "serialNumber": "..."
  }
}
```

#### 2.4 Test Certificate Status Endpoint

```bash
curl --cert pki/certs/ios-client-v1-cert.pem \\
     --key pki/private/ios-client-v1-key.pem \\
     --cacert pki/certs/ca-cert.pem \\
     https://localhost:8443/api/certificates/current
```

**Expected Response:**
```json
{
  "certName": "ios-client-v1",
  "validTo": "Mar  1 10:30:00 2025 GMT",
  "daysUntilExpiry": 89,
  "rotationRequired": false,
  "rotationRecommended": false
}
```

### Phase 3: iOS App Demo

#### 3.1 Build and Launch iOS App

1. Open `mTLSDemo.xcworkspace` in Xcode
2. Select iOS Simulator (iPhone 15 Pro recommended)
3. Build and run the project (⌘+R)

**Expected Result:** App launches showing three-tab interface

#### 3.2 Certificates Tab Walkthrough

1. **Current Certificate Section:**
   - Shows active certificate (`ios-client-v1` or `ios-client-v2`)
   - Displays source (App Bundle)
   - Shows validity status and days until expiry

2. **Rotation Status Section:**
   - Current rotation status
   - Rotation required/recommended indicators
   - Last check timestamp

3. **Certificate List:**
   - All available certificates from bundle and keychain
   - Certificate details and expiry information

4. **Actions:**
   - **Refresh**: Reload certificates and check rotation status
   - **Cleanup Expired**: Remove expired certificates from keychain

#### 3.3 Network Tab Walkthrough

1. **Connection Status:**
   - Shows current server connection status
   - TLS protocol version information
   - Error messages if connection fails

2. **Network Tests:**
   
   **Test Health:**
   - Tap "Test Health" button
   - Should show "Connected" status
   - Response shows `{"status":"ok"}`

   **Get Client Info:**
   - Tap "Get Client Info" button
   - Response shows authenticated client details
   - Verify mTLS authentication success

   **Get Secure Data:**
   - Tap "Get Secure Data" button
   - Response includes protected payload
   - Demonstrates successful authorization

   **Check Certificate Status:**
   - Tap "Check Certificate Status" button
   - Shows server-side certificate validation
   - Displays rotation requirements

#### 3.4 Demo Tab Complete Flow

1. **Tap "Run Full Demo"**

2. **Watch Step-by-Step Progress:**
   
   **Step 1: Load Certificates**
   - ✅ Should complete successfully
   - Result: "Loaded 2 certificates"

   **Step 2: Validate Current Certificate**
   - ✅ Should find valid certificate
   - Result: "Valid certificate: ios-client-v1"

   **Step 3: Test Server Connectivity**
   - ✅ Should connect to server
   - Result: "Server connected successfully"

   **Step 4: Authenticate via mTLS**
   - ✅ Should authenticate with client cert
   - Result: "mTLS authentication successful"

   **Step 5: Fetch Secure Data**
   - ✅ Should retrieve protected data
   - Result: "Secure data retrieved"

   **Step 6: Check Certificate Status**
   - ✅ Should get certificate expiry info
   - Result: "Certificate status checked"

   **Step 7: Evaluate Rotation Policy**
   - ✅ Should determine rotation needs
   - Result: "Certificate valid" or "Rotation recommended"

3. **Review Results:**
   - Tap "View Results" for detailed breakdown
   - Success rate should be 100%
   - All steps should show green checkmarks

### Phase 4: Certificate Rotation Demo

#### 4.1 Force Certificate Rotation

```bash
# Create a short-lived certificate for testing
./scripts/rotate-client-cert.sh ios-client-short-lived

# Manually edit the certificate validity (advanced)
# Or wait for certificate to approach expiry threshold
```

#### 4.2 Observe Rotation Behavior

1. **In iOS App (Certificates Tab):**
   - Rotation status should change to "Rotation Required"
   - Certificate card should show warning badge
   - Rotation threshold warnings appear

2. **Test Rotation Detection:**
   - Rotation service automatically detects expiry
   - Background monitoring updates status
   - UI reflects rotation requirements

### Phase 5: Security Validation

#### 5.1 Test CA Pinning

1. **Temporarily Replace CA Certificate:**
```bash
# Backup original CA
cp pki/certs/ca-cert.pem pki/certs/ca-cert.pem.backup

# Generate invalid CA (for testing)
openssl req -new -x509 -key pki/private/ca-key.pem \\
  -out pki/certs/ca-cert-invalid.pem -days 1 \\
  -subj "/CN=Invalid CA"

# Restart server with invalid CA
# iOS app should reject connection
```

2. **Expected Behavior:**
   - iOS app shows "Server certificate validation failed"
   - Connection refused due to CA pinning
   - Error message about CA mismatch

3. **Restore Valid CA:**
```bash
cp pki/certs/ca-cert.pem.backup pki/certs/ca-cert.pem
```

#### 5.2 Test Without Client Certificate

1. **Modify server to simulate missing client cert**
2. **Expected Behavior:**
   - Server rejects connection
   - iOS app shows "No client certificate available"
   - mTLS authentication fails

#### 5.3 Browser Testing

1. **Open browser to `https://localhost:8443`**
2. **Expected Result:**
   - `ERR_BAD_SSL_CLIENT_AUTH_CERT`
   - Connection refused (no client certificate)
   - This confirms mTLS is working properly

## 🎯 Demo Scenarios

### Scenario A: Basic mTLS Flow
1. Start server
2. Launch iOS app
3. Run full demo
4. Verify all steps complete successfully

### Scenario B: Certificate Management
1. View all certificates in app
2. Test with different client certificates
3. Cleanup expired certificates
4. Refresh certificate list

### Scenario C: Network Testing
1. Test each endpoint individually
2. Examine response data
3. Verify connection status
4. Handle network errors gracefully

### Scenario D: Rotation Workflow
1. Monitor certificate expiry
2. Detect rotation requirements
3. Download new certificates
4. Install and activate new certs

## 🔧 Troubleshooting

### Issue: "Certificate not found" 
**Solution:** Run `./scripts/setup-pki.sh` to regenerate certificates

### Issue: "Connection refused"
**Solution:** Ensure server is running on port 8443

### Issue: "CA pinning failed"
**Solution:** Verify CA certificate is properly bundled in iOS app

### Issue: "Client certificate invalid"
**Solution:** Check certificate hasn't expired with `./scripts/cert-info.sh`

### Issue: iOS Simulator networking issues
**Solution:** 
- Reset iOS Simulator
- Check localhost accessibility
- Restart development server

## 📈 Success Criteria

By the end of this demo, you should have:

- ✅ Generated complete PKI infrastructure
- ✅ Running mTLS server with all endpoints
- ✅ iOS app successfully authenticating with server
- ✅ Certificate pinning preventing invalid connections
- ✅ Automatic certificate rotation detection
- ✅ Complete step-by-step demo flow working
- ✅ Understanding of mTLS security benefits
- ✅ Knowledge of certificate lifecycle management

## 🚀 Next Steps

After completing this demo:

1. **Explore Advanced Features:**
   - Certificate revocation lists (CRL)
   - Online Certificate Status Protocol (OCSP)
   - Hardware security modules (HSM)

2. **Production Considerations:**
   - Use real Certificate Authority
   - Implement proper key storage
   - Add certificate backup/recovery
   - Monitor certificate health

3. **Enhanced Security:**
   - Add certificate transparency logging
   - Implement certificate rotation automation
   - Add intrusion detection
   - Monitor for certificate anomalies

---

🎉 **Congratulations!** You've successfully demonstrated a complete mTLS implementation with dynamic certificate rotation.