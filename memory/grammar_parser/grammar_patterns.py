"""
Grammar Pattern Definitions

Sentence structure patterns for extracting relations based on dependency parsing.
Each pattern defines what to look for in the parse tree and how to extract relations.
"""

from typing import List, Dict, Callable, Optional
from dataclasses import dataclass
import spacy
from spacy.tokens import Token, Doc


@dataclass
class GrammarPattern:
    """Defines a grammar pattern for relation extraction."""
    
    name: str
    description: str
    pattern_fn: Callable[[Doc], List[Dict]]  # Function that extracts relations from parsed doc
    priority: int = 5                         # Higher = checked first
    examples: List[str] = None
    
    def __post_init__(self):
        if self.examples is None:
            self.examples = []


def get_subject_tokens(token: Token) -> List[Token]:
    """Get all tokens that are part of the subject (including compounds, modifiers)."""
    subject_tokens = [token]
    
    # Add compound subjects (e.g., "my brother Tom")
    for child in token.children:
        if child.dep_ in ["compound", "amod", "poss"]:
            subject_tokens.append(child)
    
    # Sort by position in sentence
    subject_tokens.sort(key=lambda t: t.i)
    return subject_tokens


def get_object_tokens(token: Token) -> List[Token]:
    """Get all tokens that are part of the object (including compounds, modifiers)."""
    object_tokens = [token]
    
    # Add compounds and modifiers
    for child in token.children:
        if child.dep_ in ["compound", "amod", "det"]:
            object_tokens.append(child)
    
    object_tokens.sort(key=lambda t: t.i)
    return object_tokens


def get_prepositional_objects(verb_token: Token) -> List[Dict]:
    """Extract prepositional phrases attached to a verb."""
    prep_phrases = []
    
    for child in verb_token.children:
        if child.dep_ == "prep":
            prep = child.text
            # Find the object of the preposition
            for pobj in child.children:
                if pobj.dep_ == "pobj":
                    prep_phrases.append({
                        "prep": prep,
                        "object": pobj.text,
                        "object_token": pobj
                    })
    
    return prep_phrases


def resolve_possessive(token: Token) -> Optional[str]:
    """Resolve possessive pronouns to entity references."""
    poss_map = {
        "my": "[speaker]",
        "your": "[listener]",
        "his": "[he]",
        "her": "[she]",
        "their": "[they]",
        "our": "[we]",
        "its": "[it]"
    }
    return poss_map.get(token.text.lower())


def get_tense(verb_token: Token) -> str:
    """Determine verb tense from token."""
    tag = verb_token.tag_
    
    if tag in ["VBD", "VBN"]:  # Past, past participle
        return "past"
    elif tag in ["VBZ", "VBP", "VBG"]:  # Present
        return "present"
    elif "will" in [t.text.lower() for t in verb_token.lefts]:
        return "future"
    else:
        return "present"


def is_negated(verb_token: Token) -> bool:
    """Check if verb is negated."""
    for child in verb_token.children:
        if child.dep_ == "neg":
            return True
    return False


# ============================================================================
# PATTERN EXTRACTION FUNCTIONS
# ============================================================================

def extract_simple_svo(doc: Doc) -> List[Dict]:
    """
    Extract simple Subject-Verb-Object patterns.
    
    Examples:
        - "John loves pizza"
        - "Sarah owns a car"
        - "I like coffee"
    """
    relations = []
    
    for token in doc:
        # Find main verbs (ROOT)
        if token.dep_ == "ROOT" and token.pos_ == "VERB":
            subject = None
            obj = None
            
            # Find subject
            for child in token.children:
                if child.dep_ in ["nsubj", "nsubjpass"]:
                    subject = " ".join([t.text for t in get_subject_tokens(child)])
                    subject_token = child
                
                # Find object
                elif child.dep_ in ["dobj", "attr"]:
                    obj = " ".join([t.text for t in get_object_tokens(child)])
                    obj_token = child
            
            if subject and obj:
                # Check for possessive subject
                if subject_token.pos_ == "PRON":
                    for poss_child in subject_token.children:
                        if poss_child.dep_ == "poss":
                            subject = resolve_possessive(poss_child) or subject
                
                relations.append({
                    "subject": subject,
                    "predicate": token.lemma_,
                    "object": obj,
                    "verb_token": token,
                    "tense": get_tense(token),
                    "negated": is_negated(token),
                    "pattern": "simple_svo"
                })
    
    return relations


def extract_possessive(doc: Doc) -> List[Dict]:
    """
    Extract possessive relations.
    
    Examples:
        - "That's Sarah's car"
        - "John's house is big"
        - "My brother Tom"
    """
    relations = []
    
    for token in doc:
        # Look for possessive markers ('s)
        if token.dep_ == "poss":
            possessor = token.text
            possessed = token.head.text
            
            # Get the full possessed noun phrase
            possessed_tokens = get_object_tokens(token.head)
            possessed = " ".join([t.text for t in possessed_tokens if t != token])
            
            # Check if possessor is a pronoun
            if token.pos_ == "PRON":
                possessor = resolve_possessive(token) or possessor
            
            relations.append({
                "subject": possessor,
                "predicate": "owns",
                "object": possessed,
                "tense": "present",
                "negated": False,
                "pattern": "possessive"
            })
    
    return relations


def extract_copula_relations(doc: Doc) -> List[Dict]:
    """
    Extract relations using copula (be verbs).
    
    Examples:
        - "Mike is my brother"
        - "Sarah is a teacher"
        - "I am from Austin"
        - "Tom is tall"
    """
    relations = []
    
    for token in doc:
        # Look for copula as ROOT
        if token.dep_ == "ROOT" and token.lemma_ == "be":
            subject = None
            complement = None
            
            # Find subject
            for child in token.children:
                if child.dep_ in ["nsubj", "nsubjpass"]:
                    subject = " ".join([t.text for t in get_subject_tokens(child)])
                    subject_token = child
                    
                    # Resolve possessive pronouns in subject
                    for subchild in child.children:
                        if subchild.dep_ == "poss":
                            resolved = resolve_possessive(subchild)
                            if resolved:
                                subject = f"{resolved}'s {child.text}"
                
                # Find complement (attr, acomp, or prep phrase)
                elif child.dep_ in ["attr", "acomp"]:
                    complement = " ".join([t.text for t in get_object_tokens(child)])
                    complement_token = child
            
            # Check for prepositional phrases (location)
            prep_phrases = get_prepositional_objects(token)
            
            if subject:
                if complement:
                    # Handle possessive complements (my brother)
                    for child in complement_token.children:
                        if child.dep_ == "poss":
                            resolved = resolve_possessive(child)
                            if resolved:
                                # "Mike is my brother" -> speaker has_sibling Mike
                                relations.append({
                                    "subject": resolved,
                                    "predicate": f"has_{complement}",
                                    "object": subject,
                                    "tense": get_tense(token),
                                    "negated": is_negated(token),
                                    "pattern": "copula_relation"
                                })
                                continue
                    
                    # Otherwise normal copula
                    relations.append({
                        "subject": subject,
                        "predicate": "is",
                        "object": complement,
                        "tense": get_tense(token),
                        "negated": is_negated(token),
                        "pattern": "copula_attribute"
                    })
                
                # Location from prepositional phrase
                for prep in prep_phrases:
                    if prep["prep"] in ["in", "at", "from"]:
                        relations.append({
                            "subject": subject,
                            "predicate": f"{token.lemma_}_{prep['prep']}",
                            "object": prep["object"],
                            "tense": get_tense(token),
                            "negated": is_negated(token),
                            "pattern": "copula_location"
                        })
    
    return relations


def extract_action_with_location(doc: Doc) -> List[Dict]:
    """
    Extract action verbs with location prepositional phrases.
    
    Examples:
        - "I live in Austin"
        - "She works at Google"
        - "They study at MIT"
    """
    relations = []
    
    for token in doc:
        if token.dep_ == "ROOT" and token.pos_ == "VERB":
            subject = None
            
            # Find subject
            for child in token.children:
                if child.dep_ in ["nsubj", "nsubjpass"]:
                    subject = " ".join([t.text for t in get_subject_tokens(child)])
            
            # Find prepositional phrases
            prep_phrases = get_prepositional_objects(token)
            
            if subject and prep_phrases:
                for prep in prep_phrases:
                    # Location prepositions
                    if prep["prep"] in ["in", "at", "from"]:
                        relations.append({
                            "subject": subject,
                            "predicate": f"{token.lemma_}_{prep['prep']}",
                            "object": prep["object"],
                            "tense": get_tense(token),
                            "negated": is_negated(token),
                            "pattern": "action_location"
                        })
    
    return relations


def extract_relative_clauses(doc: Doc) -> List[Dict]:
    """
    Extract relations from relative clauses.
    
    Examples:
        - "My friend Tom, who works at Google, ..."
        - "The car that Sarah owns is red"
    """
    relations = []
    
    for token in doc:
        # Look for relative clause markers
        if token.dep_ == "relcl":
            # The token is the verb in the relative clause
            subject = token.head.text  # The noun being modified
            
            # Find the object/complement in the relative clause
            obj = None
            for child in token.children:
                if child.dep_ in ["dobj", "attr"]:
                    obj = " ".join([t.text for t in get_object_tokens(child)])
            
            # Check for prepositional phrases
            prep_phrases = get_prepositional_objects(token)
            
            if obj:
                relations.append({
                    "subject": subject,
                    "predicate": token.lemma_,
                    "object": obj,
                    "tense": get_tense(token),
                    "negated": is_negated(token),
                    "pattern": "relative_clause"
                })
            
            for prep in prep_phrases:
                if prep["prep"] in ["at", "in", "for"]:
                    relations.append({
                        "subject": subject,
                        "predicate": f"{token.lemma_}_{prep['prep']}",
                        "object": prep["object"],
                        "tense": get_tense(token),
                        "negated": is_negated(token),
                        "pattern": "relative_clause_location"
                    })
    
    return relations


def extract_compound_subjects(doc: Doc) -> List[Dict]:
    """
    Extract relations with compound subjects.
    
    Examples:
        - "John and Sarah are friends"
        - "My wife and I live in Austin"
    """
    relations = []
    
    for token in doc:
        if token.dep_ == "ROOT":
            subjects = []
            obj = None
            
            # Find all subjects (including compounds)
            for child in token.children:
                if child.dep_ in ["nsubj", "nsubjpass"]:
                    subjects.append(child.text)
                    
                    # Check for coordinated subjects
                    for subchild in child.children:
                        if subchild.dep_ == "conj":
                            subjects.append(subchild.text)
                
                elif child.dep_ in ["dobj", "attr"]:
                    obj = " ".join([t.text for t in get_object_tokens(child)])
            
            # Create relation for compound subjects
            if len(subjects) > 1 and obj:
                relations.append({
                    "subject": " + ".join(subjects),
                    "predicate": token.lemma_,
                    "object": obj,
                    "tense": get_tense(token),
                    "negated": is_negated(token),
                    "pattern": "compound_subject"
                })
    
    return relations


# ============================================================================
# PATTERN REGISTRY
# ============================================================================

GRAMMAR_PATTERNS = [
    GrammarPattern(
        name="possessive",
        description="Extract possessive relations (X's Y)",
        pattern_fn=extract_possessive,
        priority=10,
        examples=["Sarah's car", "my brother's house"]
    ),
    GrammarPattern(
        name="copula_relations",
        description="Extract relations using 'be' verbs",
        pattern_fn=extract_copula_relations,
        priority=9,
        examples=["Mike is my brother", "I am from Austin"]
    ),
    GrammarPattern(
        name="action_location",
        description="Extract actions with location",
        pattern_fn=extract_action_with_location,
        priority=8,
        examples=["I live in Austin", "She works at Google"]
    ),
    GrammarPattern(
        name="relative_clauses",
        description="Extract relations from relative clauses",
        pattern_fn=extract_relative_clauses,
        priority=7,
        examples=["My friend who works at Google"]
    ),
    GrammarPattern(
        name="compound_subjects",
        description="Extract relations with compound subjects",
        pattern_fn=extract_compound_subjects,
        priority=6,
        examples=["John and Sarah are friends"]
    ),
    GrammarPattern(
        name="simple_svo",
        description="Extract simple S-V-O patterns",
        pattern_fn=extract_simple_svo,
        priority=5,
        examples=["John loves pizza", "Sarah owns a car"]
    ),
]
