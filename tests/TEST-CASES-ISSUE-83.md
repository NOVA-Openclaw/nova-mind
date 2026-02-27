# Test Cases for Issue #83: Remove seed-data directory

## 1. Happy Path

*   **TC1.1: Remove seed-data directory:**
    *   **Steps:**
        1.  Delete the `seed-data/` directory.
        2.  Verify the directory is no longer present in the repository.
    *   **Expected Result:** The `seed-data/` directory is successfully removed.
*   **TC1.2: Update .gitignore:**
    *   **Steps:**
        1.  Add `seed-data/` to the `.gitignore` file.
        2.  Verify the change is committed.
    *   **Expected Result:** The `.gitignore` file is updated to prevent accidental re-addition of the `seed-data/` directory.
*   **TC1.3: No broken references:**
    *   **Steps:**
        1.  Search the codebase for any references to `seed-data/agents.csv` or `seed-data/sops.csv` using:
            ```bash
            grep -r "seed-data" --include="*.sh" --include="*.py" --include="*.md" --include="*.sql" .
            grep -r "agents.csv\|sops.csv" .
            ```
    *   **Expected Result:** No references to the removed files are found.
*   **TC1.4: Branch cleanup:**
    *   **Steps:**
        1.  Delete stale local branch `remove-seed-data-directory`
        2.  Recreate fresh from main before implementation
    *   **Expected Result:** Stale branch is deleted and a fresh branch is created from main.

## 2. Edge Cases

*   **TC2.1: Missed references:**
    *   **Steps:**
        1.  After removing the directory and files, run the application.
        2.  Exercise all functionalities that might have indirectly used the seed data.
    *   **Expected Result:** No errors or unexpected behavior occurs due to missing seed data.
*   **TC2.2: Local modifications:**
    *   **Steps:**
        1.  Create a local branch with modifications to `seed-data/agents.csv`.
        2.  Attempt to merge the branch after the `seed-data/` directory has been removed from the main branch.
    *   **Expected Result:** The merge process handles the conflict gracefully, potentially requiring manual resolution to remove references to the deleted files.

## 3. Domain-Specific Scenarios

*   **TC3.1: install.sh functionality:**
    *   **Steps:**
        1.  Run `install.sh` on **nova-staging** via SSH (`ssh nova-staging@localhost`) after removing the `seed-data/` directory.
    *   **Expected Result:** The `install.sh` script executes successfully without relying on the removed seed data.
*   **TC3.2: Documentation check:**
    *   **Steps:**
        1.  Review all documentation files for references to the `seed-data/` directory or its contents.
    *   **Expected Result:** No documentation files contain outdated references to the removed seed data.
*   **TC3.3: SQL/Script import check:**
    *   **Steps:**
        1.  Examine SQL scripts and other scripts for any import statements referencing `seed-data/agents.csv` or `seed-data/sops.csv` using:
            ```bash
            grep -r "seed-data" --include="*.sh" --include="*.py" --include="*.md" --include="*.sql" .
            grep -r "agents.csv\|sops.csv" .
            ```
    *   **Expected Result:** No SQL or other scripts attempt to import data from the removed CSV files.

## 4. Regression Testing

*   **TC4.1: Existing functionality:**
    *   **Steps:**
        1.  Run all existing unit and integration tests.
    *   **Expected Result:** All existing tests pass, indicating that the removal of the `seed-data/` directory did not negatively impact existing functionality. If no existing test suite covers seed-data, note "N/A - no existing test suite"
*   **TC4.2: Orphaned references:**
    *   **Steps:**
        1.  Perform a comprehensive code review to identify any potential orphaned references to data that was previously stored in the `seed-data/` directory.
    *   **Expected Result:** No orphaned references are found, ensuring that all data dependencies are properly managed after the removal of the seed data.
