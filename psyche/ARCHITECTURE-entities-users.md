# Entity & User System Architecture

This document describes NOVA's current system for tracking entities and users, and how they relate.

## Core Concept: Entity-First Design

**Everything is an entity.** Users are a *class* of entity, not a separate system.

```
Entity (any tracked thing)
├── person (human)
│   ├── user (is_user = true) — someone who interacts with NOVA directly
│   └── non-user — mentioned people, contacts, etc.
├── ai (agents, models)
├── organization (companies, groups)
├── pet
├── stuffed_animal
├── character (fictional)
└── other
```

## Database Schema

### entities table

The core table for all tracked entities.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `name` | varchar(255) | Display name (required) |
| `type` | varchar(50) | Entity type (see constraint below) |
| `full_name` | varchar(255) | Full legal/formal name |
| `nicknames` | text[] | Array of alternate names |
| `gender` | varchar(50) | Gender identity |
| `pronouns` | varchar(50) | Preferred pronouns |
| `notes` | text | Freeform notes |
| `created_at` | timestamp | When first recorded |
| `last_seen` | timestamp | Last interaction |
| `photo` | bytea | Avatar/photo (binary) |
| `user_id` | varchar(255) | External user identifier |
| `auth_token` | varchar(255) | Authentication token |
| `trust_level` | integer | Trust score (default 0) |
| `collaborate` | boolean | Can this entity collaborate? |
| `collaboration_scope` | text | 'full', 'domain-specific', or 'supervised' |
| `introduction_context` | text | How was this entity introduced? |
| `capabilities` | jsonb | What can this entity do? |
| `access_constraints` | jsonb | Limitations on access |

**Type Constraint:**
```sql
CHECK (type IN ('person', 'ai', 'organization', 'pet', 'stuffed_animal', 'character', 'other'))
```

**Current Distribution:**
| Type | Count |
|------|-------|
| organization | 151 |
| person | 94 |
| ai | 68 |
| stuffed_animal | 1 |

### entity_facts table

Flexible key-value storage for any fact about an entity.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `entity_id` | integer | FK to entities |
| `key` | varchar(255) | Fact name (e.g., 'phone', 'email') |
| `value` | text | Fact value |
| `data` | jsonb | Structured data (optional) |
| `source` | varchar(255) | Where did this fact come from? |
| `source_entity_id` | integer | Who told us this? (FK to entities) |
| `confidence` | float | 0.0 - 1.0 confidence score (default 1.0) |
| `learned_at` | timestamp | When first learned |
| `updated_at` | timestamp | When last updated |
| `last_confirmed` | timestamp | When last verified |
| `vote_count` | integer | Confirmation count |
| `visibility` | varchar(20) | 'public', 'private', etc. |
| `privacy_scope` | integer[] | Array of entity IDs who can see this |
| `visibility_reason` | text | Why is visibility set this way? |

**Common Keys for Users:**
- `is_user` — 'true' marks entity as a user
- `onboarded` — 'true' if onboarding completed
- `phone` — Phone number
- `email` — Email address
- `timezone` — IANA timezone (e.g., 'America/Chicago')
- `current_timezone` — Current location timezone
- `home_timezone` — Home/default timezone
- `owner_number` — Phone number of the "owner" (for permission inheritance)
- `signal_uuid` — Signal messenger UUID
- `gdrive_shared_folder` — Shared Google Drive folder URL

## What Makes an Entity a "User"?

An entity becomes a user when:
```sql
INSERT INTO entity_facts (entity_id, key, value) VALUES (?, 'is_user', 'true');
```

The `v_users` view filters to only entities with `is_user = 'true'` or `onboarded = 'true'`.

### v_users view

Convenience view that pivots common user facts into columns:

```sql
SELECT * FROM v_users;
```

| Column | Source |
|--------|--------|
| id | entities.id |
| name | entities.name |
| full_name | entities.full_name |
| type | entities.type |
| phone | entity_facts where key='phone' |
| email | entity_facts where key='email' |
| current_timezone | entity_facts where key='current_timezone' |
| home_timezone | entity_facts where key='home_timezone' |
| onboarded_date | entity_facts where key='onboarded' |
| owner_number | entity_facts where key='owner_number' |
| signal_uuid | entity_facts where key='signal_uuid' |

## Relationships

### entity_relationships table

Links entities together with typed relationships.

```sql
-- Example: Sean knows I)ruid
INSERT INTO entity_relationships (entity_a, entity_b, relationship_type)
VALUES (28, 2, 'knows');
```

## Related Tables

Entities are referenced throughout the system:

| Table | Relationship |
|-------|--------------|
| `tasks` | assigned_to, created_by, blocked_on |
| `project_entities` | Links entities to projects with roles |
| `event_entities` | Links entities to events |
| `preferences` | Entity-specific preferences |
| `gambling_logs` | Gambling activity by entity |
| `media_consumed` | Media consumption by entity |
| `media_queue` | Requested media by entity |
| `certificates` | mTLS certificates issued to entities |
| `vehicles` | Vehicles owned by entities |

## User Onboarding Flow

1. **Check/Create Entity** — Look for existing entity or create new
2. **Capture Contact Info** — phone, email, signal_uuid
3. **Set User Flags** — `is_user = 'true'`, `onboarded = 'true'`
4. **Set Owner** — `owner_number` for permission inheritance
5. **Capture Timezone** — for time-aware interactions
6. **Add to Signal Allowlist** — Clawdbot config update
7. **Create Shared GDrive Folder** — for file exchange
8. **Log Event** — Record onboarding in events table
9. **Verify** — Check v_users view
10. **Welcome** — Send confirmation message

## Future: Entity Profiling (NOVA Multiuser System)

The current system tracks *facts* about entities. The Multiuser System will add:

- **Behavioral profiling** — traits, patterns, tendencies
- **Confidence scoring** — how certain are we about inferred data?
- **Longitudinal analysis** — how do patterns change over time?
- **Intensity/volume tracking** — how strongly do traits present?
- **Association mapping** — relationships to places, topics, moods
- **Dynamic adaptation** — adjust NOVA's behavior based on entity state

This builds *on top of* the existing entity system, not replacing it.

---

*Last updated: 2026-02-08*
