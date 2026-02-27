# Grammar-Based Memory Extraction

Deterministic parsing rules for extracting relations from natural language sentences.

## Architecture

```
User Message
    ↓
grammar_parser.py (parse_sentence)
    ↓
spaCy Dependency Parse
    ↓
Pattern Matchers (relation extractors)
    ↓
Relation Classifier
    ↓
Structured Relations (JSON)
    ↓
Memory Database
```

## Components

- **`relation_types.py`** - Taxonomy of relation types
- **`grammar_patterns.py`** - Sentence pattern definitions
- **`grammar_parser.py`** - Main parsing engine
- **`extractors/`** - Specialized extractors for each relation type
- **`tests/`** - Test cases for all patterns

## Usage

```python
from grammar_parser import parse_sentence

text = "John loves pizza"
relations = parse_sentence(text)
# [Relation(subject="John", predicate="loves", object="pizza", type="preference")]
```

## Integration

See `INTEGRATION.md` for hooking into the memory-extract system.
