#!/bin/bash
# Wrapper script to run store_relations.py with the virtualenv

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtualenv
source venv/bin/activate

# Run store relations
python store_relations.py "$@"
