#!/bin/bash

PKI_DIR="$(cd "$(dirname "$0")/../pki" && pwd)"
CERTS_DIR="$PKI_DIR/certs"
PRIVATE_DIR="$PKI_DIR/private"

print_cert_info() {
    local cert_file="$1"
    local cert_name="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        echo "❌ Certificate not found: $cert_file"
        return 1
    fi
    
    echo "📋 $cert_name"
    echo "   File: $cert_file"
    
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/subject= *//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/issuer= *//')
    local not_before=$(openssl x509 -in "$cert_file" -noout -startdate | cut -d= -f2)
    local not_after=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
    local fingerprint=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | cut -d= -f2)
    
    echo "   Subject: $subject"
    echo "   Issuer: $issuer"
    echo "   Valid From: $not_before"
    echo "   Valid To: $not_after"
    echo "   SHA256 Fingerprint: $fingerprint"
    
    local current_date=$(date +%s)
    local expiry_date=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || echo "0")
    
    if [[ $expiry_date -gt 0 ]]; then
        local days_until_expiry=$(( ($expiry_date - $current_date) / 86400 ))
        if [[ $days_until_expiry -lt 0 ]]; then
            echo "   Status: ❌ EXPIRED ($((0 - $days_until_expiry)) days ago)"
        elif [[ $days_until_expiry -lt 14 ]]; then
            echo "   Status: ⚠️  EXPIRES SOON ($days_until_expiry days remaining)"
        else
            echo "   Status: ✅ VALID ($days_until_expiry days remaining)"
        fi
    else
        echo "   Status: ❓ Unable to parse expiry date"
    fi
    
    echo ""
}

echo "🔍 Certificate Information"
echo "=========================="
echo ""

if [[ ! -d "$CERTS_DIR" ]]; then
    echo "❌ PKI directory not found. Please run setup-pki.sh first."
    exit 1
fi

print_cert_info "$CERTS_DIR/ca-cert.pem" "Certificate Authority (CA)"
print_cert_info "$CERTS_DIR/server-cert.pem" "Server Certificate"

for cert_file in "$CERTS_DIR"/ios-client-*-cert.pem; do
    if [[ -f "$cert_file" ]]; then
        cert_basename=$(basename "$cert_file" -cert.pem)
        print_cert_info "$cert_file" "Client Certificate ($cert_basename)"
    fi
done

echo "📦 PKCS#12 Bundles"
echo "=================="
echo ""

for p12_file in "$CERTS_DIR"/*.p12; do
    if [[ -f "$p12_file" ]]; then
        p12_name=$(basename "$p12_file" .p12)
        echo "📦 $p12_name"
        echo "   File: $p12_file"
        echo "   Password: demo123"
        echo "   Size: $(ls -lh "$p12_file" | awk '{print $5}')"
        echo ""
    fi
done

if ! ls "$CERTS_DIR"/*.p12 1> /dev/null 2>&1; then
    echo "❌ No PKCS#12 bundles found"
    echo ""
fi

echo "🧪 Test Commands"
echo "==============="
echo ""

for cert_file in "$CERTS_DIR"/ios-client-*-cert.pem; do
    if [[ -f "$cert_file" ]]; then
        cert_basename=$(basename "$cert_file" -cert.pem)
        key_file="$PRIVATE_DIR/${cert_basename}-key.pem"
        
        if [[ -f "$key_file" ]]; then
            echo "# Test with $cert_basename:"
            echo "curl --cert $cert_file \\"
            echo "     --key $key_file \\"
            echo "     --cacert $CERTS_DIR/ca-cert.pem \\"
            echo "     https://localhost:8443/api/client-info"
            echo ""
        fi
    fi
done