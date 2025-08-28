const express = require('express');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

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