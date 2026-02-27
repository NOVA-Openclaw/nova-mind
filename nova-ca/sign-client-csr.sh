#!/bin/bash
# Usage: ./sign-client-csr.sh <csr_file> <entity_id> [days]
# Signs a client CSR with the entity ID as the CN (overriding CSR subject)

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <csr_file> <entity_id> [days]"
    echo "  csr_file: Path to the Certificate Signing Request"
    echo "  entity_id: User's entity ID (will be the CN in the cert)"
    echo "  days: Validity period (default: 365)"
    exit 1
fi

CSR_FILE="$1"
ENTITY_ID="$2"
DAYS="${3:-365}"
CA_DIR="/home/nova/clawd/nova-ca"
OUTPUT_CERT="$CA_DIR/certs/client_entity_${ENTITY_ID}.crt"

# Create extensions file for client cert
EXTFILE=$(mktemp)
cat > "$EXTFILE" << EOF
basicConstraints = CA:FALSE
nsCertType = client
nsComment = "NOVA CA - Client Certificate for $ENTITY_ID"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# Sign the CSR with overridden subject (entity_id as CN)
openssl x509 -req \
    -in "$CSR_FILE" \
    -CA "$CA_DIR/certs/ca.crt" \
    -CAkey "$CA_DIR/private/ca.key" \
    -CAcreateserial \
    -out "$OUTPUT_CERT" \
    -days "$DAYS" \
    -sha256 \
    -extfile "$EXTFILE" \
    -subj "/CN=entity_${ENTITY_ID}/O=NOVA App User/C=US"

RESULT=$?
rm -f "$EXTFILE"

if [ $RESULT -eq 0 ]; then
    echo "Certificate issued: $OUTPUT_CERT"
    echo ""
    openssl x509 -in "$OUTPUT_CERT" -noout -subject -serial -dates
    echo ""
    echo "SHA-256 Fingerprint:"
    openssl x509 -in "$OUTPUT_CERT" -noout -fingerprint -sha256
    echo ""
    echo "--- Certificate PEM ---"
    cat "$OUTPUT_CERT"
else
    echo "Failed to sign certificate"
    exit 1
fi
