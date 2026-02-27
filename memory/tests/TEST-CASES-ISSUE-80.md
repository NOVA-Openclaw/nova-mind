# Test Cases for nova-memory#80: Grammar Parser Installation

These test cases verify the correct installation and updating of the `grammar_parser` Python package by the installer.

## 1. Fresh Install

**Objective:** Verify that a fresh installation creates the `~/.local/share/nova/grammar_parser/` directory and copies all necessary files.

**Steps:**

1.  Ensure that the `~/.local/share/nova/grammar_parser/` directory does not exist.
2.  Run the installer.
3.  Verify that the `~/.local/share/nova/grammar_parser/` directory exists.
4.  Verify that all `.py` files from the `grammar_parser` package are present in the `~/.local/share/nova/grammar_parser/` directory.
5.  Verify that the copied `.py` files have the correct permissions (readable and executable by the user).

## 2. Hash Matching (Up-to-Date)

**Objective:** Verify that if the file hashes match, the files are not overwritten, and an "up to date" message is displayed.

**Steps:**

1.  Run the installer to create the `~/.local/share/nova/grammar_parser/` directory and copy the files.
2.  Record the hashes of all `.py` files in the `~/.local/share/nova/grammar_parser/` directory.
3.  Run the installer again.
4.  Verify that the installer displays an "up to date" message for each `.py` file.
5.  Verify that the file hashes of the `.py` files in the `~/.local/share/nova/grammar_parser/` directory remain unchanged.

## 3. Hash Differing (Update Required)

**Objective:** Verify that if the file hashes differ, the files are overwritten, and an "updated" message is displayed.

**Steps:**

1.  Run the installer to create the `~/.local/share/nova/grammar_parser/` directory and copy the files.
2.  Modify one of the `.py` files in the source `grammar_parser` package (e.g., add a comment).
3.  Run the installer again.
4.  Verify that the installer displays an "updated" message for the modified `.py` file.
5.  Verify that the modified `.py` file in the `~/.local/share/nova/grammar_parser/` directory has been updated with the changes from the source package.

## 4. spacy Installation

**Objective:** Verify that `pip install spacy` runs when `requirements.txt` changes or dependencies are missing.

**Steps:**

1.  Ensure that `spacy` is not installed in the environment where the installer is run.
2.  Run the installer.
3.  Verify that `pip install spacy` is executed during the installation process (check installer logs).
4.  Verify that `spacy` is now installed in the environment.

## 5. spacy Model Download

**Objective:** Verify that the `en_core_web_sm` spacy model is downloaded if it is not already present.

**Steps:**

1.  Ensure that the `en_core_web_sm` spacy model is not downloaded (e.g., by deleting the model directory if it exists).
2.  Run the installer.
3.  Verify that the installer attempts to download the `en_core_web_sm` model (check installer logs).
4.  Verify that the `en_core_web_sm` model is now downloaded and available.

## 6. Verification: grammar_parser Import

**Objective:** Verify that the `grammar_parser` package can be imported after installation.

**Steps:**

1.  Run the installer.
2.  Open a Python interpreter.
3.  Attempt to import the `grammar_parser` package using `import grammar_parser`.
4.  Verify that the import is successful without any errors.

## 7. Verification: spacy Model Load

**Objective:** Verify that `spacy.load('en_core_web_sm')` succeeds after installation.

**Steps:**

1.  Run the installer.
2.  Open a Python interpreter.
3.  Attempt to load the `en_core_web_sm` model using `import spacy; nlp = spacy.load('en_core_web_sm')`.
4.  Verify that the model loads successfully without any errors.
