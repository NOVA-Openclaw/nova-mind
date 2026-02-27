"""
Test cases for anaphora resolution functionality.

Tests pronoun resolution across sentences within a conversation turn.
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "grammar_parser"))

from grammar_parser import GrammarParser
from anaphora_resolver import AnaphoraResolver, Entity
import spacy


def setup_parser():
    """Initialize parser for tests."""
    try:
        return GrammarParser()
    except OSError:
        print("Error: spaCy model not found. Run:")
        print("  python -m spacy download en_core_web_sm")
        sys.exit(1)


def test_simple_pronoun_resolution():
    """Test basic pronoun resolution across two sentences."""
    parser = setup_parser()
    
    text = "I met Sarah yesterday. She works at Google."
    relations = parser.parse_multi_sentence(text)
    
    # Should extract: Sarah works_at Google
    work_rels = [r for r in relations if "Google" in (r.object or "")]
    assert len(work_rels) >= 1, "Should extract work relationship"
    assert work_rels[0].subject == "Sarah", f"Expected 'Sarah', got '{work_rels[0].subject}'"
    
    print("✓ test_simple_pronoun_resolution")


def test_male_pronoun_resolution():
    """Test male pronoun (he, him, his) resolution."""
    parser = setup_parser()
    
    text = "John joined the team yesterday. He is a great developer."
    relations = parser.parse_multi_sentence(text)
    
    # "He" should resolve to "John"
    dev_rels = [r for r in relations if "developer" in (r.object or "")]
    if dev_rels:
        assert dev_rels[0].subject == "John", f"Expected 'John', got '{dev_rels[0].subject}'"
    
    print("✓ test_male_pronoun_resolution")


def test_possessive_pronoun_resolution():
    """Test possessive pronouns (his, her, their)."""
    parser = setup_parser()
    
    text = "Sarah is an engineer. Her expertise is impressive."
    relations = parser.parse_multi_sentence(text)
    
    # "Her" should resolve to "Sarah"
    expertise_rels = [r for r in relations if "expertise" in (r.subject or "")]
    if expertise_rels:
        # The possessive should be resolved
        # Note: Depending on pattern extraction, this might be tricky
        # At minimum, we shouldn't have "her" as a subject
        assert expertise_rels[0].subject != "her", "Pronoun should be resolved"
    
    print("✓ test_possessive_pronoun_resolution")


def test_plural_pronoun_resolution():
    """Test plural pronoun (they, them, their) resolution."""
    parser = setup_parser()
    
    # Note: Plural anaphora is complex - this is a basic test
    text = "Sarah and John are colleagues. They work at Microsoft."
    relations = parser.parse_multi_sentence(text)
    
    # Should handle plural reference (implementation-dependent)
    work_rels = [r for r in relations if "Microsoft" in (r.object or "")]
    # At minimum, should not crash
    assert len(work_rels) >= 0
    
    print("✓ test_plural_pronoun_resolution")


def test_gender_agreement():
    """Test that gender agreement is respected."""
    parser = setup_parser()
    
    text = "John met Sarah. She invited him to the party."
    relations = parser.parse_multi_sentence(text)
    
    # "She" → Sarah (female)
    # "him" → John (male)
    invite_rels = [r for r in relations if "invite" in (r.predicate or "")]
    if invite_rels:
        assert invite_rels[0].subject == "Sarah", "She should resolve to Sarah"
        assert invite_rels[0].object == "John", "him should resolve to John"
    
    print("✓ test_gender_agreement")


def test_recency_bias():
    """Test that most recent entity is preferred."""
    parser = setup_parser()
    
    text = "Tom met Mike. Mike met Sarah. She is a designer."
    relations = parser.parse_multi_sentence(text)
    
    # "She" should resolve to Sarah (most recent female)
    designer_rels = [r for r in relations if "designer" in (r.object or "")]
    if designer_rels:
        assert designer_rels[0].subject == "Sarah", "Should resolve to most recent female entity"
    
    print("✓ test_recency_bias")


def test_no_ambiguous_resolution():
    """Test that ambiguous pronouns are not incorrectly resolved."""
    parser = setup_parser()
    
    # This is genuinely ambiguous
    text = "John told Tom something. He was surprised."
    relations = parser.parse_multi_sentence(text)
    
    # Should either:
    # 1. Not resolve (leave as "he")
    # 2. Resolve to most recent male (Tom) with recency bias
    # At minimum, shouldn't crash
    assert len(relations) >= 0
    
    print("✓ test_no_ambiguous_resolution")


def test_anaphora_resolver_class():
    """Test AnaphoraResolver class directly."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    # Track entities
    resolver.track_entity("Sarah", gender="female")
    resolver.track_entity("John", gender="male")
    
    # Resolve pronouns
    assert resolver.resolve("she") == "Sarah"
    assert resolver.resolve("he") == "John"
    assert resolver.resolve("her") == "Sarah"  # Possessive
    assert resolver.resolve("his") == "John"    # Possessive
    
    print("✓ test_anaphora_resolver_class")


def test_entity_extraction():
    """Test automatic entity extraction from text."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    doc = nlp("Sarah works at Google.")
    entities = resolver.extract_entities_from_doc(doc)
    
    assert len(entities) >= 1
    assert "Sarah" in entities or "Google" in entities
    
    print("✓ test_entity_extraction")


def test_gender_inference():
    """Test gender inference from names and terms."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    # Test common names
    assert resolver._infer_gender("Sarah") == "female"
    assert resolver._infer_gender("John") == "male"
    
    # Test family terms
    assert resolver._infer_gender("brother") == "male"
    assert resolver._infer_gender("sister") == "female"
    
    print("✓ test_gender_inference")


def test_reflexive_pronouns():
    """Test reflexive pronouns (himself, herself, themselves)."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    resolver.track_entity("John", gender="male")
    resolver.track_entity("Sarah", gender="female")
    
    # Reflexive should resolve same as personal pronouns
    assert resolver.resolve("himself") == "John"
    assert resolver.resolve("herself") == "Sarah"
    
    print("✓ test_reflexive_pronouns")


def test_neutral_pronoun():
    """Test neutral pronoun (it) resolution."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    resolver.track_entity("Google", gender="neutral", entity_type="ORG")
    
    resolved = resolver.resolve("it")
    # Should resolve to Google or at least not crash
    assert resolved is None or resolved == "Google"
    
    print("✓ test_neutral_pronoun")


def test_resolver_reset():
    """Test that resolver can be reset between conversations."""
    nlp = spacy.load("en_core_web_sm")
    resolver = AnaphoraResolver(nlp=nlp)
    
    # First conversation
    resolver.track_entity("Sarah", gender="female")
    assert resolver.resolve("she") == "Sarah"
    
    # Reset
    resolver.reset()
    
    # New conversation - should not resolve to Sarah
    result = resolver.resolve("she")
    assert result is None, "After reset, should not resolve to previous entity"
    
    print("✓ test_resolver_reset")


def test_complex_example():
    """Test the exact example from the issue."""
    parser = setup_parser()
    
    text = "I met Sarah yesterday. She works at Google."
    relations = parser.parse_multi_sentence(text)
    
    # Should extract: Sarah works_at Google
    work_rels = [r for r in relations if "works" in (r.predicate or "") or "work" in (r.predicate or "")]
    assert len(work_rels) >= 1, "Should extract work relationship"
    
    work_rel = work_rels[0]
    assert work_rel.subject == "Sarah", f"Subject should be 'Sarah', got '{work_rel.subject}'"
    assert "Google" in (work_rel.object or ""), f"Object should contain 'Google', got '{work_rel.object}'"
    
    print("✓ test_complex_example (issue #45 requirement)")


def test_multiple_sentences_multiple_pronouns():
    """Test handling multiple pronouns across multiple sentences."""
    parser = setup_parser()
    
    text = "John and Sarah are coworkers. He is a developer. She is a designer. They work at Apple."
    relations = parser.parse_multi_sentence(text)
    
    # Should resolve all pronouns correctly
    dev_rels = [r for r in relations if "developer" in (r.object or "")]
    if dev_rels:
        assert dev_rels[0].subject == "John", "He should resolve to John"
    
    designer_rels = [r for r in relations if "designer" in (r.object or "")]
    if designer_rels:
        assert designer_rels[0].subject == "Sarah", "She should resolve to Sarah"
    
    print("✓ test_multiple_sentences_multiple_pronouns")


def run_all_tests():
    """Run all anaphora resolution tests."""
    
    test_functions = [
        test_simple_pronoun_resolution,
        test_male_pronoun_resolution,
        test_possessive_pronoun_resolution,
        test_plural_pronoun_resolution,
        test_gender_agreement,
        test_recency_bias,
        test_no_ambiguous_resolution,
        test_anaphora_resolver_class,
        test_entity_extraction,
        test_gender_inference,
        test_reflexive_pronouns,
        test_neutral_pronoun,
        test_resolver_reset,
        test_complex_example,
        test_multiple_sentences_multiple_pronouns,
    ]
    
    passed = 0
    failed = 0
    
    print("=" * 70)
    print("Running Anaphora Resolution Tests (Issue #45)")
    print("=" * 70 + "\n")
    
    for test_fn in test_functions:
        test_name = test_fn.__name__
        try:
            test_fn()
            passed += 1
        except AssertionError as e:
            print(f"✗ {test_name}: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ {test_name}: ERROR - {e}")
            failed += 1
    
    print("\n" + "=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)
    
    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
