"""
Test examples from the task specification.

These are the exact examples provided by I)ruid.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from grammar_parser import parse_and_print


def run_spec_examples():
    """Run all examples from the task specification."""
    
    print("=" * 70)
    print("Task Specification Examples")
    print("=" * 70)
    
    examples = [
        "John loves pizza",
        "That's Sarah's car",
        "I live in Austin",
        "Mike is my brother",
        "We met in 2019",
        "My friend Tom, who works at Google, just got promoted",
    ]
    
    for example in examples:
        parse_and_print(example)
    
    print("\n" + "=" * 70)
    print("Additional Test Cases")
    print("=" * 70)
    
    additional = [
        "Sarah hates coffee",
        "Tom is my father",
        "She studies at MIT",
        "That's John's house",
        "They work at Microsoft",
        "I am from Texas",
        "Mike and Sarah are dating",
        "John doesn't like vegetables",
        "My sister Emma is a doctor",
        "We live in San Francisco",
    ]
    
    for example in additional:
        parse_and_print(example)


if __name__ == "__main__":
    run_spec_examples()
