#!/bin/bash
# Setup script for grammar parser

set -e

echo "================================"
echo "Grammar Parser Setup"
echo "================================"
echo ""

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo "Python version: $PYTHON_VERSION"

# Install requirements
echo ""
echo "Installing Python dependencies..."
pip3 install -r requirements.txt

# Download spaCy model
echo ""
echo "Downloading spaCy English model..."
python3 -m spacy download en_core_web_sm

# Make CLI scripts executable
echo ""
echo "Making CLI scripts executable..."
chmod +x extract_cli.py store_relations.py

# Run tests
echo ""
echo "Running tests..."
cd tests
python3 test_patterns.py

echo ""
echo "================================"
echo "Setup complete!"
echo "================================"
echo ""
echo "Try it out:"
echo '  python3 extract_cli.py "John loves pizza"'
echo ""
echo "Or run example tests:"
echo "  python3 tests/test_examples.py"
echo ""
