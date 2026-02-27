# Grammar Parser Examples

Real-world examples demonstrating the parser's capabilities.

## Basic Patterns

### Preferences
```python
>>> parse_and_print("John loves pizza")

Input: John loves pizza
Found 1 relation(s):

1. John --[love]--> pizza
   Type: preference
   Confidence: 0.85
   Tense: present
```

### Possession
```python
>>> parse_and_print("That's Sarah's car")

Input: That's Sarah's car
Found 1 relation(s):

1. Sarah --[owns]--> car
   Type: possession
   Confidence: 0.90
```

### Location/Residence
```python
>>> parse_and_print("I live in Austin")

Input: I live in Austin
Found 1 relation(s):

1. I --[live_in]--> Austin
   Type: residence
   Confidence: 0.85
   Tense: present
```

---

## Family Relations

### Siblings
```python
>>> parse_and_print("Mike is my brother")

Input: Mike is my brother
Found 1 relation(s):

1. [speaker] --[has_brother]--> Mike
   Type: family (sibling)
   Confidence: 0.90
```

### Parents
```python
>>> parse_and_print("Sarah is my mother")

Input: Sarah is my mother
Found 1 relation(s):

1. [speaker] --[has_mother]--> Sarah
   Type: family (parent)
   Confidence: 0.90
```

---

## Employment & Education

### Work Location
```python
>>> parse_and_print("Tom works at Google")

Input: Tom works at Google
Found 1 relation(s):

1. Tom --[work_at]--> Google
   Type: employment
   Confidence: 0.85
   Tense: present
```

### Education
```python
>>> parse_and_print("She studies at MIT")

Input: She studies at MIT
Found 1 relation(s):

1. She --[study_at]--> MIT
   Type: education
   Confidence: 0.85
   Tense: present
```

---

## Complex Sentences

### Multiple Relations
```python
>>> parse_and_print("My friend Tom, who works at Google, is visiting")

Input: My friend Tom, who works at Google, is visiting
Found 2+ relation(s):

1. Tom --[work_at]--> Google
   Type: employment
   Confidence: 0.85

2. (Additional relations extracted from main clause)
```

### Compound Location
```python
>>> parse_and_print("Sarah works at Apple in California")

Input: Sarah works at Apple in California
Found 2 relation(s):

1. Sarah --[work_at]--> Apple
   Type: employment
   Confidence: 0.85

2. Sarah --[work_in]--> California
   Type: location
   Confidence: 0.75
```

---

## Negation

```python
>>> parse_and_print("John doesn't like vegetables")

Input: John doesn't like vegetables
Found 1 relation(s):

1. John --[like]--> vegetables
   Type: preference
   Confidence: 0.85
   Tense: present
   Negated: True
```

---

## Temporal Information

```python
>>> parse_and_print("We met in 2019")

Input: We met in 2019
Found 1 relation(s):

1. We --[meet_in]--> 2019
   Type: event
   Confidence: 0.80
   Tense: past
```

---

## Batch Processing

```python
from grammar_parser import GrammarParser

parser = GrammarParser()

messages = [
    "John loves pizza",
    "Sarah works at Google",
    "Mike is my brother",
    "I live in Austin"
]

for msg in messages:
    relations = parser.parse_sentence(msg)
    print(f"\n{msg}:")
    for rel in relations:
        print(f"  → {rel.subject} --{rel.predicate}--> {rel.object}")
```

**Output:**
```
John loves pizza:
  → John --love--> pizza

Sarah works at Google:
  → Sarah --work_at--> Google

Mike is my brother:
  → [speaker] --has_brother--> Mike

I live in Austin:
  → I --live_in--> Austin
```

---

## Conversation Parsing

```python
from grammar_parser import parse_conversation

messages = [
    {"speaker": "user", "text": "My name is John"},
    {"speaker": "user", "text": "I work at Google"},
    {"speaker": "user", "text": "I love pizza"},
]

speaker_names = {"user": "John"}

relations = parse_conversation(messages, speaker_names)

for rel in relations:
    print(f"{rel.subject} --{rel.predicate}--> {rel.object} (type: {rel.relation_type.value})")
```

**Output:**
```
John --work_at--> Google (type: employment)
John --love--> pizza (type: preference)
```

---

## CLI Usage

### Basic Extraction
```bash
$ python3 extract_cli.py "John loves pizza"
```

```json
[
  {
    "subject": "John",
    "predicate": "love",
    "object": "pizza",
    "relation_type": "preference",
    "subtype": null,
    "modifiers": [],
    "prepositions": [],
    "temporal": null,
    "tense": "present",
    "negated": false,
    "confidence": 0.85,
    "source_text": "John loves pizza",
    "is_symmetric": false
  }
]
```

### With Storage
```bash
$ echo "Sarah works at Google" | python3 extract_cli.py | python3 store_relations.py
```

```
[EMPLOYMENT] Sarah @ Google (confidence: 0.85)

Stored 1/1 relation(s)
```

### Multiple Sentences
```bash
$ cat messages.txt
John loves pizza.
Sarah works at Google.
Mike is my brother.

$ cat messages.txt | python3 extract_cli.py | python3 store_relations.py
```

---

## Python API Examples

### Basic Usage
```python
from grammar_parser import parse_sentence

# Parse single sentence
relations = parse_sentence("John loves pizza")

# Access relation properties
for rel in relations:
    print(f"Subject: {rel.subject}")
    print(f"Predicate: {rel.predicate}")
    print(f"Object: {rel.object}")
    print(f"Type: {rel.relation_type.value}")
    print(f"Confidence: {rel.confidence:.2f}")
    print(f"Tense: {rel.tense}")
    print(f"Negated: {rel.negated}")
```

### With Context
```python
context = {
    "speaker_names": {"user1": "John", "user2": "Sarah"},
    "current_speaker": "user1"
}

relations = parse_sentence("I live in Austin", context=context)
# Will resolve "I" to "John" based on context
```

### Filtering by Type
```python
from relation_types import RelationType

relations = parse_sentence("John loves pizza and works at Google")

# Get only preferences
preferences = [r for r in relations if r.relation_type == RelationType.PREFERENCE]

# Get only employment
employment = [r for r in relations if r.relation_type == RelationType.EMPLOYMENT]
```

### Filtering by Confidence
```python
relations = parse_sentence("Some complex sentence...")

# High-confidence only
high_conf = [r for r in relations if r.confidence >= 0.8]

# Store immediately
for rel in high_conf:
    store_relation(rel)

# Low-confidence: send to LLM for verification
low_conf = [r for r in relations if r.confidence < 0.8]
for rel in low_conf:
    verified = verify_with_llm(rel)
    store_relation(verified)
```

---

## Error Handling

```python
from grammar_parser import GrammarParser

parser = GrammarParser()

try:
    relations = parser.parse_sentence("Some text")
except Exception as e:
    print(f"Parsing failed: {e}")
    # Fall back to LLM extraction
    relations = llm_extract("Some text")
```

---

## Custom Relation Storage

```python
from grammar_parser import parse_sentence
from relation_types import RelationType

def store_to_database(relations):
    for rel in relations:
        if rel.relation_type == RelationType.FAMILY:
            # Store in relationships table
            db.insert_relationship(
                entity_a=rel.subject,
                entity_b=rel.object,
                relationship_type=rel.subtype,
                is_symmetric=rel.is_symmetric
            )
        
        elif rel.relation_type == RelationType.PREFERENCE:
            # Store in facts table
            db.insert_fact(
                entity=rel.subject,
                key="preference",
                value=rel.object,
                sentiment="positive" if not rel.negated else "negative"
            )
        
        # ... other types ...

relations = parse_sentence("John loves pizza")
store_to_database(relations)
```

---

## Debugging

```python
from grammar_parser import parse_and_print

# Pretty-print relations for debugging
parse_and_print("John loves pizza")
```

```python
import spacy
from grammar_patterns import extract_simple_svo

# Debug specific pattern extractor
nlp = spacy.load("en_core_web_sm")
doc = nlp("John loves pizza")

# Print dependency tree
for token in doc:
    print(f"{token.text:15} {token.dep_:10} {token.head.text}")

# Test pattern
relations = extract_simple_svo(doc)
print(f"Extracted: {relations}")
```

---

## Integration Example

```python
#!/usr/bin/env python3
"""
Example memory-extract hook with grammar parser integration.
"""

from grammar_parser import parse_sentence

def extract_memories(message: str):
    # Try grammar-based extraction first
    relations = parse_sentence(message)
    
    # Check confidence
    avg_confidence = sum(r.confidence for r in relations) / len(relations) if relations else 0
    
    if avg_confidence >= 0.75:
        # High confidence - use grammar results
        print(f"Grammar extraction (confidence: {avg_confidence:.2f})")
        return relations
    else:
        # Low confidence - fall back to LLM
        print(f"Falling back to LLM (confidence: {avg_confidence:.2f})")
        return llm_extract(message)

# Use in hook
message = "John works at Google and loves pizza"
relations = extract_memories(message)

for rel in relations:
    store_relation(rel)
```

---

## Performance Monitoring

```python
import time
from grammar_parser import parse_sentence

def benchmark_extraction(messages: list):
    start = time.time()
    
    total_relations = 0
    for msg in messages:
        relations = parse_sentence(msg)
        total_relations += len(relations)
    
    elapsed = time.time() - start
    
    print(f"Processed {len(messages)} messages in {elapsed:.2f}s")
    print(f"Average: {elapsed/len(messages)*1000:.1f}ms per message")
    print(f"Extracted {total_relations} relations")
    print(f"Average: {total_relations/len(messages):.1f} relations per message")

# Test
messages = [
    "John loves pizza",
    "Sarah works at Google",
    "Mike is my brother",
    # ... more messages ...
]

benchmark_extraction(messages)
```

---

## See Also

- **Grammar rules:** `GRAMMAR_RULES.md`
- **Integration guide:** `INTEGRATION.md`
- **API documentation:** Docstrings in `grammar_parser.py`
- **Tests:** `tests/test_examples.py`
