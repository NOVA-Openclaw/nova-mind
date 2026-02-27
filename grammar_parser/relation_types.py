"""
Relation Type Taxonomy for Memory Extraction

Defines all relation types that can be extracted from natural language,
with classification rules and database mappings.
"""

from enum import Enum
from typing import Dict, List, Optional
from dataclasses import dataclass


class RelationType(Enum):
    """Primary relation type categories."""
    
    # Interpersonal Relations
    FAMILY = "family"                    # brother, sister, parent, child, etc.
    ROMANTIC = "romantic"                # dating, married, engaged, partner
    SOCIAL = "social"                    # friend, colleague, acquaintance
    PROFESSIONAL = "professional"        # mentor, boss, employee, coworker
    
    # Possession & Ownership
    POSSESSION = "possession"            # owns, has, belongs to
    
    # Preferences & Opinions
    PREFERENCE = "preference"            # likes, loves, hates, prefers
    OPINION = "opinion"                  # thinks, believes, agrees
    
    # Location & Space
    LOCATION = "location"                # lives in, located at, from
    RESIDENCE = "residence"              # lives, stays, resides
    ORIGIN = "origin"                    # from, born in, native to
    
    # Employment & Education
    EMPLOYMENT = "employment"            # works at, employed by, job
    EDUCATION = "education"              # studies at, graduated from, degree
    
    # Attributes & Properties
    ATTRIBUTE = "attribute"              # is tall, has blue eyes, aged 30
    CHARACTERISTIC = "characteristic"    # is kind, seems smart
    
    # Events & Actions
    EVENT = "event"                      # met, visited, attended
    ACTION = "action"                    # did, created, built, said
    
    # Temporal
    TEMPORAL = "temporal"                # since, until, during, in [date]
    
    # Knowledge & Information
    KNOWLEDGE = "knowledge"              # knows, aware of, familiar with
    
    # Misc
    OTHER = "other"                      # catch-all for unclassified


@dataclass
class RelationSubtype:
    """Specific subtypes within relation categories."""
    
    parent_type: RelationType
    name: str
    verb_patterns: List[str]
    is_symmetric: bool = False
    inverse_relation: Optional[str] = None
    description: str = ""


# Family Relations
FAMILY_SUBTYPES = {
    "sibling": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="sibling",
        verb_patterns=["brother", "sister", "sibling"],
        is_symmetric=True,
        description="Sibling relationship"
    ),
    "parent": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="parent",
        verb_patterns=["mother", "father", "mom", "dad", "parent"],
        inverse_relation="child",
        description="Parent-child relationship"
    ),
    "child": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="child",
        verb_patterns=["son", "daughter", "child", "kid"],
        inverse_relation="parent",
        description="Child-parent relationship"
    ),
    "spouse": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="spouse",
        verb_patterns=["husband", "wife", "spouse"],
        is_symmetric=True,
        description="Married partners"
    ),
    "grandparent": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="grandparent",
        verb_patterns=["grandmother", "grandfather", "grandma", "grandpa", "grandparent"],
        inverse_relation="grandchild",
        description="Grandparent relationship"
    ),
    "extended": RelationSubtype(
        parent_type=RelationType.FAMILY,
        name="extended_family",
        verb_patterns=["uncle", "aunt", "cousin", "nephew", "niece"],
        description="Extended family members"
    ),
}


# Romantic Relations
ROMANTIC_SUBTYPES = {
    "dating": RelationSubtype(
        parent_type=RelationType.ROMANTIC,
        name="dating",
        verb_patterns=["dating", "seeing", "going out with"],
        is_symmetric=True,
        description="Dating relationship"
    ),
    "engaged": RelationSubtype(
        parent_type=RelationType.ROMANTIC,
        name="engaged",
        verb_patterns=["engaged to", "fiancé", "fiancée"],
        is_symmetric=True,
        description="Engaged to be married"
    ),
    "married": RelationSubtype(
        parent_type=RelationType.ROMANTIC,
        name="married",
        verb_patterns=["married to", "married"],
        is_symmetric=True,
        description="Married partners"
    ),
    "partner": RelationSubtype(
        parent_type=RelationType.ROMANTIC,
        name="partner",
        verb_patterns=["partner", "significant other", "boyfriend", "girlfriend"],
        is_symmetric=True,
        description="Romantic partner"
    ),
}


# Preference Verbs
PREFERENCE_VERBS = {
    "positive": ["like", "love", "enjoy", "prefer", "adore", "appreciate", "fancy"],
    "negative": ["hate", "dislike", "despise", "can't stand", "loathe"],
    "neutral": ["think about", "consider"],
}


# Location/Residence Verbs
LOCATION_VERBS = {
    "residence": ["live", "stay", "reside", "dwell", "inhabit"],
    "work": ["work", "based"],
    "origin": ["from", "born in", "native to", "grew up in"],
    "temporary": ["visiting", "staying", "traveling to"],
}


# Employment/Education Verbs
EMPLOYMENT_VERBS = ["work", "employed", "job", "position", "role", "works at"]
EDUCATION_VERBS = ["study", "studies", "student", "graduated", "degree", "attended", "enrolled"]


# Possession Verbs
POSSESSION_VERBS = ["have", "has", "had", "own", "owns", "owned", "possess", "possesses"]


# State/Copula Patterns (for attributes)
STATE_VERBS = ["is", "are", "was", "were", "be", "been", "being", "am"]


@dataclass
class Relation:
    """Structured relation extracted from text."""
    
    subject: str                          # Entity or pronoun
    predicate: str                        # Verb or relation type
    object: Optional[str] = None         # Target entity or value
    relation_type: RelationType = RelationType.OTHER
    subtype: Optional[str] = None        # Specific subtype name
    
    # Additional context
    modifiers: List[str] = None          # Adjectives, adverbs
    prepositions: List[Dict] = None      # [{prep: "in", object: "Austin"}]
    temporal: Optional[str] = None       # Time reference
    tense: Optional[str] = None          # past, present, future
    negated: bool = False                # Is this negated?
    
    # Metadata
    confidence: float = 1.0              # 0-1, certainty of extraction
    source_text: str = ""                # Original sentence
    is_symmetric: bool = False           # Should create inverse relation?
    
    def __post_init__(self):
        if self.modifiers is None:
            self.modifiers = []
        if self.prepositions is None:
            self.prepositions = []
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "subject": self.subject,
            "predicate": self.predicate,
            "object": self.object,
            "relation_type": self.relation_type.value,
            "subtype": self.subtype,
            "modifiers": self.modifiers,
            "prepositions": self.prepositions,
            "temporal": self.temporal,
            "tense": self.tense,
            "negated": self.negated,
            "confidence": self.confidence,
            "source_text": self.source_text,
            "is_symmetric": self.is_symmetric,
        }


def classify_relation_by_verb(verb: str, context: Dict = None) -> RelationType:
    """
    Classify relation type based on the verb.
    
    Args:
        verb: The main verb
        context: Additional context (object, modifiers, etc.)
    
    Returns:
        RelationType enum value
    """
    verb_lower = verb.lower().strip()
    
    # Preference verbs
    for sentiment, verbs in PREFERENCE_VERBS.items():
        if verb_lower in verbs:
            return RelationType.PREFERENCE
    
    # Location/Residence
    for loc_type, verbs in LOCATION_VERBS.items():
        if verb_lower in verbs:
            if loc_type == "residence":
                return RelationType.RESIDENCE
            elif loc_type == "origin":
                return RelationType.ORIGIN
            else:
                return RelationType.LOCATION
    
    # Employment/Education
    if verb_lower in [v.lower() for v in EMPLOYMENT_VERBS]:
        return RelationType.EMPLOYMENT
    if verb_lower in [v.lower() for v in EDUCATION_VERBS]:
        return RelationType.EDUCATION
    
    # Possession
    if verb_lower in POSSESSION_VERBS:
        return RelationType.POSSESSION
    
    # State verbs with context
    if verb_lower in STATE_VERBS and context:
        obj = context.get("object", "").lower()
        
        # Check for family relations
        for subtype_data in FAMILY_SUBTYPES.values():
            if obj in subtype_data.verb_patterns:
                return RelationType.FAMILY
        
        # Check for romantic relations
        for subtype_data in ROMANTIC_SUBTYPES.values():
            if obj in [p.lower() for p in subtype_data.verb_patterns]:
                return RelationType.ROMANTIC
        
        # Otherwise likely an attribute
        return RelationType.ATTRIBUTE
    
    # Default
    return RelationType.OTHER


def get_subtype_from_object(obj: str, relation_type: RelationType) -> Optional[str]:
    """
    Determine the specific subtype based on the object and relation type.
    
    Args:
        obj: The object/complement of the relation
        relation_type: The classified relation type
    
    Returns:
        Subtype name or None
    """
    obj_lower = obj.lower().strip()
    
    if relation_type == RelationType.FAMILY:
        for subtype_name, subtype_data in FAMILY_SUBTYPES.items():
            if obj_lower in subtype_data.verb_patterns:
                return subtype_name
    
    elif relation_type == RelationType.ROMANTIC:
        for subtype_name, subtype_data in ROMANTIC_SUBTYPES.items():
            if any(obj_lower in p.lower() for p in subtype_data.verb_patterns):
                return subtype_name
    
    return None
