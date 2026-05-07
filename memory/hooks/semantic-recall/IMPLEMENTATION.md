# Entity Context Enhancement Implementation

## Summary

Successfully enhanced the `semantic-recall` hook to load entity context alongside semantic memories. The hook now resolves message senders to entities in the database and injects their profile information before the agent processes messages.

**Recent Update (Task #38):** Refactored entity resolution logic into a reusable shared library at `$OPENCLAW_WORKSPACE/lib/entity-resolver/` to enable reuse across multiple hooks and components.

## Changes Made

### 1. Shared Entity Resolver Library
Reusable library at `relationships/lib/entity-resolver/`, installed to `~/.openclaw/lib/entity-resolver/`:
- **`types.ts`**: TypeScript interfaces for Entity, EntityFacts, EntityIdentifiers, ResolveResult, DbEntityFact
- **`resolver.ts`**: Core resolution logic with database connection pooling, conflict detection, and `IDENTIFIER_TO_DB_KEY` mapping
- **`cache.ts`**: Session-aware caching with configurable TTL (30 min default)
- **`index.ts`**: Main exports for easy importing
- **`README.md`**: Complete API documentation and usage examples
- **`package.json`**: Dependencies and package metadata
- **`test.ts`**: Comprehensive test suite

**Library Features:**
- Multi-identifier resolution (phone, UUID, certCN, email, discordId, telegramId, slackMemberId, signalUuid, signalUsername)
- **Conflict detection** via `resolveEntityByIdentifiers()` — flags when identifiers resolve to different entities
- Session-aware caching to reduce database queries
- Connection pooling (max 5 connections)
- Graceful error handling (no exceptions thrown)
- TypeScript support with full type definitions

### 2. Refactored Handler (`handler.ts`)

**Uses shared library via dynamic imports from `~/.openclaw/lib/entity-resolver/`:**
- Imports `resolveEntity`, `resolveEntityByIdentifiers`, `getEntityProfile`, `getCachedEntity`, `setCachedEntity` from library
- Loads `pg-env.ts` BEFORE importing entity-resolver (which creates a `pg.Pool` at module scope)
- Defines `EntityIdentifiers` interface inline (mirrors the library type, since the source path isn't available at install time)
- Uses `extractIdentifiers()` for **channel-aware routing** of provider-specific sender IDs
- Uses `resolveEntityByIdentifiers()` for **conflict detection** — never silently picks a winner
- Reads message from `event.context.content` (with `event.context.message` fallback for legacy callers)
- Reads sender metadata from `event.context.metadata` (with `event.context.*` fallback for legacy callers)

**Key Features:**
- **Channel-aware routing**: Maps Discord/Telegram/Slack/Signal providers to correct identifier fields
- **Conflict detection**: Logs data integrity issues, skips entity injection if identifiers conflict
- Non-blocking: Entity resolution runs in parallel with semantic recall
- Timeout protection: 2s for entity resolution, 1s for profile loading
- Graceful degradation: Failures don't block message processing
- Session caching: Reduces database queries for repeat senders
- Detailed logging: All operations logged for debugging

### 3. Updated Documentation (`HOOK.md`)
- Added entity resolution documentation
- Listed new requirements (PostgreSQL connection)
- Documented configuration options
- Explained error handling behavior

### 4. Test Script (`test-entity-resolution.js`)
- Created standalone test script to verify entity resolution
- Can list example identifiers or test specific phone/UUID
- Validates database queries and connection

## Database Schema Used

**Tables:**
- `entities`: Main entity information (id, name, full_name)
- `entity_facts`: Key-value facts about entities

**Fact Keys Loaded:**
- `timezone` / `current_timezone`
- `communication_style`
- `expertise`
- `preferences`

**Identifier Keys for Resolution:**
- `phone`
- `signal_uuid`
- `discord_id`
- `telegram_id`
- `slack_member_id`
- `signal_username`

## Configuration

Database connection is configured via `~/.openclaw/postgres.json` (loaded by `~/.openclaw/lib/pg-env.ts` at module scope, before any database connection is created). Standard `PG*` environment variables override the config file:
```bash
PGHOST=localhost                    # default
PGDATABASE=${USER//-/_}_memory     # dynamic: e.g., nova_memory, argus_memory
PGUSER=$(whoami)                   # default: current OS user
PGPASSWORD=                        # optional
```

## Output Format

When an entity is found, the hook injects context like:

```
👤 **Talking with:** Dustin Dale Trammell

• **Expertise:** vulnerability research, exploitation, network protocols
• **Current Timezone:** America/Denver
```

If no entity is found, the hook continues silently and only injects semantic recall memories (original behavior).

## Testing

### Library Tests
Test the shared entity-resolver library:
```bash
cd "${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/lib/entity-resolver"
npx tsx test.ts "(512) 692-7184"
```

Results:
- ✅ Entity resolution working
- ✅ Profile loading working
- ✅ Session-aware caching working
- ✅ Multiple identifier types working
- ✅ Cache statistics working

### Hook Integration Tests
Verify the refactored hook works:
```bash
cd "${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/hooks/semantic-recall"
npx tsx verify-refactor.ts
```

Results:
- ✅ Library imports correctly from hook
- ✅ Entity resolution working
- ✅ Caching integration working
- ✅ Profile loading working
- ✅ Database connection working

### Legacy Test (Still Available)
Original standalone test:
```bash
cd "${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/hooks/semantic-recall"
node test-entity-resolution.js "+1 817-896-4104"
```

## Performance Considerations

- Database connection pool (max 5 connections)
- Parallel entity resolution and semantic recall
- Timeout protection prevents hanging
- Connection reuse via pooling
- Query limits (LIMIT 1 for entity, LIMIT 10 for facts)

## Error Handling

All operations fail gracefully:
- Database connection errors → logged, no entity context injected
- Entity not found → logged, no entity context injected
- Timeout exceeded → logged, no entity context injected
- Facts loading error → logged, entity name shown without facts

The hook never throws errors that would block message processing.

## Integration

The hook integrates seamlessly with existing message flow:
1. Message received
2. **Entity context loaded** (new)
3. Semantic recall executed (existing)
4. Both contexts injected into event.messages
5. Agent sees complete context before responding

## Architecture

```
~/.openclaw/
├── lib/
│   ├── pg-env.ts                     # PG credential loader (loaded first)
│   └── entity-resolver/              # Shared library (installed by agent-install.sh)
│       ├── index.ts                  # Main exports (incl. resolveEntityByIdentifiers)
│       ├── resolver.ts               # Core resolution + DB pool + conflict detection
│       ├── cache.ts                  # Session-aware caching
│       ├── types.ts                  # TypeScript interfaces (Entity, ResolveResult, etc.)
│       ├── package.json              # Dependencies (pg)
│       ├── README.md                 # API documentation
│       └── test.ts                   # Test suite
│
└── hooks/
    └── semantic-recall/
        ├── handler.ts                # Channel-aware entity resolution + semantic recall
        ├── HOOK.md                   # Hook documentation
        ├── IMPLEMENTATION.md         # This file
        ├── test-entity-resolution.js  # Legacy test
        └── verify-refactor.ts        # Integration test
```

**Source repo layout** (nova-mind):
```
nova-mind/
├── relationships/lib/entity-resolver/  # Library source
└── memory/hooks/semantic-recall/       # Handler source
```

## Benefits of Refactoring

1. **Reusability**: Other hooks/components can now use entity resolution
2. **Maintainability**: Single source of truth for entity logic
3. **Testability**: Library can be tested independently
4. **Performance**: Shared caching across different uses
5. **Consistency**: Same resolution logic everywhere
6. **Documentation**: Centralized API docs in library README

## Next Steps

Potential future enhancements:
- ✅ ~~Cache entity lookups to reduce database queries~~ (DONE via library)
- ✅ ~~Channel-aware routing for Discord, Telegram, Slack, Signal~~ (DONE — #8/#159/#164)
- ✅ ~~Conflict detection when identifiers match different entities~~ (DONE — #8/#159/#164)
- Add more fact types (interests, projects, relationships)
- Support group chat entity resolution for all participants
- Add entity relationship context (e.g., "talking with your friend Dustin")
- Implement entity context versioning for real-time updates
- Use the entity-resolver library in other hooks and tools
