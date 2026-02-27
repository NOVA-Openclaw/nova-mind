"""
Anaphora Resolution for Cross-Sentence Pronoun References

Tracks entity mentions across sentences and resolves pronouns to their antecedents.
"""

from typing import Dict, List, Optional, Set
from dataclasses import dataclass
import spacy
from spacy.tokens import Token


@dataclass
class Entity:
    """Represents a tracked entity with metadata."""
    
    name: str
    gender: Optional[str] = None  # "male", "female", "neutral", "unknown"
    number: str = "singular"      # "singular" or "plural"
    entity_type: Optional[str] = None  # "PERSON", "ORG", "GPE", etc.
    sentence_index: int = 0       # Which sentence it appeared in
    token_position: int = 0       # Position within sentence


class AnaphoraResolver:
    """
    Resolves pronouns to their antecedents within a conversation turn.
    
    Handles:
    - Personal pronouns: he, she, they, it
    - Possessive pronouns: his, her, their, its
    - Reflexive pronouns: himself, herself, themselves, itself
    """
    
    # Pronoun mappings
    MALE_PRONOUNS = {"he", "him", "his", "himself"}
    FEMALE_PRONOUNS = {"she", "her", "hers", "herself"}
    NEUTRAL_PRONOUNS = {"it", "its", "itself"}
    PLURAL_PRONOUNS = {"they", "them", "their", "theirs", "themselves"}
    
    # Possessive pronoun mappings (for resolution)
    POSSESSIVE_MAP = {
        "his": "he",
        "her": "she",
        "hers": "she",
        "its": "it",
        "their": "they",
        "theirs": "they",
    }
    
    # Common male/female name patterns (simplified)
    MALE_NAMES = {"john", "mike", "tom", "david", "james", "robert", "william", "richard", "daniel", "matthew"}
    FEMALE_NAMES = {"sarah", "mary", "lisa", "emily", "jessica", "ashley", "amanda", "jennifer", "michelle", "karen"}
    
    def __init__(self, nlp=None):
        """
        Initialize resolver.
        
        Args:
            nlp: spaCy language model (optional, for NER)
        """
        self.nlp = nlp
        self.entity_stack: List[Entity] = []
        self.resolution_cache: Dict[str, str] = {}
        self.current_sentence_index = 0
    
    def reset(self):
        """Clear all tracked entities and cache."""
        self.entity_stack.clear()
        self.resolution_cache.clear()
        self.current_sentence_index = 0
    
    def track_entity(
        self, 
        name: str, 
        gender: Optional[str] = None,
        number: str = "singular",
        entity_type: Optional[str] = None,
        token_position: int = 0
    ):
        """
        Track a new entity mention.
        
        Args:
            name: Entity name
            gender: Gender classification ("male", "female", "neutral", "unknown")
            number: "singular" or "plural"
            entity_type: NER type (PERSON, ORG, etc.)
            token_position: Position in sentence
        """
        # Infer gender if not provided
        if gender is None:
            gender = self._infer_gender(name)
        
        entity = Entity(
            name=name,
            gender=gender,
            number=number,
            entity_type=entity_type,
            sentence_index=self.current_sentence_index,
            token_position=token_position
        )
        
        self.entity_stack.append(entity)
    
    def _infer_gender(self, name: str) -> str:
        """
        Infer gender from name or context.
        
        Args:
            name: Entity name
        
        Returns:
            Gender classification: "male", "female", "neutral", or "unknown"
        """
        name_lower = name.lower()
        
        # Check common names
        if name_lower in self.MALE_NAMES:
            return "male"
        elif name_lower in self.FEMALE_NAMES:
            return "female"
        
        # Check for gendered family terms
        if any(term in name_lower for term in ["brother", "father", "dad", "uncle", "son", "grandfather", "boyfriend", "husband"]):
            return "male"
        elif any(term in name_lower for term in ["sister", "mother", "mom", "aunt", "daughter", "grandmother", "girlfriend", "wife"]):
            return "female"
        
        return "unknown"
    
    def resolve(self, pronoun: str) -> Optional[str]:
        """
        Resolve a pronoun to its antecedent.
        
        Args:
            pronoun: Pronoun to resolve (he, she, they, it, his, her, their, etc.)
        
        Returns:
            Entity name or None if resolution uncertain
        """
        pronoun_lower = pronoun.lower()
        
        # Check cache first
        if pronoun_lower in self.resolution_cache:
            return self.resolution_cache[pronoun_lower]
        
        # Convert possessive to base form
        if pronoun_lower in self.POSSESSIVE_MAP:
            base_pronoun = self.POSSESSIVE_MAP[pronoun_lower]
        else:
            base_pronoun = pronoun_lower
        
        # Find matching entity
        entity = self._find_matching_entity(base_pronoun)
        
        if entity:
            resolved_name = entity.name
            # Cache the resolution
            self.resolution_cache[pronoun_lower] = resolved_name
            # Also cache related forms
            self._cache_related_forms(base_pronoun, resolved_name)
            return resolved_name
        
        return None
    
    def _find_matching_entity(self, pronoun: str) -> Optional[Entity]:
        """
        Find the most recent entity matching the pronoun.
        
        Uses recency bias: most recent matching entity is preferred.
        Prefers exact gender matches over unknown gender.
        
        Args:
            pronoun: Pronoun to match
        
        Returns:
            Matching Entity or None
        """
        # Determine pronoun characteristics
        if pronoun in self.MALE_PRONOUNS:
            target_gender = "male"
            target_number = "singular"
        elif pronoun in self.FEMALE_PRONOUNS:
            target_gender = "female"
            target_number = "singular"
        elif pronoun in self.NEUTRAL_PRONOUNS:
            target_gender = "neutral"
            target_number = "singular"
        elif pronoun in self.PLURAL_PRONOUNS:
            target_gender = None  # Gender doesn't matter for plural
            target_number = "plural"
        else:
            return None
        
        # First pass: Look for exact gender match (most recent first)
        exact_match = None
        fallback_match = None
        
        for entity in reversed(self.entity_stack):
            # Check number agreement
            if entity.number != target_number:
                continue
            
            # For plural, any plural entity matches
            if target_number == "plural":
                return entity
            
            # For singular, check gender agreement
            if target_gender:
                if entity.gender == target_gender:
                    # Exact match - return immediately
                    return entity
                elif entity.gender == "unknown" and fallback_match is None:
                    # Unknown gender - save as fallback
                    fallback_match = entity
        
        # If no exact match found, use fallback (unknown gender)
        # But only if we're looking for neutral pronouns or there's no other option
        if target_gender == "neutral" and fallback_match:
            return fallback_match
        
        return None
    
    def _cache_related_forms(self, base_pronoun: str, resolved_name: str):
        """
        Cache all related pronoun forms when one is resolved.
        
        Args:
            base_pronoun: Base pronoun form (he, she, they, it)
            resolved_name: Resolved entity name
        """
        related_forms = []
        
        if base_pronoun == "he":
            related_forms = ["he", "him", "his", "himself"]
        elif base_pronoun == "she":
            related_forms = ["she", "her", "hers", "herself"]
        elif base_pronoun == "they":
            related_forms = ["they", "them", "their", "theirs", "themselves"]
        elif base_pronoun == "it":
            related_forms = ["it", "its", "itself"]
        
        for form in related_forms:
            self.resolution_cache[form] = resolved_name
    
    def extract_entities_from_doc(self, doc) -> List[str]:
        """
        Extract entities from a spaCy Doc and track them.
        
        Args:
            doc: spaCy Doc object
        
        Returns:
            List of entity names extracted
        """
        extracted = []
        
        for token in doc:
            # Skip pronouns themselves
            if token.lower_ in (self.MALE_PRONOUNS | self.FEMALE_PRONOUNS | 
                               self.NEUTRAL_PRONOUNS | self.PLURAL_PRONOUNS):
                continue
            
            # Extract proper nouns
            if token.pos_ == "PROPN":
                entity_type = None
                if token.ent_type_:
                    entity_type = token.ent_type_
                
                self.track_entity(
                    name=token.text,
                    entity_type=entity_type,
                    token_position=token.i
                )
                extracted.append(token.text)
            
            # Extract common nouns that are entities (family relations, etc.)
            elif token.pos_ == "NOUN" and token.dep_ in ["attr", "dobj", "pobj"]:
                # Check if it's a relationship term (brother, sister, etc.)
                if token.lower_ in {"brother", "sister", "mother", "father", "friend", 
                                   "son", "daughter", "uncle", "aunt", "cousin",
                                   "boyfriend", "girlfriend", "husband", "wife", "partner"}:
                    # Don't track these as entities, but use them for gender inference
                    pass
        
        return extracted
    
    def resolve_in_text(self, text: str) -> Dict[str, str]:
        """
        Build a resolution map for all pronouns in a piece of text.
        
        Args:
            text: Text containing pronouns to resolve
        
        Returns:
            Dict mapping pronouns to resolved names
        """
        if not self.nlp:
            return {}
        
        doc = self.nlp(text)
        resolution_map = {}
        
        for token in doc:
            if token.lower_ in (self.MALE_PRONOUNS | self.FEMALE_PRONOUNS | 
                               self.NEUTRAL_PRONOUNS | self.PLURAL_PRONOUNS):
                resolved = self.resolve(token.lower_)
                if resolved:
                    resolution_map[token.lower_] = resolved
        
        return resolution_map
    
    def next_sentence(self):
        """Mark the start of a new sentence."""
        self.current_sentence_index += 1


def resolve_pronouns_in_text(text: str, nlp=None) -> Dict[str, str]:
    """
    Convenience function to resolve pronouns in text.
    
    Args:
        text: Multi-sentence text
        nlp: spaCy model (optional, will load if not provided)
    
    Returns:
        Dict mapping pronouns to resolved entity names
    """
    if nlp is None:
        import spacy
        nlp = spacy.load("en_core_web_sm")
    
    resolver = AnaphoraResolver(nlp=nlp)
    doc = nlp(text)
    
    # Process each sentence
    for sent_idx, sent in enumerate(doc.sents):
        resolver.current_sentence_index = sent_idx
        resolver.extract_entities_from_doc(sent)
    
    # Build resolution map
    resolver.current_sentence_index = 0
    resolution_map = {}
    
    for sent in doc.sents:
        sent_map = resolver.resolve_in_text(sent.text)
        resolution_map.update(sent_map)
        resolver.next_sentence()
    
    return resolution_map
