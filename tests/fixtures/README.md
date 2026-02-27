# Test Fixtures for Nova Memory

This directory contains test data and utilities for the nova-memory system.

## Contents

### 1. `test-data.sql`
SQL seed file containing fabricated but realistic test data:

- **15 Entities:**
  - 8 People (Alice, Bob, Charlie, Diana, Eve, Frank, Grace, Hank)
  - 4 Organizations (Acme Corp, TechStart Inc, OpenSource Foundation, DataViz Labs)
  - 3 AI Agents (TestBot, AnalyticsBot, SecurityBot)

- **75 Entity Facts:**
  - Various types: preferences, roles, contact info, observations
  - Multiple visibility levels: public (~60), hidden (~10), sensitive (~5)
  - Edge cases: special characters, emojis, apostrophes, hyphens
  - Privacy test cases: phone numbers (hidden), birthdays/allergies (sensitive)

- **15 Events:** Milestones, meetings, and significant occurrences

- **8 Lessons:** Learnings from project experience

- **12 Tasks:** Various statuses (pending, in_progress, complete, blocked)

### 2. `generate-test-embeddings.py`
Python script to generate embeddings for test data using OpenAI API.

**Features:**
- Reads entity_facts from database
- Excludes sensitive data from embeddings (privacy protection)
- Generates embeddings using `text-embedding-ada-002`
- Populates `memory_embeddings` table
- Includes dry-run mode and verification

**Usage:**
```bash
# With OPENAI_API_KEY environment variable set
./generate-test-embeddings.py --database test_memory

# With API key as argument
./generate-test-embeddings.py --database test_memory --api-key sk-...

# Dry run (no API calls)
./generate-test-embeddings.py --database test_memory --dry-run

# Verify existing embeddings
./generate-test-embeddings.py --database test_memory --verify-only
```

**Requirements:**
```bash
pip install psycopg2-binary openai
```

### 3. `test-queries.md`
Comprehensive test query documentation including:

- **Semantic Search Queries:** Test embedding-based search
- **Privacy Tests:** Verify visibility enforcement
- **Edge Case Tests:** Special characters, emojis, quotes
- **Aggregation Queries:** Statistics and summaries
- **Data Quality Checks:** Verify data integrity

### 4. `load-test-data.sh`
Shell script that orchestrates the complete test data loading process.

**Usage:**
```bash
# Load into default database (test_memory)
./load-test-data.sh

# Load into specific database
./load-test-data.sh my_test_db
```

**What it does:**
1. Checks if database exists (offers to create if not)
2. Loads SQL test data
3. Verifies data counts
4. Generates embeddings (if OPENAI_API_KEY is set)
5. Provides summary and next steps

## Quick Start

### Option 1: With OpenAI API Key

```bash
# Set your OpenAI API key
export OPENAI_API_KEY="sk-your-key-here"

# Load everything (creates database if needed)
cd tests/fixtures
./load-test-data.sh test_memory
```

### Option 2: Without API Key (Manual Embeddings Later)

```bash
# Load SQL data only
cd tests/fixtures
./load-test-data.sh test_memory

# Generate embeddings later when you have an API key
export OPENAI_API_KEY="sk-your-key-here"
./generate-test-embeddings.py --database test_memory
```

## Data Characteristics

### Realistic Edge Cases

The test data includes:

- **Special characters:** Names with apostrophes (Frank O'Reilly), hyphens (Grace Hopper-Smith), quotes in text
- **Unicode:** Emojis (🚀) in text fields
- **Long text:** Descriptions and notes with multiple lines
- **Null values:** Optional fields left null
- **Various confidence levels:** From 0.7 to 1.0

### Privacy Levels

| Visibility | Count | Example | Embedded? |
|-----------|-------|---------|-----------|
| public | ~60 | Job titles, preferences | ✓ Yes |
| hidden | ~10 | Phone numbers, private emails | ✓ Yes |
| sensitive | ~5 | Birthdays, medical info | ✗ No |

**Important:** Sensitive data is **never** included in embeddings to protect privacy.

### Entity Distribution

- **People (8):** Mix of roles, various detail levels
- **Organizations (4):** Different types and sizes
- **AI Agents (3):** System components with capabilities

## Testing Semantic Search

After loading the data, try these queries:

```bash
# Connect to database
psql -d test_memory

# Who works at Acme Corp?
SELECT e.name, ef.value 
FROM entity_facts ef 
JOIN entities e ON ef.entity_id = e.id 
WHERE ef.key = 'employer' AND ef.value ILIKE '%Acme Corp%';

# Check visibility distribution
SELECT visibility, COUNT(*) 
FROM entity_facts 
GROUP BY visibility;

# Verify embeddings (should be 70 = 75 facts - 5 sensitive)
SELECT COUNT(*) 
FROM memory_embeddings 
WHERE source_type = 'entity_fact';
```

For more test queries, see `test-queries.md`.

## Verification

After loading, you should have:

| Table | Expected Count | Notes |
|-------|---------------|-------|
| entities | 15 | 8 people, 4 orgs, 3 AI |
| entity_facts | 75 | Various visibility levels |
| events | 15 | Historical events |
| lessons | 8 | Project learnings |
| tasks | 12 | Mixed statuses |
| memory_embeddings | 70 | Facts excluding sensitive (if generated) |

## Privacy Testing

The test data is specifically designed to test privacy features:

1. **Sensitive facts exist but aren't embedded:**
   ```sql
   -- These should return different counts:
   SELECT COUNT(*) FROM entity_facts WHERE visibility = 'sensitive';  -- 5
   SELECT COUNT(*) FROM memory_embeddings WHERE content ILIKE '%birthday%';  -- 0
   ```

2. **Hidden facts are embedded but should require special access:**
   - Phone numbers are 'hidden' but searchable (with proper permissions)
   - Sensitive data (birthdays, allergies) are never embedded

## Troubleshooting

### Database Connection Issues

If you get connection errors:
```bash
# Check PostgreSQL is running
pg_isready

# Check your connection settings
psql -l

# Set connection parameters if needed
export PGHOST=localhost
export PGPORT=5432
export PGUSER=your_username
```

### Embedding Generation Fails

Common issues:

1. **No OpenAI API key:**
   ```bash
   export OPENAI_API_KEY="sk-your-key-here"
   ```

2. **Missing Python packages:**
   ```bash
   pip install psycopg2-binary openai
   ```

3. **Rate limits:** Add delays between API calls (modify script if needed)

### Wrong Embedding Count

Expected: 70 embeddings (75 facts - 5 sensitive)

If count is different:
```bash
# Check which facts are excluded
SELECT key, visibility 
FROM entity_facts 
WHERE visibility = 'sensitive';

# Verify embeddings
./generate-test-embeddings.py --database test_memory --verify-only
```

## Maintenance

### Updating Test Data

1. Edit `test-data.sql`
2. Reload: `./load-test-data.sh test_memory`
3. Update `test-queries.md` with new expected results
4. Commit changes to git

### Adding New Test Cases

When adding new test cases:

- Include edge cases (special characters, long text, etc.)
- Add at least one fact for each visibility level
- Update expected counts in this README
- Add corresponding test queries to `test-queries.md`

## Contributing

When modifying these fixtures:

1. Ensure all data is obviously fake (use .example domains, test names, etc.)
2. Maintain variety in data types and edge cases
3. Keep privacy tests comprehensive
4. Update documentation
5. Verify all scripts still work after changes

## License

This test data is part of the nova-memory project. Use freely for testing and development.
