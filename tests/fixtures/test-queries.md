# Test Queries for Memory System

This document contains sample queries for testing the memory system, including semantic search and privacy filtering.

## Setup

Assumes test data has been loaded:
```bash
./tests/fixtures/load-test-data.sh test_memory
```

## Semantic Search Queries

These queries test the embedding-based semantic search functionality.

### Query 1: Favorite Color (High Similarity Expected)

**Query:** "What is Alice's favorite color?"

**Expected Result:**
- Entity: Alice (id=1)
- Fact: favorite_color = blue
- Similarity: > 0.6
- Source: direct_conversation

**SQL Test:**
```sql
SELECT 
    me.content,
    me.embedding <=> (
        SELECT embedding FROM memory_embeddings 
        WHERE content ILIKE '%favorite color%' LIMIT 1
    ) as similarity
FROM memory_embeddings me
WHERE me.content ILIKE '%Alice%' AND me.content ILIKE '%color%'
ORDER BY similarity
LIMIT 3;
```

### Query 2: Employment (Exact Match)

**Query:** "Who works at Acme Corp?"

**Expected Results:**
- Bob Builder (id=2): employer = Acme Corp
- Diana Prince (id=4): employer = Acme Corp

**SQL Test:**
```sql
SELECT e.name, ef.key, ef.value
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE ef.key = 'employer' AND ef.value ILIKE '%Acme Corp%';
```

### Query 3: Coffee Preference (Semantic)

**Query:** "Who likes coffee?"

**Expected Results:**
- Alice: coffee_preference = oat milk latte, no sugar
- Charlie: coffee_obsession = third-wave specialty coffee only
- Charlie: side_project = building a coffee review app

**Note:** Semantic search should find Charlie's "coffee_obsession" even though the query uses "likes"

### Query 4: Programming Skills

**Query:** "Who knows Python?"

**Expected Results:**
- Alice: programming_languages = Python, JavaScript, Go
- Charlie: favorite_language = R and Python for data science

### Query 5: DevOps/Infrastructure

**Query:** "Who has DevOps experience?"

**Expected Results:**
- Bob: job_title = Build Engineer
- Bob: years_of_experience = 12 years in DevOps
- Grace: job_title = DevOps Engineer
- Grace: favorite_tool = Terraform and Ansible

### Query 6: Remote Work

**Query:** "Who works remotely?"

**Expected Result:**
- Alice: works_remotely = true

### Query 7: Project Management

**Query:** "Who manages projects?"

**Expected Results:**
- Diana: job_title = Senior Project Manager
- Diana: methodology_preference = Scrum with strict sprint boundaries
- Diana: certification = PMP and Certified Scrum Master

### Query 8: Security Expertise

**Query:** "Who is a security expert?"

**Expected Results:**
- Eve: job_title = Security Researcher
- Eve: privacy_advocate = strong believer in data minimization
- SecurityBot (AI): capabilities = threat detection, security monitoring

### Query 9: Marketing

**Query:** "Who handles marketing?"

**Expected Results:**
- Frank: job_title = Head of Marketing & Growth
- Frank: loves_emojis = 🚀 Uses emojis in all communications

### Query 10: Organizations by Industry

**Query:** "What companies work with AI?"

**Expected Result:**
- TechStart Inc: industry = Artificial Intelligence and SaaS

## Privacy & Visibility Tests

These queries test that privacy levels are properly enforced.

### Test 1: Hidden Data Not in Search Results

**Query:** "What is Alice's phone number?"

**Expected Behavior:**
- Should NOT appear in semantic search results (visibility = 'hidden')
- Direct query to entity_facts should require proper permissions
- Phone numbers for Alice, Bob, and others should not be searchable

**SQL Test (should return empty or require admin access):**
```sql
-- This should respect visibility settings
SELECT content 
FROM memory_embeddings 
WHERE content ILIKE '%phone%' AND content ILIKE '%555%';

-- Expected: No results (phone numbers are 'hidden' visibility)
```

### Test 2: Sensitive Data Excluded from Embeddings

**Query:** "What is Alice's birthday?"

**Expected Behavior:**
- Should NOT appear in memory_embeddings table (visibility = 'sensitive')
- Fact exists in entity_facts but with visibility='sensitive'
- No embeddings should contain birthday, medical, or SSN data

**SQL Test:**
```sql
-- Check that sensitive facts exist in entity_facts
SELECT key, visibility FROM entity_facts WHERE visibility = 'sensitive';

-- But NOT in memory_embeddings
SELECT content FROM memory_embeddings 
WHERE content ILIKE '%birthday%' OR content ILIKE '%allergies%';

-- Expected: entity_facts has sensitive data, memory_embeddings does not
```

### Test 3: Public Data Freely Searchable

**Query:** "What is Alice's job title?"

**Expected Result:**
- Alice: job_title = Senior Software Engineer (visibility = 'public')
- Should appear in both entity_facts and memory_embeddings

### Test 4: Eve's Privacy Settings

**Query:** "Does Eve use Tor?"

**Expected Behavior:**
- Fact exists: uses_tor = true (visibility = 'sensitive')
- Should NOT appear in embeddings
- Demonstrates privacy-focused data handling

**SQL Test:**
```sql
-- Exists in entity_facts
SELECT * FROM entity_facts 
WHERE entity_id = 5 AND key = 'uses_tor';

-- Should NOT exist in embeddings
SELECT * FROM memory_embeddings 
WHERE content ILIKE '%Eve%' AND content ILIKE '%tor%';
```

## Edge Cases & Special Characters

### Test 1: Special Characters in Names

**Query:** "Who is Frank O'Reilly?"

**Expected Behavior:**
- Should handle apostrophe in name correctly
- Should return Frank's entity and facts

### Test 2: Hyphenated Names

**Query:** "Who is Grace Hopper-Smith?"

**Expected Behavior:**
- Should handle hyphenated name correctly
- Should return Grace's entity and facts

### Test 3: Quotes in Data

**Query:** "What is Frank's favorite quote?"

**Expected Result:**
- Frank: favorite_quote = Don't just market—tell a story!
- Should handle escaped quotes properly

### Test 4: Emojis

**Query:** "Who uses emojis?"

**Expected Result:**
- Frank: loves_emojis = 🚀 Uses emojis in all communications
- Should handle emoji characters in data

## Aggregation & Analysis Queries

### Query 1: Count by Visibility Level

```sql
SELECT visibility, COUNT(*) as count
FROM entity_facts
GROUP BY visibility
ORDER BY count DESC;
```

**Expected:**
- public: ~60 facts
- hidden: ~10 facts
- sensitive: ~5 facts

### Query 2: Facts per Entity Type

```sql
SELECT e.type, COUNT(ef.id) as fact_count
FROM entities e
LEFT JOIN entity_facts ef ON e.id = ef.entity_id
GROUP BY e.type
ORDER BY fact_count DESC;
```

**Expected:**
- person: ~60 facts
- organization: ~15 facts
- ai: ~7 facts

### Query 3: High Confidence Facts

```sql
SELECT e.name, ef.key, ef.value, ef.confidence
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE ef.confidence >= 0.95
ORDER BY ef.confidence DESC;
```

**Expected:** Many facts with confidence >= 0.95 (permanent identities, verified info)

### Query 4: Recent Events

```sql
SELECT title, event_date, description
FROM events
WHERE event_date >= '2024-06-01'
ORDER BY event_date DESC;
```

**Expected:** 10 events from June 2024 onwards

### Query 5: Task Status Summary

```sql
SELECT status, COUNT(*) as count
FROM tasks
GROUP BY status
ORDER BY count DESC;
```

**Expected:**
- pending: 5 tasks
- in_progress: 4 tasks
- complete: 3 tasks

### Query 6: Blocked Tasks

```sql
SELECT title, blocked_reason
FROM tasks
WHERE blocked = true;
```

**Expected:** 2 blocked tasks with reasons

## Semantic Search with Similarity Scores

For these queries, use pgvector's `<=>` operator for cosine distance:

### Example: Find Similar Facts

```sql
-- First, get embedding for search term
WITH search_embedding AS (
    SELECT embedding 
    FROM memory_embeddings 
    WHERE content ILIKE '%favorite color%' 
    LIMIT 1
)
-- Then find similar content
SELECT 
    content,
    1 - (embedding <=> (SELECT embedding FROM search_embedding)) as similarity_score
FROM memory_embeddings
ORDER BY embedding <=> (SELECT embedding FROM search_embedding)
LIMIT 10;
```

**Expected:** 
- High similarity (>0.6) for color-related facts
- Lower similarity for unrelated facts

## Data Quality Checks

### Check 1: All Entities Have Facts

```sql
SELECT e.id, e.name, COUNT(ef.id) as fact_count
FROM entities e
LEFT JOIN entity_facts ef ON e.id = ef.entity_id
GROUP BY e.id, e.name
HAVING COUNT(ef.id) = 0;
```

**Expected:** No results (all entities should have at least one fact)

### Check 2: Embedding Count Matches Non-Sensitive Facts

```sql
-- Count non-sensitive facts
SELECT COUNT(*) as non_sensitive_facts
FROM entity_facts
WHERE visibility != 'sensitive';

-- Count embeddings
SELECT COUNT(*) as embedding_count
FROM memory_embeddings
WHERE source_type = 'entity_fact';
```

**Expected:** Counts should match (70 facts excluded from embeddings: the 5 sensitive ones)

### Check 3: No Orphaned Embeddings

```sql
SELECT me.source_id
FROM memory_embeddings me
WHERE me.source_type = 'entity_fact'
AND NOT EXISTS (
    SELECT 1 FROM entity_facts ef WHERE ef.id::text = me.source_id
);
```

**Expected:** No results (all embeddings should have corresponding facts)

## Notes

- All queries assume PostgreSQL with pgvector extension
- Similarity threshold of 0.6 is a guideline; actual thresholds may vary
- Privacy enforcement should happen at multiple levels: storage, embedding generation, and query time
- Test data includes realistic edge cases but uses obviously fake information
