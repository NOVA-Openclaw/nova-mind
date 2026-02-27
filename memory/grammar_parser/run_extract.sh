#!/bin/bash
# Wrapper script to run extract_cli.py with the virtualenv

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtualenv
source venv/bin/activate

# Run extract CLI
python extract_cli.py "$@"
