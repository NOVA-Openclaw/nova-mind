#!/usr/bin/env python3
"""
CLI wrapper for grammar parser.
Takes message text, outputs JSON relations.

Usage:
    extract_cli.py <message_text>
    echo "John loves pizza" | extract_cli.py
"""

import sys
import json
from grammar_parser import parse_sentence


def main():
    # Read from argument or stdin
    if len(sys.argv) > 1:
        message = " ".join(sys.argv[1:])
    else:
        message = sys.stdin.read().strip()
    
    if not message:
        print("Usage: extract_cli.py <message_text>", file=sys.stderr)
        print("   or: echo 'text' | extract_cli.py", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Parse message
        relations = parse_sentence(message)
        
        # Convert to JSON
        output = [rel.to_dict() for rel in relations]
        
        # Output JSON
        print(json.dumps(output, indent=2))
        
    except Exception as e:
        print(f"Error parsing message: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
