# CAPTCHA Solver - Design Document

**Created:** 2026-02-05  
**Author:** NHR Agent (Newhart)  
**Status:** Proposed

---

## Executive Summary

This document proposes a **CAPTCHA-solving skill/tool** (not a full agent) for handling CAPTCHA challenges that block automated workflows. The recommended approach is a **hybrid strategy** that uses built-in vision models first, falling back to external services for complex CAPTCHAs.

---

## 1. Architecture Decision: Tool vs Agent

### Recommendation: **TOOL/SKILL** (not agent)

| Factor | Agent | Tool/Skill | Winner |
|--------|-------|------------|--------|
| Task complexity | Multi-step reasoning | Single discrete task | **Tool** |
| State requirements | Persistent memory | Stateless | **Tool** |
| Invocation frequency | Occasional | On-demand, frequent | **Tool** |
| Integration | Standalone | Embeds in workflows | **Tool** |
| Cost efficiency | Session overhead | Direct call | **Tool** |

**Rationale:** CAPTCHAs are discrete, bounded tasks requiring no planning, memory, or multi-step reasoning. A tool integrates cleanly with browser automation workflows without the overhead of spawning an agent.

---

## 2. CAPTCHA Solving Approaches

### 2.1 Approach Comparison

| Approach | Accuracy | Speed | Cost/1000 | Best For |
|----------|----------|-------|-----------|----------|
| **Vision LLM (Claude/GPT-4V)** | 70-95%* | 2-5s | ~$0.10-0.50** | Simple text, image recognition |
| **2Captcha (human)** | 98%+ | 10-30s | $1.00-2.99 | All types, high reliability |
| **CapSolver (AI/ML)** | 95%+ | 3-10s | $0.50-2.00 | reCAPTCHA, hCaptcha |
| **Anti-Captcha** | 97%+ | 8-15s | $0.50-3.00 | Complex, ML-powered |
| **Audio Transcription** | 90%+ | 2-5s | ~$0.01 | Audio CAPTCHA alternative |

\* Varies significantly by CAPTCHA type (see research findings below)  
\** Token cost estimate for vision model calls

### 2.2 Research Findings (COGNITION Paper, Dec 2025)

Recent academic research on MLLMs solving CAPTCHAs reveals:

**Easy for MLLMs (>80% success):**
- Text recognition (distorted characters)
- Image classification ("select all traffic lights")
- Simple object counting
- Path finding puzzles

**Hard for MLLMs (<50% success):**
- Fine-grained localization (click exact coordinates)
- Multi-step spatial reasoning
- Cross-frame consistency (rotating objects)
- Complex counting with overlapping objects
- Interactive sliding/dragging puzzles

### 2.3 Recommended Strategy: Tiered Approach

```
┌─────────────────────────────────────────────────┐
│                 CAPTCHA Detected                 │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│ TIER 1: Built-in Vision Model (Claude/GPT-4V)   │
│ • Cost: ~$0.01-0.05 per solve                   │
│ • Speed: 2-5 seconds                            │
│ • Use for: Text, image selection, counting      │
└─────────────────────┬───────────────────────────┘
                      │ Failed?
                      ▼
┌─────────────────────────────────────────────────┐
│ TIER 2: CapSolver API (AI/ML)                   │
│ • Cost: $0.50-2.00/1000 solves                  │
│ • Speed: 3-10 seconds                           │
│ • Use for: reCAPTCHA, hCaptcha, FunCaptcha      │
└─────────────────────┬───────────────────────────┘
                      │ Failed?
                      ▼
┌─────────────────────────────────────────────────┐
│ TIER 3: 2Captcha (Human fallback)               │
│ • Cost: $1-3/1000 solves                        │
│ • Speed: 10-30 seconds                          │
│ • Use for: Complex, interactive, edge cases     │
└─────────────────────────────────────────────────┘
```

---

## 3. Tool Specification

### 3.1 Name & Identity

| Field | Value |
|-------|-------|
| **Name** | `captcha-solver` |
| **Type** | Skill/Tool |
| **Description** | Solves CAPTCHA challenges using vision models with service fallback |

### 3.2 Capabilities

1. **Image CAPTCHA solving** - Text recognition, image selection, object counting
2. **reCAPTCHA v2/v3** - Via CapSolver/2Captcha API integration
3. **hCaptcha** - Via CapSolver/2Captcha API
4. **Audio CAPTCHA** - Via Whisper transcription
5. **Turnstile/Cloudflare** - Via specialized services
6. **GeeTest, FunCaptcha** - Via service APIs

### 3.3 Interface

```typescript
interface CaptchaSolveRequest {
  type: 'image' | 'recaptcha-v2' | 'recaptcha-v3' | 'hcaptcha' | 
        'audio' | 'turnstile' | 'geetest' | 'funcaptcha';
  
  // For image CAPTCHAs
  imageData?: string;      // Base64 image data
  imageUrl?: string;       // URL to image
  instructions?: string;   // "Select all traffic lights"
  
  // For reCAPTCHA/hCaptcha
  siteKey?: string;        // Site key from page
  pageUrl?: string;        // URL where CAPTCHA appears
  
  // For audio CAPTCHAs
  audioData?: string;      // Base64 audio
  audioUrl?: string;       // URL to audio file
  
  // Options
  strategy?: 'vision-only' | 'service-only' | 'hybrid';  // Default: hybrid
  maxRetries?: number;     // Default: 3
  timeoutMs?: number;      // Default: 60000
}

interface CaptchaSolveResponse {
  success: boolean;
  solution?: string | string[] | { x: number; y: number }[];
  token?: string;          // For reCAPTCHA/hCaptcha tokens
  method: 'vision' | 'capsolver' | '2captcha' | 'audio';
  attempts: number;
  durationMs: number;
  cost?: number;           // Estimated cost in USD
  error?: string;
}
```

### 3.4 Integration with Browser Automation

```javascript
// Example: Solving CAPTCHA during browser automation
const browser = await browser.snapshot({ targetId: tabId });

// Detect CAPTCHA presence
if (hasCaptcha(browser.snapshot)) {
  const captchaElement = findCaptchaElement(browser.snapshot);
  
  // Screenshot the CAPTCHA
  const screenshot = await browser.screenshot({ 
    element: captchaElement.ref 
  });
  
  // Solve it
  const solution = await captchaSolver.solve({
    type: 'image',
    imageData: screenshot,
    instructions: captchaElement.instructions
  });
  
  // Input solution
  await browser.act({
    kind: 'type',
    ref: captchaElement.inputRef,
    text: solution.solution
  });
}
```

---

## 4. Dependencies & Requirements

### 4.1 Required APIs/Services

| Service | Purpose | Credential | Status |
|---------|---------|------------|--------|
| **Vision Model** | Primary solver | Anthropic/OpenAI API | ✅ Available |
| **CapSolver** | ML-based fallback | API key needed | ❌ Setup needed |
| **2Captcha** | Human fallback | API key needed | ❌ Setup needed |
| **Whisper** | Audio transcription | OpenAI API | ✅ Available |

### 4.2 NPM Dependencies

```json
{
  "dependencies": {
    "2captcha": "^3.0.0",
    "capsolver-npm": "^1.0.0"
  }
}
```

### 4.3 Environment Variables

```bash
CAPSOLVER_API_KEY=xxx      # CapSolver API key
TWOCAPTCHA_API_KEY=xxx     # 2Captcha API key
CAPTCHA_STRATEGY=hybrid    # vision-only | service-only | hybrid
```

---

## 5. Cost Analysis

### 5.1 Per-Solve Cost Estimates

| CAPTCHA Type | Tier 1 (Vision) | Tier 2 (CapSolver) | Tier 3 (2Captcha) |
|--------------|-----------------|--------------------|--------------------|
| Simple text | $0.01 | $0.0005 | $0.001 |
| Image selection | $0.02-0.05 | $0.0005 | $0.001 |
| reCAPTCHA v2 | N/A | $0.0012 | $0.002 |
| reCAPTCHA v3 | N/A | $0.002 | $0.003 |
| hCaptcha | N/A | $0.001 | $0.002 |
| GeeTest | N/A | $0.002 | $0.003 |

### 5.2 Monthly Cost Projection

| Volume | Hybrid Strategy | Service-Only |
|--------|-----------------|--------------|
| 100/month | ~$1-5 | ~$0.20-0.50 |
| 1,000/month | ~$10-30 | ~$2-5 |
| 10,000/month | ~$50-150 | ~$20-50 |

**Note:** Hybrid strategy has higher per-solve cost due to vision model tokens, but provides faster resolution and doesn't require external service dependency for simple CAPTCHAs.

---

## 6. Ethical Considerations & Boundaries

### 6.1 Acceptable Use Cases

✅ **Allowed:**
- Personal automation (own accounts, authorized workflows)
- Accessibility assistance (helping users with disabilities)
- Testing/QA of own websites
- Research purposes (with proper authorization)
- Circumventing CAPTCHAs on services where user has legitimate access

### 6.2 Prohibited Use Cases

❌ **Not Allowed:**
- Mass account creation (spam)
- Credential stuffing / brute force attacks
- Scraping protected content at scale
- Bypassing security for unauthorized access
- Any use violating target service's ToS

### 6.3 Implementation Safeguards

1. **Rate limiting** - Built-in cooldown between solves
2. **Logging** - All solve attempts logged with context
3. **Volume alerts** - Warning if >100 solves/day
4. **User confirmation** - Require explicit enable in config

```javascript
// Config example
captchaSolver: {
  enabled: true,           // Explicit opt-in required
  maxDailyVolume: 100,     // Hard limit
  requireApproval: false,  // Manual approval for each solve
  allowedDomains: [        // Whitelist approach
    'discord.com',
    'twitter.com'
  ]
}
```

---

## 7. Implementation Plan

### Phase 1: Core Tool (MVP)
- [ ] Vision model integration for image CAPTCHAs
- [ ] Basic interface definition
- [ ] Browser automation helper functions
- [ ] Logging and cost tracking

### Phase 2: Service Integration
- [ ] CapSolver API integration
- [ ] 2Captcha API integration
- [ ] Automatic fallback logic
- [ ] reCAPTCHA/hCaptcha token handling

### Phase 3: Advanced Features
- [ ] Audio CAPTCHA support (Whisper)
- [ ] GeeTest, Turnstile support
- [ ] Automatic CAPTCHA type detection
- [ ] Success rate analytics

---

## 8. File Structure

```
~/.openclaw/workspace/skills/captcha-solver/
├── SKILL.md           # Skill documentation
├── _meta.json         # Skill metadata
├── package.json       # Dependencies
├── index.js           # Main entry point
├── src/
│   ├── solver.js      # Core solving logic
│   ├── vision.js      # Vision model integration
│   ├── services/
│   │   ├── capsolver.js
│   │   └── twocaptcha.js
│   ├── types/
│   │   ├── recaptcha.js
│   │   ├── hcaptcha.js
│   │   └── image.js
│   └── utils/
│       ├── detector.js    # CAPTCHA detection
│       └── logger.js      # Audit logging
└── tests/
    └── solver.test.js
```

---

## 9. Decision Summary

| Question | Decision |
|----------|----------|
| Agent or Tool? | **Tool/Skill** |
| Primary approach? | **Hybrid (Vision + Service fallback)** |
| Which services? | **CapSolver (primary), 2Captcha (fallback)** |
| Insert into agents table? | **No** - this is a skill, not an agent |

---

## Appendix: Service Comparison Detail

### 2Captcha
- **Type:** Human workers
- **Pricing:** $1-2.99/1000
- **Speed:** 10-30s average
- **Accuracy:** 98%+
- **API:** Well-documented, widely supported
- **Best for:** Maximum reliability, edge cases

### CapSolver
- **Type:** AI/ML hybrid
- **Pricing:** $0.50-2.00/1000
- **Speed:** 3-10s average
- **Accuracy:** 95%+
- **API:** 2Captcha-compatible
- **Best for:** Speed, cost efficiency

### Anti-Captcha
- **Type:** ML-powered with human backup
- **Pricing:** $0.50-3.00/1000
- **Speed:** 8-15s average
- **Accuracy:** 97%+
- **Best for:** Complex CAPTCHAs

---

*This design document was created by NHR Agent as part of agent/tool specification work.*
