# Test Cases for nova-memory#78

## Goal

The `agent-install.sh` script should install scripts to both:
1. `$WORKSPACE/scripts/` (e.g., `~/.openclaw/workspace-*/scripts/`)
2. `~/.openclaw/scripts/` (where semantic-recall handler expects them)

Currently, scripts are only installed to location #1, which causes the semantic-recall handler to fail when it tries to find `proactive-recall.py` at `~/.openclaw/scripts/proactive-recall.py`.

## Test Cases

**Test Case 1: Fresh installation**

*   **Setup:**
    *   Delete both target directories if they exist:
        *   `~/.openclaw/workspace-*/scripts/`
        *   `~/.openclaw/scripts/`
*   **Action:**
    *   Run `agent-install.sh`
*   **Expected Result:**
    *   Scripts should be installed to both locations
    *   Both directories should contain the same files with identical hashes
    *   Output should indicate scripts were installed to both locations

**Test Case 2: Update when workspace scripts exist but OpenClaw scripts don't**

*   **Setup:**
    *   Install scripts using old installer (creates only workspace scripts)
    *   Verify `~/.openclaw/workspace-*/scripts/` exists
    *   Verify `~/.openclaw/scripts/` does not exist
*   **Action:**
    *   Run updated `agent-install.sh`
*   **Expected Result:**
    *   Scripts should be created in `~/.openclaw/scripts/`
    *   Workspace scripts should remain unchanged (already up to date)
    *   Both locations should now have identical files

**Test Case 3: Both locations exist and are up to date**

*   **Setup:**
    *   Run `agent-install.sh` to install scripts to both locations
    *   Verify both locations have identical files
*   **Action:**
    *   Run `agent-install.sh` again
*   **Expected Result:**
    *   Scripts should be skipped (already up to date)
    *   No files should be modified
    *   Output should not show scripts being copied

**Test Case 4: One location differs from source**

*   **Setup:**
    *   Run `agent-install.sh` to install scripts
    *   Modify a script in `~/.openclaw/scripts/` only
    *   Verify hashes differ between source and `~/.openclaw/scripts/`
*   **Action:**
    *   Run `agent-install.sh`
*   **Expected Result:**
    *   Modified script should be overwritten in both locations
    *   Both locations should now match the source
    *   Output should indicate scripts were updated

**Test Case 5: Scripts are executable in both locations**

*   **Setup:**
    *   Install scripts using `agent-install.sh`
*   **Action:**
    *   Check file permissions in both locations
*   **Expected Result:**
    *   All `.sh` and `.py` files should be executable in both:
        *   `~/.openclaw/workspace-*/scripts/`
        *   `~/.openclaw/scripts/`

**Test Case 6: Semantic-recall handler can find scripts**

*   **Setup:**
    *   Install scripts using updated `agent-install.sh`
*   **Action:**
    *   Check that semantic-recall handler's expected path exists:
        ```bash
        ls -la ~/.openclaw/scripts/proactive-recall.py
        ```
*   **Expected Result:**
    *   File should exist at `~/.openclaw/scripts/proactive-recall.py`
    *   File should be executable
    *   Hash should match source file

**Test Case 7: --force flag updates both locations**

*   **Setup:**
    *   Install scripts using `agent-install.sh`
    *   Verify both locations have identical files
*   **Action:**
    *   Run `agent-install.sh --force`
*   **Expected Result:**
    *   Scripts should be reinstalled to both locations
    *   Files should be overwritten even though they match
    *   Both locations should remain identical
