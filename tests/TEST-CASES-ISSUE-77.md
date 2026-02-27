# Test Cases for nova-memory#77

## Goal

The `agent-install.sh` script should reinstall files when the source and target hashes differ. Currently, it skips files when hashes differ, treating them as "local modifications." The correct behavior is to reinstall when hashes differ (the repo is the source of truth).

## Test Cases

**Test Case 1: Source and target hashes match**

*   **Setup:**
    *   Create a source file in the repository.
    *   Install the file using `agent-install.sh`.
    *   Verify that the source and target files have the same hash.
*   **Action:**
    *   Run `agent-install.sh` again.
*   **Expected Result:**
    *   The script should skip the file (already up to date).
    *   No changes should be made to the target file.

**Test Case 2: Source and target hashes differ**

*   **Setup:**
    *   Create a source file in the repository.
    *   Install the file using `agent-install.sh`.
    *   Modify the target file.
    *   Verify that the source and target files have different hashes.
*   **Action:**
    *   Run `agent-install.sh` again.
*   **Expected Result:**
    *   The script should reinstall the file.
    *   The target file should be overwritten with the source file from the repository.
    *   The source and target files should now have the same hash.

**Test Case 3: Target file doesn't exist**

*   **Setup:**
    *   Create a source file in the repository.
    *   Ensure the target file does not exist.
*   **Action:**
    *   Run `agent-install.sh`.
*   **Expected Result:**
    *   The script should install the file.
    *   The target file should be created with the content of the source file.
    *   The source and target files should have the same hash.

**Test Case 4: Multiple files in a hook directory with mixed states**

*   **Setup:**
    *   Create a hook directory in the repository.
    *   Create multiple files within the hook directory.
    *   Install the hook directory using `agent-install.sh`.
    *   Modify some of the target files in the hook directory.
    *   Verify that some source and target files have the same hash, while others have different hashes.
*   **Action:**
    *   Run `agent-install.sh` again.
*   **Expected Result:**
    *   The script should skip the files with matching hashes.
    *   The script should reinstall the files with differing hashes.
    *   All target files should now match their corresponding source files and have the same hashes.

**Test Case 5: The --force flag**

*   **Setup:**
    *   Create a source file in the repository.
    *   Install the file using `agent-install.sh`.
    *   Verify that the source and target files have the same hash.
*   **Action:**
    *   Run `agent-install.sh --force`.
*   **Expected Result:**
    *   The script should reinstall the file, even though the hashes match.
    *   The target file should be overwritten with the source file from the repository.
    *   The source and target files should still have the same hash.

*   **Setup:**
    *   Create a source file in the repository.
    *   Install the file using `agent-install.sh`.
    *   Modify the target file.
    *   Verify that the source and target files have different hashes.
*   **Action:**
    *   Run `agent-install.sh --force`.
*   **Expected Result:**
    *   The script should reinstall the file.
    *   The target file should be overwritten with the source file from the repository.
    *   The source and target files should now have the same hash.
