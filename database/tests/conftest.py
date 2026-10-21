"""Pytest fixtures shared by database/ tests."""

import os
import sys

# Make imports like `from fix_installer_ownership import ...` work when tests
# import modules from the database/ directory.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
