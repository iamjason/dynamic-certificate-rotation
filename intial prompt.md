Claude, generate a complete demo project that showcases Mutual TLS (mTLS) with dynamic certificate pinning and certificate rotation across an iOS app (SwiftUI) and a Node.js server.

GOAL
- iOS SwiftUI app authenticates to a local Node.js HTTPS server using client certificates (mTLS)
- App pins the server's CA, manages client certs securely, and supports rotation
- End-to-end working demo with simple UI, curl parity, and scripts to generate certs

TECH
- iOS: Swift 6.1+, SwiftUI, Swift Concurrency, SPM package architecture (workspace + package)
- Server: Node.js (Express or native https), TLS 1.3
- PKI: OpenSSL; PEM files for CA/server/client, PKCS#12 (.p12) bundles for iOS

REPO LAYOUT
- /server
  - server.js (HTTPS mTLS server)
  - package.json (start script)
- /scripts
  - setup-pki.sh (create CA, server cert, client certs, .p12)
  - rotate-client-cert.sh <name> (new client cert + .p12)
  - cert-info.sh (print cert details)
  - start-server.sh (install deps, start server)
- /pki
  - certs/ca-cert.pem, server-cert.pem, ios-client-v1-cert.pem, ios-client-v2-cert.pem
  - private/server-key.pem, ios-client-v1-key.pem, ios-client-v2-key.pem
  - client bundles: ios-client-v1.p12, ios-client-v2.p12 (password: demo123)
- /mTLSDemo.xcworkspace + /mTLSDemoPackage (all app logic in SPM package)

SERVER REQUIREMENTS (mTLS)
- HTTPS on https://localhost:8443
- TLS options:
  - key: pki/private/server-key.pem
  - cert: pki/certs/server-cert.pem
  - ca: pki/certs/ca-cert.pem
  - requestCert: true
  - rejectUnauthorized: true
- Endpoints (all require valid client cert):
  - GET /health → { status: "ok" }
  - GET /api/client-info → { authenticated, client: { commonName, org, ... }, certificate: { validFrom, validTo, issuer, fingerprint, serialNumber } }
  - GET /api/secure-data → sample protected payload
  - GET /api/certificates/current → { certName, validTo, rotationRequired: boolean }
  - GET /api/certificates/download/:certName → serve new client cert bundle (mock in demo)
- Console log: "✅ Client authenticated: <CN>"
- Provide curl samples:
  - curl --cert pki/certs/ios-client-v1-cert.pem \
         --key pki/private/ios-client-v1-key.pem \
         --cacert pki/certs/ca-cert.pem \
         https://localhost:8443/api/client-info

IOS APP REQUIREMENTS (SwiftUI)
- App entry target minimal; all code in SPM package `mTLSDemoFeature`
- Components:
  - CertificateManager: load bundled .p12, parse, validate, monitor expiry; install into Keychain; list all known certs
  - KeychainManager: secure storage for identity (SecIdentity), device-only access
  - NetworkService: URLSession with mTLS client identity; custom trust evaluator that pins server CA (read `ca-cert.pem` from bundle); hostname verification for "localhost"
  - CertificateRotationService: rotation policy: rotate N days before expiry (default 14). Checks `/api/certificates/current`, optionally fetches new cert, installs, removes old one
- UI (3 tabs):
  - Certificates tab: "Current Certificate" card (name, source: Bundle/Keychain, expires in X days, validity badge), list of all certificates, buttons [Refresh Certificates], [Cleanup Expired]
  - Network tab: buttons [Test Health], [Get Client Info], [Get Secure Data], [Check Certificate Status]; show responses and connectivity status
  - Demo tab: "Run Full Demo" that executes steps: Load certs → Connect → Authenticate via mTLS → Fetch Secure Data → Check Rotation; show step-by-step progress with green checkmarks
- Concurrency/style:
  - Use async/await, @MainActor for UI, actor or isolated services where appropriate
  - No ViewModels; use @State/@Observable per modern SwiftUI patterns
- Bundle the following for the demo:
  - `ios-client-v1.p12`, `ios-client-v2.p12` (password "demo123") and `ca-cert.pem`
- Error states: surface certificate validation failures and server pinning errors clearly

SCRIPTS
- setup-pki.sh: idempotent generation of CA, server cert, two iOS client certs (v1, v2), and .p12 bundles
- rotate-client-cert.sh <name>: generate and add a new client cert/bundle (e.g., ios-client-v3)
- cert-info.sh: print CN, validity window, issuer; list available .p12
- start-server.sh: `cd server && npm install && npm start`, then echo endpoint list and sample curl

DEMO BEHAVIOR
- Opening the server in a browser should fail with ERR_BAD_SSL_CLIENT_AUTH_CERT (expected; requires client cert)
- curl with proper client cert works and returns client info JSON
- iOS app connects successfully, authenticates with mTLS, and displays responses
- Rotation path: when under threshold, app detects rotationRequired and can fetch/install a newer cert (mock download ok)

ACCEPTANCE CRITERIA
- `./scripts/setup-pki.sh` produces CA/server/client certs and .p12 files
- `./scripts/start-server.sh` runs server at https://localhost:8443 with logs and endpoints
- curl commands succeed; missing/expired certs fail as expected
- iOS app shows certificates, performs mTLS calls, and passes full demo flow
- CA pinning blocks mismatched/invalid server certs

OUTPUT
- Full source code for server and iOS package
- All scripts under /scripts
- README.md and DEMO_GUIDE.md with quick start, curl samples, and troubleshooting