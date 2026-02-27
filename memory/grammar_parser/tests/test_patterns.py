"""
Test cases for grammar pattern extraction.

Tests cover all major sentence patterns and relation types.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from grammar_parser import parse_sentence
from relation_types import RelationType


def test_simple_svo():
    """Test simple Subject-Verb-Object patterns."""
    
    # Preference
    relations = parse_sentence("John loves pizza")
    assert len(relations) == 1
    assert relations[0].subject == "John"
    assert relations[0].predicate == "love"
    assert relations[0].object == "pizza"
    assert relations[0].relation_type == RelationType.PREFERENCE
    
    # Possession
    relations = parse_sentence("Sarah owns a car")
    assert len(relations) >= 1
    assert any(r.predicate == "own" for r in relations)
    assert any(r.relation_type == RelationType.POSSESSION for r in relations)


def test_possessive_patterns():
    """Test possessive relation extraction."""
    
    relations = parse_sentence("That's Sarah's car")
    assert len(relations) >= 1
    
    # Should extract ownership
    ownership = [r for r in relations if r.predicate == "owns"]
    assert len(ownership) >= 1
    assert ownership[0].subject == "Sarah"
    assert "car" in ownership[0].object


def test_location_residence():
    """Test location and residence patterns."""
    
    # Residence
    relations = parse_sentence("I live in Austin")
    assert len(relations) >= 1
    loc_rels = [r for r in relations if "Austin" in (r.object or "")]
    assert len(loc_rels) >= 1
    assert loc_rels[0].relation_type in [RelationType.RESIDENCE, RelationType.LOCATION]
    
    # Work location
    relations = parse_sentence("She works at Google")
    assert len(relations) >= 1
    work_rels = [r for r in relations if "Google" in (r.object or "")]
    assert len(work_rels) >= 1


def test_family_relations():
    """Test family relation extraction."""
    
    relations = parse_sentence("Mike is my brother")
    assert len(relations) >= 1
    
    family_rels = [r for r in relations if r.relation_type == RelationType.FAMILY]
    assert len(family_rels) >= 1
    assert family_rels[0].subtype == "sibling"
    assert family_rels[0].is_symmetric


def test_employment():
    """Test employment relation extraction."""
    
    relations = parse_sentence("Tom works at Apple")
    assert len(relations) >= 1
    
    work_rels = [r for r in relations if "Apple" in (r.object or "")]
    assert len(work_rels) >= 1


def test_copula_patterns():
    """Test copula (be verb) patterns."""
    
    # Attribute
    relations = parse_sentence("Sarah is tall")
    assert len(relations) >= 1
    assert relations[0].predicate == "be"
    assert relations[0].object == "tall"
    
    # Profession
    relations = parse_sentence("He is a doctor")
    assert len(relations) >= 1


def test_negation():
    """Test negated relations."""
    
    relations = parse_sentence("John doesn't like pizza")
    assert len(relations) >= 1
    
    pref_rels = [r for r in relations if r.relation_type == RelationType.PREFERENCE]
    if pref_rels:
        assert pref_rels[0].negated == True


def test_relative_clauses():
    """Test relative clause extraction."""
    
    relations = parse_sentence("My friend Tom, who works at Google, is visiting")
    assert len(relations) >= 1
    
    # Should extract work relationship
    work_rels = [r for r in relations if "Google" in (r.object or "")]
    assert len(work_rels) >= 1


def test_compound_subjects():
    """Test compound subject patterns."""
    
    relations = parse_sentence("John and Sarah are friends")
    assert len(relations) >= 1


def test_tense_detection():
    """Test verb tense detection."""
    
    # Past
    relations = parse_sentence("John loved pizza")
    assert any(r.tense == "past" for r in relations)
    
    # Present
    relations = parse_sentence("John loves pizza")
    assert any(r.tense == "present" for r in relations)


def test_multiple_relations():
    """Test extracting multiple relations from complex sentences."""
    
    relations = parse_sentence("My friend Tom works at Google in California")
    assert len(relations) >= 1
    
    # Should have at least friendship and employment
    work_rels = [r for r in relations if "Google" in (r.object or "")]
    assert len(work_rels) >= 1


def run_all_tests():
    """Run all tests and report results."""
    
    test_functions = [
        test_simple_svo,
        test_possessive_patterns,
        test_location_residence,
        test_family_relations,
        test_employment,
        test_copula_patterns,
        test_negation,
        test_relative_clauses,
        test_compound_subjects,
        test_tense_detection,
        test_multiple_relations,
    ]
    
    passed = 0
    failed = 0
    
    print("=" * 60)
    print("Running Grammar Parser Tests")
    print("=" * 60 + "\n")
    
    for test_fn in test_functions:
        test_name = test_fn.__name__
        try:
            test_fn()
            print(f"✓ {test_name}")
            passed += 1
        except AssertionError as e:
            print(f"✗ {test_name}: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ {test_name}: ERROR - {e}")
            failed += 1
    
    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)
    
    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
