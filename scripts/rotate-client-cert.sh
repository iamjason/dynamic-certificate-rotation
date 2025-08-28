#!/bin/bash

set -e

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <client-name>"
    echo "Example: $0 ios-client-v3"
    exit 1
fi

CLIENT_NAME="$1"
PKI_DIR="$(cd "$(dirname "$0")/../pki" && pwd)"
CERTS_DIR="$PKI_DIR/certs"
PRIVATE_DIR="$PKI_DIR/private"

if [[ ! -f "$CERTS_DIR/ca-cert.pem" ]]; then
    echo "❌ CA certificate not found. Please run setup-pki.sh first."
    exit 1
fi

if [[ -f "$CERTS_DIR/${CLIENT_NAME}-cert.pem" ]]; then
    echo "⚠️  Client certificate $CLIENT_NAME already exists."
    echo "   This will overwrite the existing certificate."
    read -p "   Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Operation cancelled."
        exit 0
    fi
fi

echo "🔄 Rotating client certificate: $CLIENT_NAME"

echo "🔑 Generating new private key..."
openssl genrsa -out "$PRIVATE_DIR/${CLIENT_NAME}-key.pem" 2048

echo "📝 Creating certificate signing request..."
cat > "$PKI_DIR/${CLIENT_NAME}.conf" << EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = mTLS Demo iOS
OU = Mobile
CN = $CLIENT_NAME
EOF

openssl req -new -key "$PRIVATE_DIR/${CLIENT_NAME}-key.pem" \
    -out "$PKI_DIR/${CLIENT_NAME}.csr" \
    -config "$PKI_DIR/${CLIENT_NAME}.conf"

echo "🏆 Signing certificate with CA..."
openssl x509 -req -in "$PKI_DIR/${CLIENT_NAME}.csr" \
    -CA "$CERTS_DIR/ca-cert.pem" \
    -CAkey "$PRIVATE_DIR/ca-key.pem" \
    -CAcreateserial \
    -out "$CERTS_DIR/${CLIENT_NAME}-cert.pem" \
    -days 90 \
    -extensions usr_cert

echo "📦 Creating PKCS#12 bundle..."
openssl pkcs12 -export \
    -out "$CERTS_DIR/${CLIENT_NAME}.p12" \
    -inkey "$PRIVATE_DIR/${CLIENT_NAME}-key.pem" \
    -in "$CERTS_DIR/${CLIENT_NAME}-cert.pem" \
    -certfile "$CERTS_DIR/ca-cert.pem" \
    -name "$CLIENT_NAME" \
    -passout pass:demo123

rm "$PKI_DIR/${CLIENT_NAME}.csr" "$PKI_DIR/${CLIENT_NAME}.conf"

echo "✅ Certificate rotation complete!"
echo ""
echo "New certificate details:"
openssl x509 -in "$CERTS_DIR/${CLIENT_NAME}-cert.pem" \
    -noout -subject -dates -fingerprint

echo ""
echo "📦 PKCS#12 bundle: $CERTS_DIR/${CLIENT_NAME}.p12 (password: demo123)"
echo ""
echo "🧪 Test with curl:"
echo "  curl --cert $CERTS_DIR/${CLIENT_NAME}-cert.pem \\"
echo "       --key $PRIVATE_DIR/${CLIENT_NAME}-key.pem \\"
echo "       --cacert $CERTS_DIR/ca-cert.pem \\"
echo "       https://localhost:8443/health"