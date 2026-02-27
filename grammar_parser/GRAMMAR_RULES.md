# Grammar Rules for Memory Extraction

Comprehensive documentation of English grammar patterns used for deterministic relation extraction.

## Table of Contents

1. [Sentence Structure Patterns](#sentence-structure-patterns)
2. [Entity Recognition](#entity-recognition)
3. [Relation-Indicating Verbs](#relation-indicating-verbs)
4. [Extraction Rules](#extraction-rules)
5. [Temporal & Spatial Markers](#temporal--spatial-markers)
6. [Edge Cases & Limitations](#edge-cases--limitations)

---

## Sentence Structure Patterns

### 1. Simple Subject-Verb-Object (S-V-O)

**Pattern:** `[Subject] [Verb] [Object]`

**Examples:**
- "John loves pizza" → `John --loves--> pizza`
- "Sarah owns a car" → `Sarah --owns--> car`
- "I like coffee" → `I --like--> coffee`

**Dependency Structure:**
```
    loves (ROOT)
    /    \
John    pizza
(nsubj)  (dobj)
```

**Extraction Rule:**
1. Find ROOT verb
2. Extract nsubj (nominal subject)
3. Extract dobj (direct object)
4. Classify relation by verb

---

### 2. Subject-Verb-Indirect Object-Direct Object (S-V-IO-DO)

**Pattern:** `[Subject] [Verb] [IndirectObject] [DirectObject]`

**Examples:**
- "John gave Sarah a book" → `John --gave--> book (recipient: Sarah)`
- "I told Tom the news" → `I --told--> news (recipient: Tom)`

**Dependency Structure:**
```
     gave (ROOT)
    / | \
John  Sarah  book
(nsubj) (iobj) (dobj)
```

---

### 3. Copula Constructions (Be-Verbs)

**Pattern:** `[Subject] [be] [Complement]`

**Types:**

#### a) State/Attribute
- "Sarah is tall" → `Sarah --is--> tall` (attribute)
- "The house is big" → `house --is--> big`

#### b) Identity/Definition
- "Tom is a doctor" → `Tom --is--> doctor` (profession)
- "Mike is my brother" → `[speaker] --has_sibling--> Mike`

#### c) Location
- "I am in Austin" → `I --located_in--> Austin`
- "The book is on the table" → `book --located_on--> table`

**Special Handling for Possessive Complements:**
- "Mike is **my** brother" → Detect `poss` dependency on complement
- Transform to: `[speaker] --has_brother--> Mike`
- Reciprocal: `Mike --sibling_of--> [speaker]`

---

### 4. Possessive Relations

**Pattern 1: Genitive ('s)**
- "Sarah's car" → `Sarah --owns--> car`
- "John's house" → `John --owns--> house`

**Pattern 2: Possessive Determiners**
- "my brother" (in context) → `[speaker] --has_sibling--> [brother_name]`
- "his car" → `[he] --owns--> car`

**Dependency Marker:**
```
    car
    /
Sarah
(poss)
```

---

### 5. Prepositional Phrases

**Pattern:** `[Subject] [Verb] [Preposition] [Object]`

**Location Prepositions:** `in`, `at`, `on`, `from`, `near`
- "I live **in** Austin" → `I --lives_in--> Austin`
- "She works **at** Google" → `She --works_at--> Google`
- "Tom is **from** Texas" → `Tom --from--> Texas`

**Temporal Prepositions:** `since`, `during`, `until`, `in [year]`
- "We met **in 2019**" → `We --met--> [temporal: 2019]`
- "She has lived here **since 2020**" → `She --lives_in--> here [since: 2020]`

---

### 6. Relative Clauses

**Pattern:** `[Noun] [who/that/which] [Verb Phrase]`

**Examples:**
- "My friend Tom, **who works at Google**, is visiting"
  - Extract 1: `[speaker] --has_friend--> Tom`
  - Extract 2: `Tom --works_at--> Google`

**Dependency Marker:** `relcl` (relative clause)

```
     friend
       |
    works (relcl)
      |
    Google
```

---

### 7. Compound Subjects/Objects

**Compound Subjects:**
- "John and Sarah are friends"
  - `John + Sarah --are--> friends`
  - Can split into: `John --friend_of--> Sarah`

**Compound Objects:**
- "I like pizza and pasta"
  - `I --likes--> pizza`
  - `I --likes--> pasta`

**Dependency Marker:** `conj` (conjunction)

---

## Entity Recognition

### Proper Nouns
- **Capitalized words** (not at sentence start) → Entity
- "John", "Sarah", "Google", "Austin"

### Personal Pronouns
- **Subject:** I, you, he, she, it, we, they
- **Object:** me, you, him, her, it, us, them
- **Possessive:** my, your, his, her, its, our, their

**Resolution:**
- `I`, `me`, `my` → `[speaker]`
- `you`, `your` → `[listener]` (or specific person in context)
- Others require anaphora resolution

### Demonstratives
- `this`, `that`, `these`, `those`
- Refer to previously mentioned entities

---

## Relation-Indicating Verbs

### Possession Verbs
- `have`, `has`, `had`, `own`, `owns`, `possess`, `belong to`
- → **RelationType.POSSESSION**

### Preference Verbs
**Positive:**
- `like`, `love`, `enjoy`, `prefer`, `adore`, `appreciate`, `fancy`

**Negative:**
- `hate`, `dislike`, `despise`, `can't stand`, `loathe`

→ **RelationType.PREFERENCE**

### Location/Residence Verbs
- `live`, `stay`, `reside`, `dwell`, `inhabit`
- → **RelationType.RESIDENCE**

- `work`, `based`, `located`
- → **RelationType.LOCATION** (work)

- `from`, `born in`, `native to`, `grew up in`
- → **RelationType.ORIGIN**

### Family Relation Nouns (used with "be")
- `brother`, `sister`, `mother`, `father`, `son`, `daughter`
- `uncle`, `aunt`, `cousin`, `nephew`, `niece`
- `grandmother`, `grandfather`
- → **RelationType.FAMILY** with appropriate subtype

### Romantic Relation Nouns
- `boyfriend`, `girlfriend`, `partner`, `spouse`, `husband`, `wife`
- `fiancé`, `fiancée`
- → **RelationType.ROMANTIC** with subtype

### Employment/Education Verbs
- `work`, `employed`, `job`, `position`
- → **RelationType.EMPLOYMENT**

- `study`, `student`, `attend`, `enrolled`, `graduate`
- → **RelationType.EDUCATION**

---

## Extraction Rules

### Rule 1: Simple S-V-O Extraction
```python
FOR each ROOT verb IN sentence:
    subject = find_child(verb, dep="nsubj")
    object = find_child(verb, dep="dobj")
    
    IF subject AND object:
        relation_type = classify_by_verb(verb, object)
        YIELD Relation(subject, verb, object, relation_type)
```

### Rule 2: Possessive Extraction
```python
FOR each token IN sentence:
    IF token.dep == "poss":
        possessor = token.text
        possessed = token.head.text
        
        YIELD Relation(possessor, "owns", possessed, POSSESSION)
```

### Rule 3: Copula Relation Extraction
```python
FOR each ROOT verb WHERE verb.lemma == "be":
    subject = find_child(verb, dep="nsubj")
    complement = find_child(verb, dep="attr" OR "acomp")
    
    IF complement HAS child WITH dep="poss":
        # "Mike is my brother" case
        possessor = resolve_pronoun(poss_child)
        YIELD Relation(possessor, f"has_{complement}", subject, FAMILY)
    
    ELSE:
        YIELD Relation(subject, "is", complement, ATTRIBUTE)
```

### Rule 4: Location/Prepositional Extraction
```python
FOR each ROOT verb:
    FOR each child WHERE dep="prep":
        prep = child.text
        prep_object = find_child(child, dep="pobj")
        
        IF prep IN ["in", "at", "from"]:
            predicate = f"{verb}_{prep}"
            YIELD Relation(subject, predicate, prep_object, LOCATION)
```

### Rule 5: Relative Clause Extraction
```python
FOR each token WHERE dep="relcl":
    subject = token.head.text  # The modified noun
    verb = token.text
    object = find_child(token, dep="dobj")
    
    IF object:
        YIELD Relation(subject, verb, object, classify_by_verb(verb))
```

---

## Temporal & Spatial Markers

### Temporal Expressions

**Absolute Dates:**
- "in 2019", "on January 5th", "2024-01-01"
- Extract as `temporal` field in Relation

**Relative Time:**
- "yesterday", "last week", "recently", "soon"
- Map to approximate temporal values

**Duration:**
- "for 5 years", "since 2020"
- Extract as relation modifier

**Tense Detection:**
- **Past:** VBD (lived), VBN (has lived)
- **Present:** VBZ (lives), VBP (live), VBG (living)
- **Future:** "will live", "going to live"

### Spatial Prepositions

**Location:** `in`, `at`, `on`, `near`, `by`, `beside`
**Direction:** `to`, `from`, `toward`, `into`, `out of`
**Position:** `above`, `below`, `under`, `over`

---

## Edge Cases & Limitations

### 1. Anaphora Resolution
**Challenge:** Pronouns refer to entities mentioned earlier

**Example:**
```
"I met Sarah yesterday. She works at Google."
```
- "She" → needs resolution to "Sarah"

**Current Limitation:** Single-sentence parsing doesn't resolve across sentences.

**Solution:** Multi-sentence context tracking (TODO)

---

### 2. Ambiguous Pronouns

**Example:**
```
"John told Tom that he was wrong."
```
- "he" could refer to John OR Tom

**Solution:** Require context or leave as `[he]`

---

### 3. Implicit Relations

**Example:**
```
"John and Sarah have been together for 5 years."
```
- "together" implies romantic relationship, but not explicit

**Solution:** Pattern matching for common implicit phrases

---

### 4. Negation Scope

**Example:**
```
"I don't think John likes pizza."
```
- Negation on "think", not "likes"

**Current Limitation:** Negation detected at verb level only

---

### 5. Complex Nested Clauses

**Example:**
```
"The person who John said that Mary met was tall."
```

**Limitation:** Deep nesting may produce incomplete relations

---

### 6. Idiomatic Expressions

**Example:**
```
"John kicked the bucket."
```
- Literal: John kicked a bucket
- Idiomatic: John died

**Solution:** Idiom detection (future enhancement)

---

### 7. Sarcasm & Irony

**Example:**
```
"Oh yeah, I *love* getting stuck in traffic." [sarcastic]
```

**Limitation:** Grammar-based parsing cannot detect sarcasm

**Solution:** Requires sentiment analysis or LLM fallback

---

## Confidence Scoring

Relations are assigned confidence scores (0-1) based on:

1. **Pattern Specificity**
   - Possessive patterns: +0.2
   - Copula relations: +0.2
   - Simple S-V-O: +0.1

2. **Relation Type Classification**
   - Classified (not OTHER): +0.1
   - Has subtype: +0.05

3. **Completeness**
   - Missing object: -0.1
   - Missing subject: invalid

4. **Ambiguity**
   - Unresolved pronoun: -0.1
   - Multiple interpretations: -0.15

**Threshold for automatic storage:** confidence ≥ 0.7

---

## Integration with LLM Extraction

**Hybrid Approach:**

1. **Grammar parser** runs first (fast, deterministic)
2. Extract high-confidence relations (≥ 0.7)
3. For low-confidence or complex sentences → **LLM fallback**
4. LLM validates and enriches grammar-extracted relations

**Cost Optimization:**
- Grammar parser: ~80% of common patterns (free)
- LLM: ~20% of complex cases (paid)
- Reduces API costs by 80%

---

## Testing Strategy

### Unit Tests
- Individual pattern extractors
- Verb classification
- Entity recognition

### Integration Tests
- Full sentence parsing
- Multi-relation extraction
- Conversation-level parsing

### Regression Tests
- Task spec examples
- Known edge cases
- Previous failures

See `tests/` directory for implementation.
