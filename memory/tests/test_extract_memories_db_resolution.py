"""Tests for extract_memories.py #703 DB resolution (no nova_memory fallback)."""

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add scripts to path
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

# Prevent ~/.openclaw/lib/pg_env.py from overriding PGDATABASE during import.
sys.modules["pg_env"] = MagicMock()
sys.modules["pg_env"].load_pg_env = MagicMock()


class TestGetDbConnectionResolution(unittest.TestCase):
    """TC-703 coverage for extract_memories.get_db_connection()."""

    def setUp(self):
        self._orig_pgdatabase = os.environ.get("PGDATABASE")
        self._orig_session_id = os.environ.get("SOURCE_SESSION_ID")
        # Ensure a clean starting state.
        os.environ.pop("PGDATABASE", None)
        os.environ.pop("SOURCE_SESSION_ID", None)

    def tearDown(self):
        self._restore("PGDATABASE", self._orig_pgdatabase)
        self._restore("SOURCE_SESSION_ID", self._orig_session_id)

    def _restore(self, key, value):
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value

    def _import_fresh(self):
        """Re-import the module so it picks up the current os.environ."""
        if "extract_memories" in sys.modules:
            del sys.modules["extract_memories"]
        import extract_memories
        return extract_memories

    def test_pgdatabase_unset_fails_loudly(self):
        """TC-703-007: unset PGDATABASE must raise a clear error."""
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "PGDATABASE is not set"):
            mod.get_db_connection()

    def test_pgdatabase_nonexistent_peer_memory_mismatch(self):
        """TC-703-008: wrong DB name is rejected without fallback."""
        os.environ["PGDATABASE"] = "nonexistent_peer_memory_db"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "does not look like a memory database"):
            mod.get_db_connection()

    def test_peer_match_uses_pgdatabase(self):
        """TC-703-002: matching peer DB resolves successfully."""
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:newhart:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")
        mock_connect.assert_called_once()

    def test_session_key_env_mismatch_fails(self):
        """TC-703-009a: session_key says nova but env says newhart -> fail."""
        os.environ["PGDATABASE"] = "newhart_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:nova:agent_chat"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "PGDATABASE mismatch"):
            mod.get_db_connection()

    def test_unknown_peer_fails(self):
        """TC-703-009b: unknown agent segment fails loudly."""
        os.environ["PGDATABASE"] = "totallymadeuppeer_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:totallymadeuppeer:x"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "Unknown agent"):
            mod.get_db_connection()

    def test_missing_agent_prefix_fails(self):
        """TC-703-009c: session_key without agent: prefix fails."""
        os.environ["PGDATABASE"] = "nova_memory"
        os.environ["SOURCE_SESSION_ID"] = "discord:channel:123"
        mod = self._import_fresh()
        with self.assertRaisesRegex(RuntimeError, "Cannot derive agent"):
            mod.get_db_connection()

    def test_athena_maps_to_nova_memory(self):
        """athena is a NOVA subagent and resolves to nova_memory."""
        os.environ["PGDATABASE"] = "nova_memory"
        os.environ["SOURCE_SESSION_ID"] = "agent:athena:agent_chat"
        mod = self._import_fresh()
        with patch("psycopg2.connect") as mock_connect:
            mock_connect.return_value = "mock_conn"
            conn = mod.get_db_connection()
        self.assertEqual(conn, "mock_conn")


if __name__ == "__main__":
    unittest.main(verbosity=2)
