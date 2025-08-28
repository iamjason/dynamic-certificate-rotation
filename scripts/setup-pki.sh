#!/bin/bash

set -e

PKI_DIR="$(cd "$(dirname "$0")/../pki" && pwd)"
CERTS_DIR="$PKI_DIR/certs"
PRIVATE_DIR="$PKI_DIR/private"

echo "🔧 Setting up PKI infrastructure..."
echo "PKI Directory: $PKI_DIR"

mkdir -p "$CERTS_DIR" "$PRIVATE_DIR"

if [[ -f "$CERTS_DIR/ca-cert.pem" ]]; then
    echo "⚠️  CA certificate already exists. Skipping PKI generation to preserve existing setup."
    echo "   Delete $CERTS_DIR/ca-cert.pem to force regeneration."
    exit 0
fi

echo "📋 Generating Certificate Authority (CA)..."
openssl genrsa -out "$PRIVATE_DIR/ca-key.pem" 4096

cat > "$PKI_DIR/ca.conf" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = mTLS Demo CA
OU = Security
CN = mTLS Demo Root CA

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF

openssl req -new -x509 -key "$PRIVATE_DIR/ca-key.pem" \
    -out "$CERTS_DIR/ca-cert.pem" \
    -days 3650 \
    -config "$PKI_DIR/ca.conf"

echo "🖥️  Generating Server Certificate..."
openssl genrsa -out "$PRIVATE_DIR/server-key.pem" 2048

cat > "$PKI_DIR/server.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = mTLS Demo Server
OU = Backend
CN = localhost

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation,digitalSignature,keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -new -key "$PRIVATE_DIR/server-key.pem" \
    -out "$PKI_DIR/server.csr" \
    -config "$PKI_DIR/server.conf"

openssl x509 -req -in "$PKI_DIR/server.csr" \
    -CA "$CERTS_DIR/ca-cert.pem" \
    -CAkey "$PRIVATE_DIR/ca-key.pem" \
    -CAcreateserial \
    -out "$CERTS_DIR/server-cert.pem" \
    -days 365 \
    -extensions v3_req \
    -extfile "$PKI_DIR/server.conf"

generate_client_cert() {
    local client_name="$1"
    echo "📱 Generating Client Certificate: $client_name..."
    
    openssl genrsa -out "$PRIVATE_DIR/${client_name}-key.pem" 2048
    
    cat > "$PKI_DIR/${client_name}.conf" << EOF
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = mTLS Demo iOS
OU = Mobile
CN = $client_name
EOF
    
    openssl req -new -key "$PRIVATE_DIR/${client_name}-key.pem" \
        -out "$PKI_DIR/${client_name}.csr" \
        -config "$PKI_DIR/${client_name}.conf"
    
    openssl x509 -req -in "$PKI_DIR/${client_name}.csr" \
        -CA "$CERTS_DIR/ca-cert.pem" \
        -CAkey "$PRIVATE_DIR/ca-key.pem" \
        -CAcreateserial \
        -out "$CERTS_DIR/${client_name}-cert.pem" \
        -days 90 \
        -extensions usr_cert
    
    echo "📦 Creating PKCS#12 bundle for $client_name..."
    openssl pkcs12 -export \
        -out "$CERTS_DIR/${client_name}.p12" \
        -inkey "$PRIVATE_DIR/${client_name}-key.pem" \
        -in "$CERTS_DIR/${client_name}-cert.pem" \
        -certfile "$CERTS_DIR/ca-cert.pem" \
        -name "$client_name" \
        -passout pass:demo123
    
    rm "$PKI_DIR/${client_name}.csr" "$PKI_DIR/${client_name}.conf"
}

generate_client_cert "ios-client-v1"
generate_client_cert "ios-client-v2"

rm "$PKI_DIR/server.csr" "$PKI_DIR/server.conf" "$PKI_DIR/ca.conf"

echo "✅ PKI Setup Complete!"
echo ""
echo "Generated certificates:"
echo "  📋 CA Certificate: $CERTS_DIR/ca-cert.pem"
echo "  🖥️  Server Certificate: $CERTS_DIR/server-cert.pem"
echo "  📱 iOS Client v1: $CERTS_DIR/ios-client-v1-cert.pem"
echo "  📱 iOS Client v2: $CERTS_DIR/ios-client-v2-cert.pem"
echo ""
echo "PKCS#12 bundles (password: demo123):"
echo "  📦 $CERTS_DIR/ios-client-v1.p12"
echo "  📦 $CERTS_DIR/ios-client-v2.p12"
echo ""
echo "🧪 Test with curl:"
echo "  curl --cert $CERTS_DIR/ios-client-v1-cert.pem \\"
echo "       --key $PRIVATE_DIR/ios-client-v1-key.pem \\"
echo "       --cacert $CERTS_DIR/ca-cert.pem \\"
echo "       https://localhost:8443/health"