#!/bin/bash
#
# Load test data into nova-memory database
#
# Usage:
#   ./load-test-data.sh [DATABASE_NAME]
#
# Default database name is 'test_memory'
# This script will:
#   1. Load the SQL test data (entities, facts, events, lessons, tasks)
#   2. Generate embeddings for searchable facts
#   3. Verify the data was loaded correctly

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get database name from argument or use default
DB_NAME="${1:-test_memory}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Nova Memory - Test Data Loader${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "Database: ${GREEN}${DB_NAME}${NC}"
echo ""

# Check if database exists
echo -e "${YELLOW}➜${NC} Checking database connection..."
if psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${GREEN}✓${NC} Database '$DB_NAME' exists"
else
    echo -e "${RED}✗${NC} Database '$DB_NAME' does not exist"
    echo ""
    read -p "Create database '$DB_NAME'? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        createdb "$DB_NAME"
        echo -e "${GREEN}✓${NC} Created database '$DB_NAME'"
        
        # Apply main schema if available
        if [ -f "$SCRIPT_DIR/../../schema.sql" ]; then
            echo -e "${YELLOW}➜${NC} Applying main schema..."
            psql -d "$DB_NAME" -f "$SCRIPT_DIR/../../schema.sql" > /dev/null 2>&1
            echo -e "${GREEN}✓${NC} Schema applied"
        else
            echo -e "${YELLOW}⚠${NC} Warning: schema.sql not found, database may need schema"
        fi
    else
        echo -e "${RED}✗${NC} Aborted"
        exit 1
    fi
fi

# Step 1: Load SQL test data
echo ""
echo -e "${YELLOW}➜${NC} Loading test data from SQL file..."
if [ ! -f "$SCRIPT_DIR/test-data.sql" ]; then
    echo -e "${RED}✗${NC} Error: test-data.sql not found in $SCRIPT_DIR"
    exit 1
fi

psql -d "$DB_NAME" -f "$SCRIPT_DIR/test-data.sql"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Test data loaded successfully"
else
    echo -e "${RED}✗${NC} Failed to load test data"
    exit 1
fi

# Step 2: Verify basic data
echo ""
echo -e "${YELLOW}➜${NC} Verifying loaded data..."

verify_query() {
    local query="$1"
    local expected="$2"
    local description="$3"
    
    local result=$(psql -d "$DB_NAME" -t -c "$query" | xargs)
    
    if [ "$result" = "$expected" ]; then
        echo -e "${GREEN}✓${NC} $description: $result"
        return 0
    else
        echo -e "${RED}✗${NC} $description: expected $expected, got $result"
        return 1
    fi
}

verify_query "SELECT COUNT(*) FROM entities;" "15" "Entities count"
verify_query "SELECT COUNT(*) FROM entity_facts;" "75" "Entity facts count"
verify_query "SELECT COUNT(*) FROM events;" "15" "Events count"
verify_query "SELECT COUNT(*) FROM lessons;" "8" "Lessons count"
verify_query "SELECT COUNT(*) FROM tasks;" "12" "Tasks count"

# Check visibility distribution
echo ""
echo -e "${YELLOW}➜${NC} Visibility distribution:"
psql -d "$DB_NAME" -c "SELECT visibility, COUNT(*) as count FROM entity_facts GROUP BY visibility ORDER BY count DESC;"

# Step 3: Generate embeddings
echo ""
echo -e "${YELLOW}➜${NC} Generating embeddings..."

# Check if Python script is available
if [ ! -f "$SCRIPT_DIR/generate-test-embeddings.py" ]; then
    echo -e "${RED}✗${NC} Error: generate-test-embeddings.py not found"
    exit 1
fi

# Check if OpenAI API key is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}⚠${NC} Warning: OPENAI_API_KEY not set"
    echo ""
    echo "Embeddings require an OpenAI API key. You can:"
    echo "  1. Set OPENAI_API_KEY environment variable"
    echo "  2. Run embeddings generation manually later:"
    echo "     export OPENAI_API_KEY='your-key'"
    echo "     $SCRIPT_DIR/generate-test-embeddings.py --database $DB_NAME"
    echo ""
    read -p "Continue without generating embeddings? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}✗${NC} Aborted"
        exit 1
    fi
    echo -e "${YELLOW}⚠${NC} Skipping embedding generation"
else
    # Check for Python and required packages
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}✗${NC} Python 3 not found"
        exit 1
    fi
    
    # Try to generate embeddings
    python3 "$SCRIPT_DIR/generate-test-embeddings.py" --database "$DB_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Embeddings generated successfully"
        
        # Verify embeddings
        echo ""
        echo -e "${YELLOW}➜${NC} Verifying embeddings..."
        local embedding_count=$(psql -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM memory_embeddings WHERE source_type='entity_fact';" | xargs)
        echo -e "${GREEN}✓${NC} Memory embeddings count: $embedding_count"
        
        # Should be 70 (75 total facts - 5 sensitive facts)
        local expected_embeddings=70
        if [ "$embedding_count" = "$expected_embeddings" ]; then
            echo -e "${GREEN}✓${NC} Embedding count matches expected (excluding sensitive facts)"
        else
            echo -e "${YELLOW}⚠${NC} Expected $expected_embeddings embeddings, got $embedding_count"
            echo -e "   ${YELLOW}(Should be: 75 total facts - 5 sensitive facts = 70 embeddings)${NC}"
        fi
    else
        echo -e "${RED}✗${NC} Failed to generate embeddings"
        echo -e "${YELLOW}⚠${NC} You can generate them manually later with:"
        echo "     $SCRIPT_DIR/generate-test-embeddings.py --database $DB_NAME"
    fi
fi

# Final summary
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}✓ Test data loaded successfully!${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "Database: ${GREEN}${DB_NAME}${NC}"
echo ""
echo "Next steps:"
echo "  1. Review test queries: $SCRIPT_DIR/test-queries.md"
echo "  2. Test semantic search queries"
echo "  3. Verify privacy filtering works correctly"
echo ""
echo "Example queries:"
echo "  psql -d $DB_NAME -c \"SELECT name, type FROM entities;\""
echo "  psql -d $DB_NAME -c \"SELECT key, visibility, COUNT(*) FROM entity_facts GROUP BY key, visibility LIMIT 10;\""
echo ""
