# Test Cases for Issue #67: Improve installer API key handling

## TC-67-01: Installer prompts for API key when not set
**Given** OPENAI_API_KEY is not in environment
**When** user runs ./install.sh
**Then** installer prompts user to enter API key
**And** displays explanation that key is required for semantic recall

## TC-67-02: Installer configures OpenClaw with provided key
**Given** user provides valid API key during install
**When** install completes
**Then** ~/.openclaw/openclaw.json contains the API key
**And** key is in correct config path for gateway environment

## TC-67-03: Installer fails without API key
**Given** OPENAI_API_KEY not set and user declines to provide one
**When** user runs ./install.sh
**Then** installer exits with non-zero code
**And** displays clear error about required API key

## TC-67-04: Hook logs error when API key missing at runtime
**Given** semantic-recall hook is enabled
**And** OPENAI_API_KEY is removed from environment
**When** message triggers hook
**Then** gateway log contains "[semantic-recall] ERROR: OPENAI_API_KEY not set"
**And** hook returns gracefully (no crash)

## TC-67-05: proactive-recall.py returns error JSON
**Given** OPENAI_API_KEY not set
**When** proactive-recall.py is executed
**Then** output is valid JSON with error field
**And** memories array is empty
**Example:** {"error": "OPENAI_API_KEY not set", "memories": []}

## TC-67-06: INSTALLATION.md has prerequisites section
**Given** INSTALLATION.md exists
**When** reading the file
**Then** contains "Prerequisites" or "Requirements" section
**And** lists OPENAI_API_KEY as required
**And** explains it's for embeddings/semantic recall