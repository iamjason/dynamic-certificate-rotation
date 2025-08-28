#!/bin/bash

set -e

SERVER_DIR="$(cd "$(dirname "$0")/../server" && pwd)"
PKI_DIR="$(cd "$(dirname "$0")/../pki" && pwd)"

echo "🚀 Starting mTLS Demo Server"
echo "=========================="

if [[ ! -f "$PKI_DIR/certs/ca-cert.pem" ]]; then
    echo "❌ PKI certificates not found. Running setup-pki.sh first..."
    echo ""
    "$(dirname "$0")/setup-pki.sh"
    echo ""
fi

echo "📦 Installing dependencies..."
cd "$SERVER_DIR"

if [[ ! -f "package.json" ]]; then
    echo "❌ server/package.json not found. Please ensure the server is implemented."
    exit 1
fi

npm install

echo ""
echo "🔐 Certificate Status:"
echo "   CA Certificate: $PKI_DIR/certs/ca-cert.pem"
echo "   Server Certificate: $PKI_DIR/certs/server-cert.pem"
echo "   Server Key: $PKI_DIR/private/server-key.pem"

echo ""
echo "🌐 Starting HTTPS server on port 8443..."
echo "   URL: https://localhost:8443"
echo ""

npm start &
SERVER_PID=$!

sleep 2

if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "✅ Server started successfully (PID: $SERVER_PID)"
else
    echo "❌ Server failed to start"
    exit 1
fi

echo ""
echo "📡 Available Endpoints:"
echo "   GET /health                           - Health check"
echo "   GET /api/client-info                  - Client certificate information"
echo "   GET /api/secure-data                  - Protected data"
echo "   GET /api/certificates/current         - Current certificate status"
echo "   GET /api/certificates/download/:name  - Download certificate bundle"
echo ""
echo "🧪 Test Commands:"
echo ""
echo "# Health check:"
echo "curl --cert $PKI_DIR/certs/ios-client-v1-cert.pem \\"
echo "     --key $PKI_DIR/private/ios-client-v1-key.pem \\"
echo "     --cacert $PKI_DIR/certs/ca-cert.pem \\"
echo "     https://localhost:8443/health"
echo ""
echo "# Client info:"
echo "curl --cert $PKI_DIR/certs/ios-client-v1-cert.pem \\"
echo "     --key $PKI_DIR/private/ios-client-v1-key.pem \\"
echo "     --cacert $PKI_DIR/certs/ca-cert.pem \\"
echo "     https://localhost:8443/api/client-info"
echo ""
echo "# Test without client certificate (should fail):"
echo "curl --cacert $PKI_DIR/certs/ca-cert.pem \\"
echo "     https://localhost:8443/health"
echo ""
echo "# Test in browser (should show client certificate error):"
echo "open https://localhost:8443"
echo ""
echo "Press Ctrl+C to stop the server..."

wait $SERVER_PID