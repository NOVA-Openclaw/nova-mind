# Confidence Decay System

## Overview

The confidence decay system is designed to fade learned facts over time, prioritizing recent and reinforced knowledge in the nova-memory system. This ensures that the agent's memory naturally evolves, giving more weight to current information while allowing older, unconfirmed knowledge to gradually diminish in importance.

### Key Components

- **Script:** `~/.openclaw/workspace/scripts/decay-confidence.sh`
- **Schedule:** Runs via cron daily at 4:00 AM UTC
- **Purpose:** Automatically reduce confidence scores for facts that haven't been recently referenced or reconfirmed

## Tables Covered

The confidence decay system applies to the following tables with different parameters:

| Table | Decay Rate | Interval | Floor | Notes |
|-------|------------|----------|-------|-------|
| lessons | 0.95 | 30 days | 0.1 | Based on last_referenced |
| entity_facts | 0.95 | 30 days | 0.1 | Excludes data_type='permanent' |
| events | 0.98 | 60 days | 0.2 | Slower decay for historical events |
| media_tags | 0.95 | 30 days | 0.1 | |
| memory_embeddings | 0.95 | 30 days | 0.1 | |

### Decay Parameters Explained

- **Decay Rate:** Multiplier applied to confidence score (e.g., 0.95 means 95% retention, 5% decay)
- **Interval:** Number of days since last reference before decay begins
- **Floor:** Minimum confidence level; decay stops at this threshold

## Excluded from Decay

The following tables and data are explicitly excluded from confidence decay:

- **`agent_domains`** — Permanent role assignments that define agent capabilities
- **`delegation_knowledge`** — VIEW on entity_facts containing permanent data
- **`entity_facts` where `data_type = 'permanent'`** — Facts marked as permanent knowledge
- **All `*_archive` tables** — Historical records preserved for audit/reference

## Reinforcement Mechanism

The system includes mechanisms to prevent decay of actively used knowledge:

- **vote_count increments** — When facts are reconfirmed through use or validation
- **last_confirmed updates** — Reset the decay clock when knowledge is actively verified
- **last_referenced tracking** — Updates when information is accessed or retrieved

## Implementation Details

### Decay Calculation

For eligible records, confidence is reduced using the formula:
```
new_confidence = max(current_confidence * decay_rate, floor_value)
```

### Timing Logic

- Decay only applies to records older than the specified interval
- The `last_referenced` or `last_confirmed` timestamp determines eligibility
- Daily execution ensures consistent, gradual degradation

### Safety Measures

- Floor values prevent complete knowledge loss
- Permanent data exclusions protect critical system knowledge
- Archive tables remain untouched for historical integrity

## Monitoring

The decay process includes logging to track:
- Number of records processed per table
- Confidence changes applied
- Any errors or exceptions during execution

## Configuration

Decay parameters are configurable within the script to allow fine-tuning based on:
- Knowledge domain importance
- Usage patterns
- System performance requirements

This system ensures that the nova-memory maintains relevant, current knowledge while gracefully aging out outdated information that is no longer actively used or confirmed.