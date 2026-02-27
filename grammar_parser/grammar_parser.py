"""
Grammar-Based Relation Parser

Main parsing engine that combines spaCy dependency parsing with pattern-based
relation extraction.
"""

import spacy
from typing import List, Dict, Optional
from spacy.tokens import Doc

from relation_types import (
    Relation,
    RelationType,
    classify_relation_by_verb,
    get_subtype_from_object,
    FAMILY_SUBTYPES,
    ROMANTIC_SUBTYPES,
)
from grammar_patterns import GRAMMAR_PATTERNS
from anaphora_resolver import AnaphoraResolver


class GrammarParser:
    """Main parser for extracting relations from text."""
    
    def __init__(self, spacy_model: str = "en_core_web_sm"):
        """
        Initialize parser with spaCy model.
        
        Args:
            spacy_model: Name of spaCy model to load
        """
        try:
            self.nlp = spacy.load(spacy_model)
        except OSError:
            print(f"spaCy model '{spacy_model}' not found. Download with:")
            print(f"  python -m spacy download {spacy_model}")
            raise
        
        # Sort patterns by priority (highest first)
        self.patterns = sorted(GRAMMAR_PATTERNS, key=lambda p: p.priority, reverse=True)
    
    def parse_sentence(self, text: str, context: Optional[Dict] = None) -> List[Relation]:
        """
        Parse a sentence and extract relations.
        
        Args:
            text: Input sentence or text
            context: Optional context (speaker info, conversation history, etc.)
        
        Returns:
            List of Relation objects
        """
        # Parse with spaCy
        doc = self.nlp(text)
        
        # Extract raw relations using all patterns
        raw_relations = []
        for pattern in self.patterns:
            try:
                extracted = pattern.pattern_fn(doc)
                raw_relations.extend(extracted)
            except Exception as e:
                print(f"Warning: Pattern '{pattern.name}' failed: {e}")
                continue
        
        # Convert raw relations to Relation objects
        relations = []
        for raw in raw_relations:
            relation = self._build_relation(raw, text, context)
            if relation:
                relations.append(relation)
        
        # Deduplicate (keep highest confidence)
        relations = self._deduplicate_relations(relations)
        
        return relations
    
    def _build_relation(
        self, 
        raw: Dict, 
        source_text: str,
        context: Optional[Dict] = None
    ) -> Optional[Relation]:
        """
        Build a Relation object from raw extracted data.
        
        Args:
            raw: Raw relation dict from pattern extraction
            source_text: Original sentence text
            context: Optional context
        
        Returns:
            Relation object or None if invalid
        """
        subject = raw.get("subject")
        predicate = raw.get("predicate")
        obj = raw.get("object")
        
        if not subject or not predicate:
            return None
        
        # Classify relation type
        relation_type = classify_relation_by_verb(
            predicate,
            context={"object": obj} if obj else None
        )
        
        # Determine subtype
        subtype = None
        is_symmetric = False
        
        if obj:
            subtype = get_subtype_from_object(obj, relation_type)
            
            # Check if relation is symmetric
            if relation_type == RelationType.FAMILY and subtype:
                subtype_data = FAMILY_SUBTYPES.get(subtype)
                if subtype_data:
                    is_symmetric = subtype_data.is_symmetric
            
            elif relation_type == RelationType.ROMANTIC and subtype:
                subtype_data = ROMANTIC_SUBTYPES.get(subtype)
                if subtype_data:
                    is_symmetric = subtype_data.is_symmetric
        
        # Build confidence score
        confidence = self._calculate_confidence(raw, relation_type)
        
        return Relation(
            subject=subject,
            predicate=predicate,
            object=obj,
            relation_type=relation_type,
            subtype=subtype,
            tense=raw.get("tense"),
            negated=raw.get("negated", False),
            confidence=confidence,
            source_text=source_text,
            is_symmetric=is_symmetric,
        )
    
    def _calculate_confidence(self, raw: Dict, relation_type: RelationType) -> float:
        """
        Calculate confidence score for a relation.
        
        Higher confidence for:
        - Well-defined patterns (possessive, copula)
        - Specific relation types (not OTHER)
        - Complete information (subject, predicate, object)
        
        Args:
            raw: Raw relation dict
            relation_type: Classified relation type
        
        Returns:
            Confidence score 0-1
        """
        confidence = 0.7  # Base confidence
        
        # Boost for specific patterns
        pattern = raw.get("pattern", "")
        if pattern in ["possessive", "copula_relation"]:
            confidence += 0.2
        elif pattern in ["simple_svo", "action_location"]:
            confidence += 0.1
        
        # Boost for classified types
        if relation_type != RelationType.OTHER:
            confidence += 0.1
        
        # Penalty for missing object
        if not raw.get("object"):
            confidence -= 0.1
        
        return min(1.0, max(0.0, confidence))
    
    def _deduplicate_relations(self, relations: List[Relation]) -> List[Relation]:
        """
        Remove duplicate relations, keeping the highest confidence version.
        
        Args:
            relations: List of relations (may have duplicates)
        
        Returns:
            Deduplicated list
        """
        seen = {}
        
        for rel in relations:
            key = (rel.subject, rel.predicate, rel.object)
            
            if key not in seen or seen[key].confidence < rel.confidence:
                seen[key] = rel
        
        return list(seen.values())
    
    def parse_multi_sentence(self, text: str, context: Optional[Dict] = None) -> List[Relation]:
        """
        Parse multiple sentences, handling anaphora and context.
        
        Args:
            text: Multi-sentence text
            context: Optional context
        
        Returns:
            List of all extracted relations
        """
        doc = self.nlp(text)
        all_relations = []
        
        # Initialize anaphora resolver
        resolver = AnaphoraResolver(nlp=self.nlp)
        
        # First pass: extract entities from all sentences
        for sent_idx, sent in enumerate(doc.sents):
            resolver.current_sentence_index = sent_idx
            resolver.extract_entities_from_doc(sent)
        
        # Second pass: parse each sentence with anaphora resolution
        resolver.current_sentence_index = 0
        for sent in doc.sents:
            # Parse the sentence
            relations = self.parse_sentence(sent.text, context)
            
            # Resolve pronouns in extracted relations
            for relation in relations:
                # Resolve subject if it's a pronoun
                if relation.subject and relation.subject.lower() in (
                    resolver.MALE_PRONOUNS | resolver.FEMALE_PRONOUNS | 
                    resolver.NEUTRAL_PRONOUNS | resolver.PLURAL_PRONOUNS
                ):
                    resolved = resolver.resolve(relation.subject.lower())
                    if resolved:
                        relation.subject = resolved
                
                # Resolve object if it's a pronoun
                if relation.object and relation.object.lower() in (
                    resolver.MALE_PRONOUNS | resolver.FEMALE_PRONOUNS | 
                    resolver.NEUTRAL_PRONOUNS | resolver.PLURAL_PRONOUNS
                ):
                    resolved = resolver.resolve(relation.object.lower())
                    if resolved:
                        relation.object = resolved
            
            all_relations.extend(relations)
            resolver.next_sentence()
        
        return all_relations


def parse_sentence(text: str, context: Optional[Dict] = None) -> List[Relation]:
    """
    Convenience function to parse a sentence without managing parser instance.
    
    Args:
        text: Input sentence
        context: Optional context
    
    Returns:
        List of Relation objects
    """
    parser = GrammarParser()
    return parser.parse_sentence(text, context)


def parse_and_print(text: str, context: Optional[Dict] = None):
    """
    Parse and print relations in readable format (for debugging).
    
    Args:
        text: Input text
        context: Optional context
    """
    relations = parse_sentence(text, context)
    
    print(f"\nInput: {text}")
    print(f"Found {len(relations)} relation(s):\n")
    
    for i, rel in enumerate(relations, 1):
        print(f"{i}. {rel.subject} --[{rel.predicate}]--> {rel.object}")
        print(f"   Type: {rel.relation_type.value}" + 
              (f" ({rel.subtype})" if rel.subtype else ""))
        print(f"   Confidence: {rel.confidence:.2f}")
        if rel.tense:
            print(f"   Tense: {rel.tense}")
        if rel.negated:
            print(f"   Negated: True")
        print()


# ============================================================================
# BATCH PROCESSING
# ============================================================================

def parse_conversation(
    messages: List[Dict],
    speaker_names: Optional[Dict[str, str]] = None
) -> List[Relation]:
    """
    Parse an entire conversation and extract all relations.
    
    Args:
        messages: List of message dicts with 'speaker' and 'text' keys
        speaker_names: Optional mapping of speaker IDs to names
    
    Returns:
        List of all extracted relations
    """
    parser = GrammarParser()
    all_relations = []
    
    context = {
        "speaker_names": speaker_names or {},
        "conversation_history": []
    }
    
    for msg in messages:
        speaker = msg.get("speaker", "unknown")
        text = msg.get("text", "")
        
        if not text.strip():
            continue
        
        # Update context with current speaker
        context["current_speaker"] = speaker
        
        # Parse message
        relations = parser.parse_sentence(text, context)
        
        # Resolve [speaker] to actual speaker name
        for rel in relations:
            if rel.subject == "[speaker]":
                rel.subject = speaker_names.get(speaker, speaker)
            if rel.object == "[speaker]":
                rel.object = speaker_names.get(speaker, speaker)
        
        all_relations.extend(relations)
        
        # Add to conversation history
        context["conversation_history"].append({
            "speaker": speaker,
            "text": text
        })
    
    return all_relations


if __name__ == "__main__":
    # Quick test
    test_sentences = [
        "John loves pizza",
        "That's Sarah's car",
        "I live in Austin",
        "Mike is my brother",
        "She works at Google",
        "My friend Tom, who works at Apple, just got promoted",
    ]
    
    print("=" * 60)
    print("Grammar Parser Test")
    print("=" * 60)
    
    for sentence in test_sentences:
        parse_and_print(sentence)
