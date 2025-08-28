const express = require('express');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

const app = express();
const PORT = 8443;

const PKI_DIR = path.join(__dirname, '..', 'pki');
const CERTS_DIR = path.join(PKI_DIR, 'certs');
const PRIVATE_DIR = path.join(PKI_DIR, 'private');

const serverOptions = {
  key: fs.readFileSync(path.join(PRIVATE_DIR, 'server-key.pem')),
  cert: fs.readFileSync(path.join(CERTS_DIR, 'server-cert.pem')),
  ca: fs.readFileSync(path.join(CERTS_DIR, 'ca-cert.pem')),
  requestCert: true,
  rejectUnauthorized: true,
  secureOptions: require('constants').SSL_OP_NO_TLSv1 | require('constants').SSL_OP_NO_TLSv1_1,
  ciphers: [
    'ECDHE-RSA-AES128-GCM-SHA256',
    'ECDHE-RSA-AES256-GCM-SHA384',
    'ECDHE-RSA-AES128-SHA256',
    'ECDHE-RSA-AES256-SHA384'
  ].join(':'),
  honorCipherOrder: true
};

app.use(express.json());

function getClientCertInfo(req) {
  const cert = req.socket.getPeerCertificate();
  
  if (!cert || !cert.subject) {
    return null;
  }
  
  return {
    commonName: cert.subject.CN || '',
    organization: cert.subject.O || '',
    organizationalUnit: cert.subject.OU || '',
    country: cert.subject.C || '',
    state: cert.subject.ST || '',
    locality: cert.subject.L || '',
    validFrom: cert.valid_from,
    validTo: cert.valid_to,
    issuer: {
      commonName: cert.issuer.CN || '',
      organization: cert.issuer.O || '',
      organizationalUnit: cert.issuer.OU || ''
    },
    fingerprint: cert.fingerprint || '',
    serialNumber: cert.serialNumber || ''
  };
}

function logClientAuth(req, res, next) {
  const clientInfo = getClientCertInfo(req);
  if (clientInfo) {
    console.log(`✅ Client authenticated: ${clientInfo.commonName} (${clientInfo.organization})`);
  } else {
    console.log('❌ Client authentication failed');
  }
  next();
}

app.use(logClientAuth);

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.get('/api/client-info', (req, res) => {
  const clientInfo = getClientCertInfo(req);
  
  if (!clientInfo) {
    return res.status(401).json({ error: 'Client certificate required' });
  }
  
  res.json({
    authenticated: true,
    client: {
      commonName: clientInfo.commonName,
      organization: clientInfo.organization,
      organizationalUnit: clientInfo.organizationalUnit,
      country: clientInfo.country,
      state: clientInfo.state,
      locality: clientInfo.locality
    },
    certificate: {
      validFrom: clientInfo.validFrom,
      validTo: clientInfo.validTo,
      issuer: clientInfo.issuer,
      fingerprint: clientInfo.fingerprint,
      serialNumber: clientInfo.serialNumber
    }
  });
});

app.get('/api/secure-data', (req, res) => {
  const clientInfo = getClientCertInfo(req);
  
  if (!clientInfo) {
    return res.status(401).json({ error: 'Client certificate required' });
  }
  
  res.json({
    message: 'This is protected data accessible only with valid client certificates',
    timestamp: new Date().toISOString(),
    client: clientInfo.commonName,
    data: {
      secretValue: 'demo-secret-42',
      permissions: ['read', 'write'],
      sessionId: crypto.randomBytes(16).toString('hex')
    }
  });
});

app.get('/api/certificates/current', (req, res) => {
  const clientInfo = getClientCertInfo(req);
  
  if (!clientInfo) {
    return res.status(401).json({ error: 'Client certificate required' });
  }
  
  const validTo = new Date(clientInfo.validTo);
  const now = new Date();
  const daysUntilExpiry = Math.ceil((validTo - now) / (1000 * 60 * 60 * 24));
  
  res.json({
    certName: clientInfo.commonName,
    validTo: clientInfo.validTo,
    daysUntilExpiry: daysUntilExpiry,
    rotationRequired: daysUntilExpiry <= 14,
    rotationRecommended: daysUntilExpiry <= 30
  });
});

app.get('/api/certificates/download/:certName', (req, res) => {
  const clientInfo = getClientCertInfo(req);
  
  if (!clientInfo) {
    return res.status(401).json({ error: 'Client certificate required' });
  }
  
  const certName = req.params.certName;
  const p12Path = path.join(CERTS_DIR, `${certName}.p12`);
  
  if (!fs.existsSync(p12Path)) {
    return res.status(404).json({ error: 'Certificate bundle not found' });
  }
  
  console.log(`📦 Serving certificate bundle: ${certName}.p12 to ${clientInfo.commonName}`);
  
  res.setHeader('Content-Type', 'application/x-pkcs12');
  res.setHeader('Content-Disposition', `attachment; filename="${certName}.p12"`);
  res.sendFile(p12Path);
});

app.post('/api/certificates/enroll', (req, res) => {
  try {
    const { csr, deviceId, commonName } = req.body;

    if (!csr || !deviceId || !commonName) {
      return res.status(400).json({
        error: 'Missing required fields: csr, deviceId, commonName'
      });
    }

    console.log(`📝 Certificate enrollment request from device: ${deviceId}`);
    console.log(`📝 Common name: ${commonName}`);

    // Parse CSR - handle both JSON format and traditional base64 CSR
    let csrInfo;
    try {
      // Try to parse as JSON first (new format)
      const decodedCSR = Buffer.from(csr, 'base64').toString();
      console.log('📝 Decoded CSR data:', decodedCSR.substring(0, 200) + '...');
      
      const csrJson = JSON.parse(decodedCSR);
      csrInfo = csrJson;
      console.log('📝 Received JSON-based CSR request');
      console.log('📝 CSR Info:', JSON.stringify(csrInfo, null, 2));
    } catch (parseError) {
      console.log('📝 JSON parsing failed:', parseError.message);
      // Fall back to traditional CSR format
      const csrData = Buffer.from(csr, 'base64');
      
      // Save CSR to temporary file for traditional processing
      const csrFile = path.join(CERTS_DIR, `csr-${deviceId}-${Date.now()}.csr`);
      fs.writeFileSync(csrFile, csrData);
      
      console.log('📝 Received traditional ASN.1 CSR');
      return handleTraditionalCSR(csrFile, deviceId, commonName, res);
    }

    // Handle JSON-based CSR by generating certificate directly
    const certFile = path.join(CERTS_DIR, `client-${deviceId}-${Date.now()}.pem`);
    const keyFile = path.join(PRIVATE_DIR, `client-${deviceId}-${Date.now()}.key`);
    const configFile = path.join(CERTS_DIR, `client-${deviceId}-${Date.now()}.conf`);

    try {
      // Create a temporary OpenSSL config for the certificate
      const opensslConfig = `
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = ${csrInfo.subject.commonName}
O = ${csrInfo.subject.organizationName}
OU = ${csrInfo.subject.organizationalUnitName}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${csrInfo.subject.commonName}
      `.trim();

      fs.writeFileSync(configFile, opensslConfig);

      // Generate an ECDSA private key for the client (P-256 to match iOS)
      const genKeyCommand = `openssl ecparam -genkey -name prime256v1 | openssl pkcs8 -topk8 -nocrypt -out "${keyFile}"`;
      console.log('🔐 Generating ECDSA P-256 client private key in PKCS#8 format...');
      execSync(genKeyCommand, { stdio: 'inherit' });

      // Generate CSR first, then sign it
      const csrTempFile = path.join(CERTS_DIR, `temp-${deviceId}-${Date.now()}.csr`);
      
      const genCSRCommand = [
        'openssl req -new',
        `-key "${keyFile}"`,
        `-out "${csrTempFile}"`,
        `-config "${configFile}"`
      ].join(' ');

      console.log('🔐 Generating CSR from config...');
      execSync(genCSRCommand, { stdio: 'inherit' });

      // Sign the CSR with CA
      const signCommand = [
        'openssl x509 -req',
        `-in "${csrTempFile}"`,
        `-CA "${path.join(CERTS_DIR, 'ca-cert.pem')}"`,
        `-CAkey "${path.join(PRIVATE_DIR, 'ca-key.pem')}"`,
        `-out "${certFile}"`,
        '-days 365',
        '-sha256',
        `-CAcreateserial`
      ].join(' ');

      console.log('🔐 Signing certificate...');
      execSync(signCommand, { stdio: 'inherit' });

      // Read the signed certificate
      const signedCert = fs.readFileSync(certFile);
      const clientKey = fs.readFileSync(keyFile);

      // Clean up temporary files
      fs.unlinkSync(csrTempFile);
      fs.unlinkSync(certFile);
      fs.unlinkSync(keyFile);
      fs.unlinkSync(configFile);

      console.log(`✅ Certificate enrolled successfully for device: ${deviceId}`);

      // Return the signed certificate and private key
      res.json({
        success: true,
        certificate: signedCert.toString('base64'),
        privateKey: clientKey.toString('base64'),
        deviceId: deviceId,
        commonName: commonName,
        validFor: '365 days'
      });

    } catch (signError) {
      console.error('❌ Certificate generation failed:', signError.message);

      // Clean up temporary files
      if (fs.existsSync(certFile)) fs.unlinkSync(certFile);
      if (fs.existsSync(keyFile)) fs.unlinkSync(keyFile);
      if (fs.existsSync(configFile)) fs.unlinkSync(configFile);
      const csrTempFile = path.join(CERTS_DIR, `temp-${deviceId}-${Date.now()}.csr`);
      if (fs.existsSync(csrTempFile)) fs.unlinkSync(csrTempFile);

      return res.status(500).json({
        error: 'Certificate generation failed',
        details: signError.message
      });
    }

  } catch (error) {
    console.error('❌ Certificate enrollment error:', error.message);
    res.status(500).json({
      error: 'Internal server error during certificate enrollment'
    });
  }
});

function handleTraditionalCSR(csrFile, deviceId, commonName, res) {
  // Original CSR processing logic
  const certFile = path.join(CERTS_DIR, `client-${deviceId}-${Date.now()}.pem`);
  const serialFile = path.join(PKI_DIR, 'certs', 'ca-cert.srl');

  try {
    const signCommand = [
      'openssl x509 -req',
      `-in "${csrFile}"`,
      `-CA "${path.join(CERTS_DIR, 'ca-cert.pem')}"`,
      `-CAkey "${path.join(PRIVATE_DIR, 'ca-key.pem')}"`,
      `-out "${certFile}"`,
      '-days 365',
      '-sha256',
      `-CAserial "${serialFile}"`,
      '-CAcreateserial'
    ].join(' ');

    console.log('🔐 Executing certificate signing command...');
    execSync(signCommand, { stdio: 'inherit' });

    const signedCert = fs.readFileSync(certFile);

    fs.unlinkSync(csrFile);
    fs.unlinkSync(certFile);

    console.log(`✅ Certificate enrolled successfully for device: ${deviceId}`);

    res.json({
      success: true,
      certificate: signedCert.toString('base64'),
      deviceId: deviceId,
      commonName: commonName,
      validFor: '365 days'
    });

  } catch (signError) {
    console.error('❌ Certificate signing failed:', signError.message);

    if (fs.existsSync(csrFile)) fs.unlinkSync(csrFile);
    if (fs.existsSync(certFile)) fs.unlinkSync(certFile);

    return res.status(500).json({
      error: 'Certificate signing failed',
      details: signError.message
    });
  }
}

app.use((err, req, res, next) => {
  console.error('Server error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

const server = https.createServer(serverOptions, app);

server.on('tlsClientError', (err, tlsSocket) => {
  console.log('❌ TLS Client Error:', err.message);
});

server.on('secureConnection', (tlsSocket) => {
  const cert = tlsSocket.getPeerCertificate();
  if (cert && cert.subject) {
    console.log(`🔐 Secure connection established with: ${cert.subject.CN || 'Unknown'}`);
  }
});

server.listen(PORT, () => {
  console.log('🚀 mTLS Demo Server Starting...');
  console.log('================================');
  console.log(`🌐 Server running on https://localhost:${PORT}`);
  console.log('🔐 Mutual TLS authentication required');
  console.log('');
  console.log('📡 Available endpoints:');
  console.log('  GET /health                           - Health check');
  console.log('  GET /api/client-info                  - Client certificate information');
  console.log('  GET /api/secure-data                  - Protected data');
  console.log('  GET /api/certificates/current         - Current certificate status');
  console.log('  GET /api/certificates/download/:name  - Download certificate bundle');
  console.log('  POST /api/certificates/enroll         - Enroll new certificate');
  console.log('');
  console.log('🧪 Test with curl:');
  console.log(`  curl --cert ${CERTS_DIR}/ios-client-v1-cert.pem \\`);
  console.log(`       --key ${PRIVATE_DIR}/ios-client-v1-key.pem \\`);
  console.log(`       --cacert ${CERTS_DIR}/ca-cert.pem \\`);
  console.log(`       https://localhost:${PORT}/health`);
  console.log('');
});

process.on('SIGINT', () => {
  console.log('\\n🛑 Shutting down server...');
  server.close(() => {
    console.log('✅ Server stopped');
    process.exit(0);
  });
});