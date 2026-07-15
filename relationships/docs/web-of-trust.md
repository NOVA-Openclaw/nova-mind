# Web of Trust Design

## Overview

The NOVA Web of Trust is an experimental trust infrastructure inspired by PGP's web of trust model, designed specifically for AI agent networks. It provides cryptographic identity verification and transitive trust relationships between autonomous agents.

## Trust Model

### Certificate Authority Hierarchy

```
NOVA Root CA
├── Organization CA (optional)
│   ├── Agent Certificate (agent-alice)
│   ├── Agent Certificate (agent-bob)
│   └── Agent Certificate (agent-charlie)
└── Direct Agent Certificates
    ├── Agent Certificate (nova-main)
    ├── Agent Certificate (nova-scribe)
    └── Agent Certificate (trusted-external-agent)
```

### Trust Relationships

1. **Root Trust**: All agents trust the NOVA Root CA
2. **Direct Trust**: Agents can directly trust other agent certificates
3. **Transitive Trust**: Agents can accept vouches from trusted agents
4. **Revocation**: Trust can be revoked at any level

### Trust Levels

- **Full Trust**: Agent can perform any action on behalf of the trustor
- **Limited Trust**: Agent can perform specific actions (read-only, specific domains)
- **Vouch-Only**: Agent can vouch for other agents but cannot act directly
- **No Trust**: Default state for unknown agents

## Protocol Design

### Certificate Format

Agent certificates include standard X.509 fields plus custom extensions:

```
Subject: CN=agent-name, O=organization, C=country
Extensions:
  - agentType: (autonomous|human-operated|service)
  - capabilities: comma-separated list of agent capabilities
  - trustPolicy: URL to agent's trust policy document
  - publicKey: Agent's public key for message verification
```

### Trust Vouches

Agents can create signed vouches for other agents:

```json
{
  "version": "1.0",
  "voucher": "CN=agent-alice",
  "vouchee": "CN=agent-bob", 
  "trustLevel": "limited",
  "capabilities": ["read-calendar", "send-notifications"],
  "validUntil": "2025-12-31T23:59:59Z",
  "signature": "base64-encoded-signature"
}
```

### Trust Discovery

Agents can query the trust network:

1. **Direct Query**: "Do I trust agent X?"
2. **Path Query**: "What's the trust path to agent X?"
3. **Capability Query**: "Which agents can perform action Y?"
4. **Reputation Query**: "What's the reputation of agent X?"

## Implementation Status

### Current Components

✅ **NOVA Root CA**
- Operational certificate authority (manually initialized per
  `skills/certificate-authority/SKILL.md`; `agent-install.sh` verifies but
  does not create it — see `README.md`)
- Client certificate signing (`nova-ca/sign-client-csr.sh`)
- OpenSSL-based infrastructure

📋 **mTLS Authentication** (Not yet implemented in this repo)
- No Nginx configuration or other server-side mTLS enforcement exists in
  this repo. `docs/integration-guide.md`'s Express middleware example
  (`X-SSL-Client-CN` header extraction, `req.socket.getPeerCertificate()`)
  is illustrative sample code, not a shipped integration.
- CN extraction for identity resolution is likewise illustrative only
  (no such code exists in `lib/entity-resolver/`).

🧪 **Trust Protocols** (Experimental / design-only)
- Basic vouch format defined below (design sketch, not implemented)
- Signature verification and trust path calculation are design sketches
  in this document — no corresponding code exists in `lib/entity-resolver/`
  or elsewhere in this repo

📋 **Planned Features**
- Automated trust discovery
- Trust policy enforcement
- Reputation scoring
- Revocation checking

### Integration Points

The Web of Trust integrates with existing NOVA components:

#### Entity Resolution
- Certificate CN becomes an identity source
- Trust level affects entity confidence scores
- Trust relationships stored as entity relationships

#### Agent Communication
- Certificate-based agent authentication
- Trust verification before message processing
- Capability checking for requested actions

#### Cross-Platform Identity
- Certificates survive platform changes
- Trust relationships portable across systems
- Federated identity across organizations

## Security Model

### Threat Model

**Trusted Components:**
- NOVA Root CA private key (ultimate trust anchor)
- Agent certificate private keys (individual agent identity)
- Trust vouch signatures (reputation system)

**Attack Scenarios:**
- **Compromised Agent**: Revocation and re-certification process
- **Compromised CA**: Root key rotation and certificate reissuance  
- **False Vouches**: Reputation tracking and vouch verification
- **Sybil Attacks**: Identity verification and rate limiting
- **Trust Path Poisoning**: Path validation and reputation checks

### Security Controls

1. **Certificate Validation**
   - Full certificate chain verification
   - CRL/OCSP checking (planned)
   - Certificate policy validation

2. **Trust Verification**
   - Cryptographic vouch signature verification
   - Trust path length limits
   - Reputation-based filtering

3. **Access Controls**
   - Capability-based permissions
   - Time-limited trust grants
   - Action audit logging

4. **Monitoring**
   - Trust relationship change alerts
   - Suspicious activity detection
   - Certificate usage analytics

## Use Cases

### Multi-Agent Collaboration

**Scenario**: Agent Alice needs Agent Bob to check a calendar and send a notification.

1. Alice verifies Bob's certificate against NOVA CA
2. Alice checks if Bob has "read-calendar" and "send-notifications" capabilities
3. Alice may require additional vouches if Bob isn't directly trusted
4. Bob performs actions and signs response for verification

### Cross-Organization Trust

**Scenario**: Company A's agent needs to interact with Company B's agent.

1. Both companies run their own CAs under NOVA Root CA
2. Agents establish trust through certificate chain verification
3. Inter-company trust policies define allowed interactions
4. Cross-vouches establish reputation between organizations

### Agent Onboarding

**Scenario**: New agent joins the NOVA network.

1. Agent generates key pair and CSR
2. Human operator or trusted agent vouches for new agent
3. NOVA CA signs certificate with appropriate capabilities
4. Agent starts with minimal trust and builds reputation over time

### Trust Revocation

**Scenario**: Agent becomes compromised or untrustworthy.

1. Trust revocation announced to network
2. Existing trust vouches invalidated
3. Agent's capabilities suspended
4. Re-certification required for network re-entry

## Implementation Guide

### Setting Up Agent Certificates

```bash
# Generate agent key pair
openssl genrsa -out agent-alice.key 2048

# Create certificate request with agent extensions
openssl req -new -key agent-alice.key -out agent-alice.csr \
  -subj "/CN=agent-alice/O=MyOrg" \
  -addext "agentType = autonomous" \
  -addext "capabilities = read-calendar,send-email,search-web"

# Sign with NOVA CA
cd nova-ca
./sign-client-csr.sh agent-alice.csr agent-alice 365
```

### Trust Vouch Creation

```typescript
import crypto from 'crypto';

interface TrustVouch {
  voucher: string;
  vouchee: string;
  trustLevel: 'full' | 'limited' | 'vouch-only';
  capabilities?: string[];
  validUntil: string;
  signature?: string;
}

function createVouch(
  voucherKey: crypto.KeyObject,
  vouchData: Omit<TrustVouch, 'signature'>
): TrustVouch {
  const payload = JSON.stringify(vouchData);
  const signature = crypto.sign('sha256', Buffer.from(payload), voucherKey);
  
  return {
    ...vouchData,
    signature: signature.toString('base64')
  };
}
```

### Trust Verification

```typescript
function verifyTrust(
  agentCert: crypto.X509Certificate,
  requiredCapabilities: string[]
): boolean {
  // 1. Verify certificate chain to NOVA CA
  const isValidCert = verifyCertificateChain(agentCert);
  
  // 2. Check certificate capabilities
  const certCapabilities = extractCapabilities(agentCert);
  const hasCapabilities = requiredCapabilities.every(
    cap => certCapabilities.includes(cap)
  );
  
  // 3. Check trust vouches if needed
  const trustLevel = calculateTrustLevel(agentCert);
  
  return isValidCert && hasCapabilities && trustLevel >= REQUIRED_TRUST;
}
```

## Future Directions

### Standardization

The NOVA Web of Trust could serve as the foundation for industry-standard AI agent trust protocols:

- **RFC Development**: Formal specification for inter-agent trust
- **Open Source Implementation**: Reference implementation for other AI systems
- **Interoperability Testing**: Cross-system trust verification
- **Security Research**: Academic collaboration on trust model security

### Advanced Features

**Reputation Scoring**
- Historical trust relationship analysis
- Behavioral pattern recognition
- Community-based reputation metrics
- Machine learning-based trust prediction

**Privacy-Preserving Trust**
- Zero-knowledge trust proofs
- Anonymous reputation systems
- Selective disclosure protocols
- Privacy-preserving federation

**Dynamic Trust Networks**
- Adaptive trust based on context
- Temporal trust relationships
- Conditional trust triggers
- Real-time trust adjustment

### Integration Opportunities

The Web of Trust model could integrate with:
- **Blockchain Networks**: Decentralized trust anchoring
- **IoT Systems**: Device identity and trust management
- **Identity Providers**: Federation with existing identity systems
- **AI Marketplaces**: Trust-based agent selection and pricing

---

*The NOVA Web of Trust represents a foundational step toward trustworthy AI agent networks. While experimental, it provides the infrastructure necessary for secure, verifiable inter-agent collaboration at scale.*