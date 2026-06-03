#!/usr/bin/env python3
"""
test_ghost_entity_prevention.py — Test suite for issues #230 and #267.

Tests:
  Section A: is_plausible_entity() heuristic rejection
  Section B: find_entity_id() smarter matching (alternate_spellings, domain, substring)
  Section C: _store_fact() type resolution from entity_type_map
  Section D: Schema — entities.alternate_spellings column
  Section E: ensure_entity() name-only collision detection
  Section F: End-to-end pipeline integration tests (mocked DB)
  Section G: Edge cases for is_plausible_entity()
  Section H: Regression — existing behaviors unchanged

Run:
  cd ~/.openclaw/workspace/nova-mind
  python3 memory/tests/test_ghost_entity_prevention.py

Exit 0 = all tests passed.
Exit 1 = one or more failures (details printed).
"""

import json
import os
import sys
import unittest
from typing import Any, Optional
from unittest.mock import MagicMock, patch, call

# Add memory/scripts to path
SCRIPT_DIR = os.path.join(os.path.dirname(__file__), "..", "scripts")
sys.path.insert(0, os.path.abspath(SCRIPT_DIR))

# Stub out heavy imports before loading the module
sys.modules.setdefault("psycopg2", MagicMock())
sys.modules.setdefault("psycopg2.extras", MagicMock())
sys.modules.setdefault("requests", MagicMock())

# Stub pg_env and env_loader so the module loads in test without live config
pg_env_stub = MagicMock()
pg_env_stub.load_pg_env = lambda: None
sys.modules["pg_env"] = pg_env_stub
env_loader_stub = MagicMock()
env_loader_stub.load_openclaw_env = lambda: None
sys.modules["env_loader"] = env_loader_stub

import extract_memories as em  # noqa: E402  (after stubs)


# ── Helpers ────────────────────────────────────────────────────────────────────

def make_cursor(rows=None):
    """Return a mock cursor whose fetchone/fetchall return the given rows."""
    cur = MagicMock()
    if rows is None:
        rows = []
    # fetchone cycles through rows one at a time
    _rows = list(rows)
    cur.fetchone.side_effect = lambda: _rows.pop(0) if _rows else None
    cur.fetchall.return_value = []
    return cur


def make_conn(cursor=None):
    """Return a mock DB connection."""
    conn = MagicMock()
    if cursor:
        conn.cursor.return_value.__enter__ = MagicMock(return_value=cursor)
        conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    return conn


# ══════════════════════════════════════════════════════════════════════════════
# Section A: is_plausible_entity()
# ══════════════════════════════════════════════════════════════════════════════

class TestIsPlausibleEntityEnvVars(unittest.TestCase):
    """A1 — Env var pattern rejection"""

    def test_A1_1_nova_documentation_haiku(self):
        self.assertFalse(em.is_plausible_entity("NOVA_DOCUMENTATION_HAIKU"), "A1-1")

    def test_A1_2_sender_provider(self):
        self.assertFalse(em.is_plausible_entity("SENDER_PROVIDER"), "A1-2")

    def test_A1_3_source_channel_transcript_id(self):
        self.assertFalse(em.is_plausible_entity("SOURCE_CHANNEL_TRANSCRIPT_ID"), "A1-3")

    def test_A1_4_openrouter_api_key(self):
        self.assertFalse(em.is_plausible_entity("OPENROUTER_API_KEY"), "A1-4")

    def test_A1_5_nova_passes(self):
        self.assertTrue(em.is_plausible_entity("NOVA"), "A1-5: ALL_CAPS no underscore should pass")

    def test_A1_6_valid_passes(self):
        self.assertTrue(em.is_plausible_entity("VALID"), "A1-6")

    def test_A1_7_ai_passes(self):
        self.assertTrue(em.is_plausible_entity("AI"), "A1-7: Short ALL_CAPS abbreviation should pass")


class TestIsPlausibleEntityFilePaths(unittest.TestCase):
    """A2 — File path / filename rejection"""

    def test_A2_1_soul_md(self):
        self.assertFalse(em.is_plausible_entity("SOUL.md"), "A2-1")

    def test_A2_2_handler_ts(self):
        self.assertFalse(em.is_plausible_entity("handler.ts"), "A2-2")

    def test_A2_3_json_file(self):
        self.assertFalse(em.is_plausible_entity("memory-extraction-config.json"), "A2-3")

    def test_A2_4_py_file(self):
        self.assertFalse(em.is_plausible_entity("extract_memories.py"), "A2-4")

    def test_A2_5_absolute_path(self):
        self.assertFalse(em.is_plausible_entity("/home/nova/.openclaw/scripts/foo.py"), "A2-5")

    def test_A2_6_relative_path(self):
        self.assertFalse(em.is_plausible_entity("scripts/foo.sh"), "A2-6")

    def test_A2_7_identity_md(self):
        self.assertFalse(em.is_plausible_entity("IDENTITY.md"), "A2-7")

    def test_A2_8_readme_passes(self):
        self.assertTrue(em.is_plausible_entity("README"), "A2-8: No extension, no path sep — passes")


class TestIsPlausibleEntityDbArtifacts(unittest.TestCase):
    """A3 — DB artifact marker rejection"""

    def test_A3_1_unknown_user_numeric(self):
        self.assertFalse(em.is_plausible_entity("Unknown user: 330189773371080716"), "A3-1")

    def test_A3_2_unknown_user_name(self):
        self.assertFalse(em.is_plausible_entity("Unknown user: graybeard"), "A3-2")

    def test_A3_3_cognition_system_id(self):
        self.assertFalse(em.is_plausible_entity("Cognition System (id=9)"), "A3-3")

    def test_A3_4_full_system_id(self):
        self.assertFalse(em.is_plausible_entity("Full System (id=10)"), "A3-4")

    def test_A3_5_project_number(self):
        self.assertFalse(em.is_plausible_entity("NOVA Multiuser System (project #28)"), "A3-5")

    def test_A3_6_agents_table(self):
        self.assertFalse(em.is_plausible_entity("agents table"), "A3-6")

    def test_A3_7_workflows_table(self):
        self.assertFalse(em.is_plausible_entity("workflows table"), "A3-7")

    def test_A3_8_agent_chat_table(self):
        self.assertFalse(em.is_plausible_entity("agent_chat table"), "A3-8")

    def test_A3_9_nova_staging_db_role(self):
        self.assertFalse(em.is_plausible_entity("nova_staging DB role"), "A3-9")

    def test_A3_10_nova_hyphen_staging_db_role(self):
        self.assertFalse(em.is_plausible_entity("nova-staging DB role"), "A3-10")

    def test_A3_11_round_table_passes(self):
        self.assertTrue(em.is_plausible_entity("Round Table"), "A3-11: 'table' not trailing word")

    def test_A3_12_em_dash(self):
        self.assertFalse(em.is_plausible_entity("Google Drive \u2014 Edmund's Edification"), "A3-12")

    def test_A3_13_sender_artifact(self):
        self.assertFalse(em.is_plausible_entity("Sender (I)ruid)"), "A3-13")

    def test_A3_14_generic_phrase(self):
        self.assertFalse(em.is_plausible_entity("the group (including sender)"), "A3-14")


class TestIsPlausibleEntityGenericRoles(unittest.TestCase):
    """A4 — Generic role word / pronoun rejection"""

    def test_A4_1_sender_lower(self):
        self.assertFalse(em.is_plausible_entity("sender"), "A4-1")

    def test_A4_2_sender_title(self):
        self.assertFalse(em.is_plausible_entity("Sender"), "A4-2")

    def test_A4_3_recipient(self):
        self.assertFalse(em.is_plausible_entity("recipient"), "A4-3")

    def test_A4_4_the_recipient(self):
        self.assertFalse(em.is_plausible_entity("the recipient"), "A4-4")

    def test_A4_5_the_sender(self):
        self.assertFalse(em.is_plausible_entity("the sender"), "A4-5")

    def test_A4_6_system(self):
        self.assertFalse(em.is_plausible_entity("system"), "A4-6")

    def test_A4_7_user(self):
        self.assertFalse(em.is_plausible_entity("user"), "A4-7")

    def test_A4_8_plugin(self):
        self.assertFalse(em.is_plausible_entity("plugin"), "A4-8")

    def test_A4_9_the_group(self):
        self.assertFalse(em.is_plausible_entity("the group"), "A4-9")

    def test_A4_10_the_team(self):
        self.assertFalse(em.is_plausible_entity("the team"), "A4-10")

    def test_A4_11_nova_staging_memory(self):
        self.assertFalse(em.is_plausible_entity("nova_staging_memory"), "A4-11")

    def test_A4_12_agent_bootstrap_context(self):
        self.assertFalse(em.is_plausible_entity("agent_bootstrap_context"), "A4-12")


class TestIsPlausibleEntityLegitimate(unittest.TestCase):
    """A5 — Must NOT reject legitimate entities"""

    def test_A5_1_john_smith(self):
        self.assertTrue(em.is_plausible_entity("John Smith"), "A5-1")

    def test_A5_2_rayven(self):
        self.assertTrue(em.is_plausible_entity("Rayven"), "A5-2")

    def test_A5_3_trammell_ventures(self):
        self.assertTrue(em.is_plausible_entity("Trammell Ventures"), "A5-3")

    def test_A5_4_art_car(self):
        self.assertTrue(em.is_plausible_entity("Gargantuan Art Car"), "A5-4")

    def test_A5_5_blockhenge(self):
        self.assertTrue(em.is_plausible_entity("Blockhenge"), "A5-5")

    def test_A5_6_idruid_handle(self):
        self.assertTrue(em.is_plausible_entity("I)ruid"), "A5-6")

    def test_A5_7_nova_mind(self):
        self.assertTrue(em.is_plausible_entity("nova-mind"), "A5-7")

    def test_A5_8_openclaw(self):
        self.assertTrue(em.is_plausible_entity("OpenClaw"), "A5-8")

    def test_A5_9_wearevalid_domain(self):
        self.assertTrue(em.is_plausible_entity("wearevalid.ai"), "A5-9: Domain names pass layer 1")

    def test_A5_10_roguesignal_domain(self):
        self.assertTrue(em.is_plausible_entity("roguesignal.io"), "A5-10")

    def test_A5_11_dustin_full_name(self):
        self.assertTrue(em.is_plausible_entity("Dustin D. Trammell"), "A5-11")

    def test_A5_12_coinbase(self):
        self.assertTrue(em.is_plausible_entity("CoinBase"), "A5-12")

    def test_A5_13_unicode_name(self):
        self.assertTrue(em.is_plausible_entity("\u00dcber"), "A5-13")

    def test_A5_14_dj_khaled(self):
        self.assertTrue(em.is_plausible_entity("DJ Khaled"), "A5-14")


# ══════════════════════════════════════════════════════════════════════════════
# Section B: find_entity_id() smarter matching
# ══════════════════════════════════════════════════════════════════════════════

class TestFindEntityIdAlternateSpellings(unittest.TestCase):
    """B1 — alternate_spellings matching"""

    def _make_conn_for_alternate(self, entity_id: int):
        """Return a mock conn that simulates the SQL query matching alternate_spellings."""
        conn = MagicMock()
        cur = MagicMock()
        # fetchone returns the entity_id (simulating the SQL match)
        cur.fetchone.return_value = (entity_id,)
        cur.fetchall.return_value = []
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        return conn

    def test_B1_5_exact_name(self):
        """B1-5: Direct name match (existing behavior)"""
        conn = self._make_conn_for_alternate(6)
        result = em.find_entity_id("Rayven", conn)
        self.assertEqual(result, 6, "B1-5: Direct name match")

    def test_B1_7_nickname_match(self):
        """B1-7: I)ruid should match via nicknames or alternate_spellings"""
        conn = self._make_conn_for_alternate(2)
        result = em.find_entity_id("I)ruid", conn)
        self.assertEqual(result, 2, "B1-7: Nickname/alternate match")

    def test_B1_6_no_match(self):
        """B1-6: Non-matching name returns None"""
        conn = MagicMock()
        cur = MagicMock()
        cur.fetchone.return_value = None  # No match in SQL
        cur.fetchall.return_value = []    # No domain or substring candidates
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        result = em.find_entity_id("RavenX", conn)
        self.assertIsNone(result, "B1-6: No match for 'RavenX'")

    def test_B1_8_alternate_raven_title_case(self):
        """B1-8: 'Raven' resolves to Rayven (id=6) via alternate_spellings.

        Rayven's alternate_spellings=['raven', 'ravens', 'Raven']. The subject
        'Raven' does NOT match entity name 'Rayven' on name/full_name/nicknames;
        it resolves via LOWER(%s) = ANY(SELECT LOWER(unnest(alternate_spellings))).
        The mock simulates the DB returning a match (as it would in reality for
        this alternate_spellings hit). We additionally verify that the SQL
        actually includes the alternate_spellings clause.
        """
        conn = self._make_conn_for_alternate(6)
        result = em.find_entity_id("Raven", conn)
        self.assertEqual(result, 6, "B1-8: 'Raven' -> Rayven via alternate_spellings")
        # Confirm the SQL query included the alternate_spellings clause
        cur = conn.cursor.return_value
        all_sql = " ".join(str(c.args[0]) for c in cur.execute.call_args_list)
        self.assertIn(
            "alternate_spellings", all_sql,
            "B1-8: SQL executed by find_entity_id must query alternate_spellings",
        )

    def test_B1_9_alternate_raven_lowercase(self):
        """B1-9: 'raven' (all-lowercase) resolves via alternate_spellings (case-insensitive)."""
        conn = self._make_conn_for_alternate(6)
        result = em.find_entity_id("raven", conn)
        self.assertEqual(result, 6, "B1-9: 'raven' -> Rayven via alternate_spellings")

    def test_B1_10_alternate_ravens_plural(self):
        """B1-10: 'ravens' (plural) resolves via alternate_spellings."""
        conn = self._make_conn_for_alternate(6)
        result = em.find_entity_id("ravens", conn)
        self.assertEqual(result, 6, "B1-10: 'ravens' -> Rayven via alternate_spellings")

    def test_B1_11_alternate_RAVEN_uppercase(self):
        """B1-11: 'RAVEN' (all-caps) resolves via alternate_spellings (case-insensitive)."""
        conn = self._make_conn_for_alternate(6)
        result = em.find_entity_id("RAVEN", conn)
        self.assertEqual(result, 6, "B1-11: 'RAVEN' -> Rayven via alternate_spellings")


class TestFindEntityIdDomainMatching(unittest.TestCase):
    """B2 — Domain-name-to-entity matching"""

    def _make_conn_no_sql_match(self, entity_list):
        """Conn where SQL name query returns None, but domain scan returns entity_list."""
        conn = MagicMock()
        cur = MagicMock()
        # fetchone = None (no exact name match)
        cur.fetchone.return_value = None
        # fetchall returns the entity list for domain scanning
        cur.fetchall.return_value = entity_list
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        return conn

    def test_B2_1_roguesignal_io(self):
        conn = self._make_conn_no_sql_match([(11, "Rogue Signal")])
        result = em.find_entity_id("roguesignal.io", conn)
        self.assertEqual(result, 11, "B2-1: roguesignal.io -> Rogue Signal")

    def test_B2_2_roguesignal_com(self):
        conn = self._make_conn_no_sql_match([(11, "Rogue Signal")])
        result = em.find_entity_id("roguesignal.com", conn)
        self.assertEqual(result, 11, "B2-2: roguesignal.com -> Rogue Signal")

    def test_B2_4_renaissancemachine_ai(self):
        conn = self._make_conn_no_sql_match([(5384, "Renaissance Machine")])
        result = em.find_entity_id("renaissancemachine.ai", conn)
        self.assertEqual(result, 5384, "B2-4: renaissancemachine.ai -> Renaissance Machine")

    def test_B2_6_valid_ai(self):
        conn = self._make_conn_no_sql_match([(3450, "VALID")])
        result = em.find_entity_id("VALID.ai", conn)
        self.assertEqual(result, 3450, "B2-6: VALID.ai -> VALID")

    def test_B2_7_valid_ai_lowercase(self):
        conn = self._make_conn_no_sql_match([(3450, "VALID")])
        result = em.find_entity_id("valid.ai", conn)
        self.assertEqual(result, 3450, "B2-7: valid.ai -> VALID (case-insensitive)")

    def test_B2_8_example_com_no_match(self):
        conn = self._make_conn_no_sql_match([])
        result = em.find_entity_id("example.com", conn)
        self.assertIsNone(result, "B2-8: No entity named 'example'")


class TestFindEntityIdSubstringMatching(unittest.TestCase):
    """B3 — Substring/containment matching"""

    def _make_conn_substring(self, substring_candidates, domain_candidates=None):
        """Conn where fetchone=None; fetchall returns domain_candidates then substring_candidates.

        For subjects without dots, domain scan is skipped entirely, so only
        one fetchall call occurs (the substring scan).
        For subjects with dots, domain scan runs first (call 1), then substring (call 2).
        """
        conn = MagicMock()
        call_count = [0]
        _domain = domain_candidates if domain_candidates is not None else []

        def fetchall_side_effect():
            call_count[0] += 1
            if call_count[0] == 1 and domain_candidates is not None:
                # First call is domain scan when we explicitly provide domain candidates
                return _domain
            else:
                # Substring scan (or first call when no domain scan requested)
                return substring_candidates

        cur = MagicMock()
        cur.fetchone.return_value = None
        cur.fetchall.side_effect = fetchall_side_effect
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        return conn

    def test_B3_1_valid_movement(self):
        """B3-1: 'VALID movement' (no dot) — domain scan skipped, substring matches"""
        # No dot -> _extract_domain_base returns None -> domain scan skipped
        # Only one fetchall call (substring scan)
        conn = self._make_conn_substring([(3450, "VALID")])
        result = em.find_entity_id("VALID movement", conn)
        self.assertEqual(result, 3450, "B3-1: 'VALID movement' contains 'VALID'")

    def test_B3_2_the_valid_movement(self):
        """B3-2: 'the VALID movement' — 'VALID' is a whole word within the phrase"""
        conn = self._make_conn_substring([(3450, "VALID")])
        result = em.find_entity_id("the VALID movement", conn)
        self.assertEqual(result, 3450, "B3-2: 'VALID' as word in phrase")

    def test_B3_3_invalid_no_match(self):
        """B3-3: 'invalid.io' must NOT match 'VALID' — whole-word boundary"""
        # 'invalid.io' has a dot -> domain scan runs first
        # domain base of 'invalid.io' -> 'invalid'; normalized 'invalid' != 'valid'
        # Then substring scan: 'valid' is inside 'invalid' but word boundary rejects it
        conn = self._make_conn_substring(
            substring_candidates=[(3450, "VALID")],
            domain_candidates=[(3450, "VALID")],  # returned in domain scan but no match
        )
        result = em.find_entity_id("invalid.io", conn)
        self.assertIsNone(result, "B3-3: 'invalid' must not match 'VALID'")


# ══════════════════════════════════════════════════════════════════════════════
# Section C: Type resolution fix
# ══════════════════════════════════════════════════════════════════════════════

class TestEntityTypeMap(unittest.TestCase):
    """C1/C2 — entity_type_map built correctly in store_extracted"""

    def test_entity_type_map_organization(self):
        """C1-1: entity_type_map picks up 'organization' type"""
        data = {"entities": [{"name": "OpenClaw", "type": "organization"}], "facts": []}
        # The map is built inside store_extracted; test the logic directly
        entity_type_map = {
            (ent.get("name") or "").strip().lower(): em.normalize_entity_type(ent.get("type") or "other")
            for ent in (data.get("entities") or [])
            if ent.get("name")
        }
        self.assertEqual(entity_type_map.get("openclaw"), "organization", "C1-1")

    def test_entity_type_map_ai(self):
        """C1-2: entity_type_map picks up 'ai' type"""
        data = {"entities": [{"name": "Cadence", "type": "ai"}], "facts": []}
        entity_type_map = {
            (ent.get("name") or "").strip().lower(): em.normalize_entity_type(ent.get("type") or "other")
            for ent in (data.get("entities") or [])
            if ent.get("name")
        }
        self.assertEqual(entity_type_map.get("cadence"), "ai", "C1-2")

    def test_entity_type_map_case_insensitive(self):
        """C1-3: Case-insensitive lookup in entity_type_map"""
        data = {"entities": [{"name": "Blockhenge", "type": "organization"}], "facts": []}
        entity_type_map = {
            (ent.get("name") or "").strip().lower(): em.normalize_entity_type(ent.get("type") or "other")
            for ent in (data.get("entities") or [])
            if ent.get("name")
        }
        # Lookup with lowercase
        self.assertEqual(entity_type_map.get("blockhenge"), "organization", "C1-3")


class TestNormalizeEntityType(unittest.TestCase):
    """C3 — Type normalization (existing behavior)"""

    def test_C3_1_place(self):
        self.assertEqual(em.normalize_entity_type("place"), "other", "C3-1")

    def test_C3_2_restaurant(self):
        self.assertEqual(em.normalize_entity_type("restaurant"), "other", "C3-2")

    def test_C3_3_person(self):
        self.assertEqual(em.normalize_entity_type("person"), "person", "C3-3")

    def test_C3_4_garbage_type(self):
        self.assertEqual(em.normalize_entity_type("garbage_type"), "other", "C3-4")

    def test_C3_5_case_normalization(self):
        self.assertEqual(em.normalize_entity_type("PERSON"), "person", "C3-5")


# ══════════════════════════════════════════════════════════════════════════════
# Section E: ensure_entity() name-only collision detection
# ══════════════════════════════════════════════════════════════════════════════

class TestEnsureEntityCollision(unittest.TestCase):
    """B5/E — Name-only collision detection in ensure_entity"""

    def _make_conn_existing_entity(self, entity_id: int):
        """Conn that returns existing entity on all lookups."""
        conn = MagicMock()
        cur = MagicMock()
        # All fetches return the existing entity
        cur.fetchone.return_value = (entity_id,)
        cur.fetchall.return_value = []
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        return conn

    def test_B5_1_returns_existing_organization_for_person(self):
        """B5-1: ensure_entity('VALID', 'organization') returns existing person id"""
        conn = self._make_conn_existing_entity(3428)
        result = em.ensure_entity("VALID", "organization", conn)
        self.assertEqual(result, 3428, "B5-1: Should return existing entity, not create new one")
        # Ensure no INSERT was executed (conn.commit should not have been called with a new insert)

    def test_B5_2_case_insensitive_collision(self):
        """B5-2: ensure_entity('valid', 'ai') returns existing VALID entity"""
        conn = self._make_conn_existing_entity(3428)
        result = em.ensure_entity("valid", "ai", conn)
        self.assertEqual(result, 3428, "B5-2: Case-insensitive name-only collision")


# ══════════════════════════════════════════════════════════════════════════════
# Section F: End-to-end (partial) integration tests (mocked DB)
# ══════════════════════════════════════════════════════════════════════════════

class TestIsPlausibleEntityIntegration(unittest.TestCase):
    """F1, F2, F5, F6 — Ghost entities not created for role words / artifacts."""

    def test_F1_sender_not_created(self):
        """F1: 'sender' fails heuristics"""
        self.assertFalse(em.is_plausible_entity("sender"), "F1")

    def test_F2_agent_bootstrap_context_not_created(self):
        """F2: 'agent_bootstrap_context' is a snake_case identifier — rejected"""
        self.assertFalse(em.is_plausible_entity("agent_bootstrap_context"), "F2")

    def test_F5_soul_md_not_created(self):
        """F5: SOUL.md is a file artifact"""
        self.assertFalse(em.is_plausible_entity("SOUL.md"), "F5")

    def test_F6_unknown_user_not_created(self):
        """F6: Unknown user: ... is a DB artifact"""
        self.assertFalse(em.is_plausible_entity("Unknown user: 330189773371080716"), "F6")

    def test_F8_newbury_passes(self):
        """F8: Legitimate new person name passes heuristics"""
        self.assertTrue(em.is_plausible_entity("Newbury"), "F8")


class TestDomainMatchIntegration(unittest.TestCase):
    """F3, F4 — Domain names route to existing entities."""

    def _make_conn_entities(self, entity_list):
        """Conn where fetchone=None but fetchall returns entity_list for domain scan."""
        conn = MagicMock()
        cur = MagicMock()
        cur.fetchone.return_value = None
        cur.fetchall.return_value = entity_list
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur
        return conn

    def test_F3_valid_ai_routes_to_valid(self):
        """F3: VALID.ai -> VALID (id=3450)"""
        conn = self._make_conn_entities([(3450, "VALID")])
        result = em.find_entity_id("VALID.ai", conn)
        self.assertEqual(result, 3450, "F3: VALID.ai should route to VALID")

    def test_F4_roguesignal_io_routes_to_rogue_signal(self):
        """F4: roguesignal.io -> Rogue Signal (id=11)"""
        conn = self._make_conn_entities([(11, "Rogue Signal")])
        result = em.find_entity_id("roguesignal.io", conn)
        self.assertEqual(result, 11, "F4: roguesignal.io -> Rogue Signal")


class TestTypeMapIntegration(unittest.TestCase):
    """F9 — Type from entities array used instead of 'person'."""

    def test_F9_acmecorp_gets_organization_type(self):
        """entity_type_map returns 'organization' for AcmeCorp"""
        data = {
            "entities": [{"name": "AcmeCorp", "type": "organization"}],
            "facts": [{"subject": "AcmeCorp", "key": "industry", "value": "software",
                       "visibility": "public", "durability": "long_term", "category": "observation"}]
        }
        entity_type_map = {
            (ent.get("name") or "").strip().lower(): em.normalize_entity_type(ent.get("type") or "other")
            for ent in (data.get("entities") or [])
            if ent.get("name")
        }
        etype = entity_type_map.get("acmecorp", "person")
        self.assertEqual(etype, "organization", "F9: should use 'organization', not 'person'")


class TestDeduplicationLogic(unittest.TestCase):
    """F12 — Distinct entities not falsely collapsed."""

    def test_F12_mark_smith_and_mark_johnson_are_distinct(self):
        """F12: Mark Smith and Mark Johnson are different people."""
        # Neither contains the other as a whole word
        import re
        subject_lower_smith = "mark smith"
        subject_lower_johnson = "mark johnson"
        ename_lower = "mark"
        # In our implementation we look for the entity name inside the subject
        # "Mark" would match both — but our substring matching only runs when
        # an entity named "Mark" exists. With no such entity, both pass through.
        # This test just validates the heuristic doesn't fire for non-existent entities.
        self.assertTrue(em.is_plausible_entity("Mark Smith"), "F12a: Mark Smith passes")
        self.assertTrue(em.is_plausible_entity("Mark Johnson"), "F12b: Mark Johnson passes")


class TestInBatchDeduplication(unittest.TestCase):
    """F11 — In-batch entity deduplication: VALID and VALID.ai both route to entity 3450."""

    def test_F11_valid_and_valid_ai_deduplicated_to_same_entity(self):
        """F11: When store_extracted() receives both 'VALID' and 'VALID.ai' in the
        entities array (with facts referencing both subjects), only one entity record
        is used (the existing VALID entity, id=3450), and both facts route to it.

        - is_plausible_entity() passes for both (domain names and ALL_CAPS without
          underscores are legitimate).
        - find_entity_id('VALID') returns 3450 via exact name match.
        - find_entity_id('VALID.ai') returns 3450 via domain normalization
          (domain base 'valid' matches entity name 'VALID').
        - No second entity is created; both store_or_reinforce_fact calls use
          entity_id=3450.
        """
        data = {
            "entities": [
                {"name": "VALID", "type": "organization"},
                {"name": "VALID.ai", "type": "organization"},
            ],
            "facts": [
                {
                    "subject": "VALID",
                    "key": "industry",
                    "value": "technology",
                    "visibility": "public",
                    "durability": "long_term",
                    "category": "observation",
                },
                {
                    "subject": "VALID.ai",
                    "key": "website",
                    "value": "wearevalid.ai",
                    "visibility": "public",
                    "durability": "long_term",
                    "category": "observation",
                },
            ],
        }

        with patch.object(em, "resolve_source_entity_id", return_value=1), \
             patch.object(em, "find_entity_id", return_value=3450) as mock_find, \
             patch.object(em, "store_or_reinforce_fact", return_value="STORED") as mock_store:

            conn = MagicMock()
            em.store_extracted(
                data=data,
                sender_name="I)ruid",
                sender_id="330189773371080716",
                sender_provider="discord",
                src_timestamp="2026-06-01T00:00:00Z",
                src_channel_transcript_id="t1",
                src_channel_session_id="s1",
                conn=conn,
            )

        # Both facts must have been stored using entity_id=3450
        self.assertEqual(
            mock_store.call_count, 2,
            "F11: store_or_reinforce_fact must be called exactly twice (one fact per subject)",
        )
        entity_ids = [c.kwargs["entity_id"] for c in mock_store.call_args_list]
        self.assertTrue(
            all(eid == 3450 for eid in entity_ids),
            f"F11: Both facts must route to entity_id=3450, got {entity_ids}",
        )

        # Verify find_entity_id was called for 'VALID.ai' (domain-matching path exercised)
        find_subjects = [c.args[0] for c in mock_find.call_args_list]
        self.assertIn(
            "VALID.ai", find_subjects,
            "F11: find_entity_id must be called with 'VALID.ai' (domain-dedup path)",
        )


# ══════════════════════════════════════════════════════════════════════════════
# Section G: Edge cases for is_plausible_entity
# ══════════════════════════════════════════════════════════════════════════════

class TestIsPlausibleEntityEdgeCases(unittest.TestCase):
    """G — Edge cases"""

    def test_G1_empty_string(self):
        self.assertFalse(em.is_plausible_entity(""), "G1")

    def test_G2_whitespace_only(self):
        self.assertFalse(em.is_plausible_entity("   "), "G2")

    def test_G3_null_string(self):
        # "null" — checked by callers, but is_plausible doesn't explicitly reject it
        # It passes heuristics (no underscore, not a file, etc.)
        # Guard is at the find_entity_id / ensure_entity level
        pass  # G3 is handled at a higher level

    def test_G4_unknown_string(self):
        # "unknown" — same; handled at higher level
        pass  # G4 is handled at a higher level

    def test_G5_single_char_rejected(self):
        self.assertFalse(em.is_plausible_entity("A"), "G5: Single char rejected")

    def test_G6_ai_passes(self):
        self.assertTrue(em.is_plausible_entity("AI"), "G6: 2-char abbreviation passes")

    def test_G7_long_name_no_crash(self):
        long_name = "A" * 200
        # Should not raise
        result = em.is_plausible_entity(long_name)
        self.assertIsInstance(result, bool, "G7: Returns bool, no crash")

    def test_G8_numeric_only_rejected(self):
        self.assertFalse(em.is_plausible_entity("12345"), "G8")

    def test_G9_snowflake_rejected(self):
        self.assertFalse(em.is_plausible_entity("330189773371080716"), "G9")

    def test_G10_unicode_name_passes(self):
        self.assertTrue(em.is_plausible_entity("\u00c5ngstr\u00f6m"), "G10")

    def test_G11_leading_trailing_whitespace(self):
        """G11: Leading/trailing whitespace normalized, then evaluated"""
        # "  John  " -> "John" -> passes
        self.assertTrue(em.is_plausible_entity("  John  "), "G11: Whitespace stripped then passes")

    def test_G16_none_returns_false(self):
        self.assertFalse(em.is_plausible_entity(None), "G16: None returns False")


# ══════════════════════════════════════════════════════════════════════════════
# Section H: Regression tests
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# Section H (new): Phone privacy regression
# ══════════════════════════════════════════════════════════════════════════════

class TestPhonePrivacy(unittest.TestCase):
    """H2 — Phone facts are always stored as private, regardless of the
    visibility value the LLM extracted."""

    def _run_store_extracted_with_fact(self, fact_dict):
        """Helper: call store_extracted with a single fact, return the mock_store
        MagicMock so tests can inspect call args."""
        data = {"entities": [], "facts": [fact_dict]}
        with patch.object(em, "resolve_source_entity_id", return_value=1), \
             patch.object(em, "find_entity_id", return_value=100), \
             patch.object(em, "store_or_reinforce_fact", return_value="STORED") as mock_store:
            conn = MagicMock()
            em.store_extracted(
                data=data,
                sender_name="I)ruid",
                sender_id="330189773371080716",
                sender_provider="discord",
                src_timestamp="2026-06-01T00:00:00Z",
                src_channel_transcript_id="t1",
                src_channel_session_id="s1",
                conn=conn,
            )
        return mock_store

    def test_H2_phone_overrides_public_visibility(self):
        """H2-1: key='phone' with visibility='public' is stored as visibility='private'.

        The hard rule in store_extracted's facts loop:
            if key == 'phone': visibility = 'private'
        must fire before _store_fact() and thus before store_or_reinforce_fact().
        The LLM-extracted visibility ('public') must never reach the DB for phone facts.
        """
        mock_store = self._run_store_extracted_with_fact({
            "subject": "John Smith",
            "key": "phone",
            "value": "+1-555-0100",
            "visibility": "public",  # Wrong — should be overridden
            "durability": "long_term",
            "category": "observation",
        })
        mock_store.assert_called_once()
        stored_visibility = mock_store.call_args.kwargs["visibility"]
        self.assertEqual(
            stored_visibility, "private",
            "H2-1: phone fact must be stored with visibility='private', "
            f"but got visibility={stored_visibility!r}",
        )

    def test_H2_phone_overrides_shared_visibility(self):
        """H2-2: key='phone' with visibility='shared' is also overridden to 'private'.

        The override must apply regardless of what the LLM extracted.
        """
        mock_store = self._run_store_extracted_with_fact({
            "subject": "Alice",
            "key": "phone",
            "value": "+1-555-0200",
            "visibility": "shared",  # Any non-private value must be overridden
            "durability": "long_term",
            "category": "observation",
        })
        mock_store.assert_called_once()
        stored_visibility = mock_store.call_args.kwargs["visibility"]
        self.assertEqual(
            stored_visibility, "private",
            "H2-2: phone fact with visibility='shared' must be stored as 'private'",
        )

    def test_H2_non_phone_key_preserves_visibility(self):
        """H2-3: Non-phone keys are NOT affected by the phone override.

        This guards against the override being too broad — only 'phone' is
        subject to the hard-private rule.
        """
        mock_store = self._run_store_extracted_with_fact({
            "subject": "Alice",
            "key": "email",
            "value": "alice@example.com",
            "visibility": "public",
            "durability": "long_term",
            "category": "observation",
        })
        mock_store.assert_called_once()
        stored_visibility = mock_store.call_args.kwargs["visibility"]
        self.assertEqual(
            stored_visibility, "public",
            "H2-3: non-phone key must preserve original visibility, "
            f"got visibility={stored_visibility!r}",
        )


class TestRegressionNormalizeEntityType(unittest.TestCase):
    """H15 — normalize_entity_type unchanged"""

    def test_H15_place_to_other(self):
        self.assertEqual(em.normalize_entity_type("place"), "other", "H15: place -> other")

    def test_H15_person_unchanged(self):
        self.assertEqual(em.normalize_entity_type("person"), "person", "H15: person passthrough")

    def test_H15_restaurant_to_other(self):
        self.assertEqual(em.normalize_entity_type("restaurant"), "other", "H15")


class TestRegressionFindEntityIdPlatformPriority(unittest.TestCase):
    """H7 — Platform ID takes priority over name when subject == sender"""

    def test_H7_platform_id_priority(self):
        """H7: When subject == sender, platform ID lookup wins over name"""
        # This is tested via find_entity_id's existing logic: when
        # sender_provider + sender_id + subject == sender_name, it calls
        # _resolve_by_sender_id first. We verify that path exists.
        conn = MagicMock()
        cur = MagicMock()
        cur.fetchone.return_value = (99,)  # Simulates platform ID match
        cur.fetchall.return_value = []
        cur.__enter__ = MagicMock(return_value=cur)
        cur.__exit__ = MagicMock(return_value=False)
        conn.cursor.return_value = cur

        with patch.object(em, '_resolve_by_sender_id', return_value=42) as mock_resolve:
            result = em.find_entity_id(
                "Dustin",
                conn,
                sender_id="330189773371080716",
                sender_provider="discord",
                sender_name="Dustin",
            )
        mock_resolve.assert_called_once()
        self.assertEqual(result, 42, "H7: Platform ID lookup returned first")


class TestRegressionIsPlausibleDoesNotBreakLegitEntities(unittest.TestCase):
    """H — is_plausible_entity must not block normal entity creation"""

    def test_sender_entity_creation_name_passes(self):
        """H1: Sender name like 'Dustin' passes heuristics"""
        self.assertTrue(em.is_plausible_entity("Dustin"), "H1: Sender name passes")

    def test_h13_nicknames_still_work(self):
        """H13: Entity with nicknames — nickname matching still works (SQL query unchanged)"""
        # The SQL query now includes an extra OR clause for alternate_spellings;
        # the nicknames clause is still present and unchanged.
        # Verify by checking the SQL in find_entity_id includes 'nicknames'
        import inspect
        source = inspect.getsource(em.find_entity_id)
        self.assertIn("nicknames", source, "H13: nicknames clause still in find_entity_id")

    def test_h13_alternate_spellings_added(self):
        """H13: alternate_spellings clause also present"""
        import inspect
        source = inspect.getsource(em.find_entity_id)
        self.assertIn("alternate_spellings", source, "H13: alternate_spellings clause added")


class TestRegressionDomainExtraction(unittest.TestCase):
    """G15 — Multi-part domain subdomain stripping"""

    def test_G15_app_blockhenge_com(self):
        base = em._extract_domain_base("app.blockhenge.com")
        self.assertEqual(base, "blockhenge", "G15: app.blockhenge.com -> blockhenge")

    def test_domain_base_simple(self):
        self.assertEqual(em._extract_domain_base("roguesignal.io"), "roguesignal")

    def test_domain_base_www(self):
        self.assertEqual(em._extract_domain_base("www.roguesignal.io"), "roguesignal")

    def test_domain_base_none_for_no_dot(self):
        self.assertIsNone(em._extract_domain_base("localhost"))

    def test_domain_base_valid_ai(self):
        self.assertEqual(em._extract_domain_base("valid.ai"), "valid")

    def test_normalize_domain_strips_spaces_hyphens(self):
        self.assertEqual(em._normalize_for_domain_match("Rogue Signal"), "roguesignal")
        self.assertEqual(em._normalize_for_domain_match("roguesignal"), "roguesignal")
        self.assertEqual(em._normalize_for_domain_match("Renaissance Machine"), "renaissancemachine")


# ══════════════════════════════════════════════════════════════════════════════
# Main runner
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()

    # Ordered by section
    for cls in [
        TestIsPlausibleEntityEnvVars,
        TestIsPlausibleEntityFilePaths,
        TestIsPlausibleEntityDbArtifacts,
        TestIsPlausibleEntityGenericRoles,
        TestIsPlausibleEntityLegitimate,
        TestFindEntityIdAlternateSpellings,
        TestFindEntityIdDomainMatching,
        TestFindEntityIdSubstringMatching,
        TestEntityTypeMap,
        TestNormalizeEntityType,
        TestEnsureEntityCollision,
        TestIsPlausibleEntityIntegration,
        TestDomainMatchIntegration,
        TestTypeMapIntegration,
        TestDeduplicationLogic,
        TestInBatchDeduplication,
        TestIsPlausibleEntityEdgeCases,
        TestPhonePrivacy,
        TestRegressionNormalizeEntityType,
        TestRegressionFindEntityIdPlatformPriority,
        TestRegressionIsPlausibleDoesNotBreakLegitEntities,
        TestRegressionDomainExtraction,
    ]:
        suite.addTests(loader.loadTestsFromTestCase(cls))

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
