---
name: certificate-authority
description: Manage a private Certificate Authority for mTLS authentication. Use when creating CA infrastructure, signing client certificates, configuring nginx for mutual TLS, or managing certificate lifecycle. Covers OpenSSL CA operations, CSR signing, and certificate verification.
---

# Certificate Authority Management

## Quick Start

Sign a client certificate:
```bash
cd ~/nova-ca  # or your CA directory
./sign-client-csr.sh /path/to/client.csr entity_name [days]
```

## CA Structure

```
nova-ca/
├── private/ca.key      # CA private key (mode 400, PROTECT THIS)
├── certs/ca.crt        # CA certificate (distribute to clients)
├── certs/              # Issued certificates
├── csr/                # Certificate signing requests
├── newcerts/           # Cert archive
├── index.txt           # Certificate database
├── serial              # Next serial number
└── sign-client-csr.sh  # Signing script
```

## Common Operations

### Create New CA (one-time setup)
```bash
mkdir -p ~/nova-ca/{private,certs,csr,newcerts}
chmod 700 ~/nova-ca/private
cd ~/nova-ca

# Generate CA key and cert
openssl genrsa -out private/ca.key 4096
chmod 400 private/ca.key
openssl req -x509 -new -nodes -key private/ca.key -sha256 -days 3650 \
  -out certs/ca.crt -subj "/CN=My Root CA"

# Initialize database
touch index.txt
echo 1000 > serial
```

### Generate Client Key + CSR
```bash
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -subj "/CN=client-name"
```

### Sign Client CSR
```bash
openssl x509 -req -in client.csr -CA certs/ca.crt -CAkey private/ca.key \
  -CAcreateserial -out client.crt -days 365 -sha256
```

### Verify Certificate
```bash
openssl verify -CAfile certs/ca.crt client.crt
openssl x509 -in client.crt -text -noout  # View details
```

## Nginx mTLS Configuration

```nginx
server {
    listen 443 ssl;
    
    ssl_certificate /path/to/server.crt;
    ssl_certificate_key /path/to/server.key;
    
    # Client certificate verification
    ssl_client_certificate /path/to/ca.crt;
    ssl_verify_client on;  # or 'optional' for gradual rollout
    
    # Pass client CN to backend
    proxy_set_header X-Client-CN $ssl_client_s_dn_cn;
}
```

## Security Notes

- **Never expose ca.key** — compromise means all certs are compromised
- **Track issued certs** — maintain index.txt or database record
- **Set appropriate expiry** — balance security vs operational burden
- **Revocation** — for production, implement CRL or OCSP
