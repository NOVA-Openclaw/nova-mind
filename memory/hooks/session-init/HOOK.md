---
name: session-init
description: "Generate privacy-filtered context when session starts"
metadata: {"openclaw":{"emoji":"🔐","events":["message:received"]}}
---

# Session Init Hook

Generates privacy-filtered context when a new session starts or participants change.

## What It Does

1. Detects session participant changes
2. Generates relevant context for the conversation
3. Filters sensitive information based on privacy settings
