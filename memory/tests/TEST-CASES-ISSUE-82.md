# Test Cases for Issue #82: Add Unload Option to Test Data Script

This document outlines test cases for the 'unload' option added to the test data script. The unload option should remove all test entities and associated data from the database, ensuring a clean state for subsequent tests.

## Test Cases

**1. Unload removes all test entities (ids 1-15)**

*   **Description:** Verify that all test entities with IDs ranging from 1 to 15 are removed from the `entities` table after running the unload script.
*   **Steps:**
    1.  Load the test data script to populate the database.
    2.  Run the unload script.
    3.  Query the `entities` table to check the IDs.
*   **Expected Result:** The `entities` table should not contain any entities with IDs from 1 to 15.

**2. Unload removes associated entity_facts**

*   **Description:** Verify that all `entity_facts` associated with the removed test entities are also removed after running the unload script.
*   **Steps:**
    1.  Load the test data script.
    2.  Run the unload script.
    3.  Query the `entity_facts` table for facts associated with entity IDs 1-15.
*   **Expected Result:** The `entity_facts` table should not contain any records associated with entity IDs from 1 to 15.

**3. Unload removes test events, places, lessons, tasks**

*   **Description:** Verify that all test data related to events, places, lessons, and tasks are removed from the database.
*   **Steps:**
    1.  Load the test data script.
    2.  Run the unload script.
    3.  Query the relevant tables (`events`, `places`, `lessons`, `tasks`) to check for any test data.
*   **Expected Result:** The tables should not contain test data associated with the default test user.

**4. Sequences are reset appropriately after unload**

*   **Description:** Verify that sequences used for generating IDs are reset to their initial values after running the unload script.  This ensures that subsequent data loads will start with the expected IDs.
*   **Steps:**
    1.  Load the test data script.
    2.  Run the unload script.
    3.  Load the test data script again.
    4.  Verify that entities are created with IDs starting from 1.
*   **Expected Result:** The newly created entities should have IDs starting from 1.

**5. Unload is idempotent (running twice doesn't error)**

*   **Description:** Verify that running the unload script multiple times does not result in errors or unexpected behavior.
*   **Steps:**
    1.  Load the test data script.
    2.  Run the unload script.
    3.  Run the unload script again.
*   **Expected Result:** The unload script should complete without errors in both runs.

**6. Unload doesn't affect non-test data**

*   **Description:** Verify that the unload script only removes test data and does not affect any non-test data that might be present in the database.
*   **Steps:**
    1.  Insert some non-test data into the relevant tables.
    2.  Load the test data script.
    3.  Run the unload script.
    4.  Verify that the non-test data is still present in the database.
*   **Expected Result:** The non-test data inserted in step 1 should still exist in the database after running the unload script.

**7. Load → Unload cycle leaves database in original state**

*   **Description:**  Verify that loading the test data and then unloading it returns the database to its original, pre-load state.
*   **Steps:**
    1.  Take a database snapshot (backup).
    2.  Load the test data script.
    3.  Run the unload script.
    4.  Compare the current database state to the backup created in step 1.
*   **Expected Result:** The database state after the load and unload cycle should be identical to the initial backup.
