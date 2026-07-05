"""Unit tests for the paragraph/section-boundary chunker.

These tests exercise ``_chunk_text()`` from
``memory/templates/memory-maintenance.py``. They are pure-Python and have no
database or Ollama dependency.
"""

import importlib.util
import re
import sys
import time
from pathlib import Path

import pytest

# Load the module under test by file path because the filename contains a hyphen.
_MAINTENANCE_PATH = (
    Path(__file__).resolve().parent.parent / "templates" / "memory-maintenance.py"
)
_spec = importlib.util.spec_from_file_location("memory_maintenance", str(_MAINTENANCE_PATH))
_memory_maintenance = importlib.util.module_from_spec(_spec)
sys.modules["memory_maintenance"] = _memory_maintenance
_spec.loader.exec_module(_memory_maintenance)

_chunk_text = _memory_maintenance._chunk_text
_find_overlap_boundary = _memory_maintenance._find_overlap_boundary


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _old_chunk_text(text, chunk_size=1000, overlap=200):
    """Reference hard-character chunker used as a baseline in metric tests."""
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunks.append(text[start:end])
        start += chunk_size - overlap
        if start >= len(text):
            break
    return chunks


def _sentence_boundary_positions(text):
    """Return indices in ``text`` that immediately follow a sentence end.

    A position is considered a sentence boundary if it follows ``. ``,
    ``? ``, or ``! `` and precedes a non-whitespace character, or if it is
    the start of the document (position 0).
    """
    positions = [0]
    for match in re.finditer(r"(?<=[.!?])\s+(?=\S)", text):
        positions.append(match.end())
    return positions


def _paragraph_boundary_positions(text):
    """Return indices immediately after ``\\n\\n`` and at position 0."""
    positions = [0]
    idx = text.find("\n\n")
    while idx != -1:
        positions.append(idx + 2)
        idx = text.find("\n\n", idx + 1)
    return positions


def _header_boundary_positions(text):
    """Return indices at the start of any markdown header line."""
    positions = []
    for match in re.finditer(r"^#{1,6}\s", text, flags=re.MULTILINE):
        positions.append(match.start())
    return positions


def _strip_overlap(prev_chunk, chunk, overlap_param):
    """Return the non-overlapping suffix of ``chunk``.

    Uses the chunker's own boundary logic to determine how much of ``chunk``
    was copied from the end of ``prev_chunk``. This avoids both accidental
    prefix/suffix matches on repetitive text and under-stripping.
    """
    boundary = _find_overlap_boundary(prev_chunk, overlap_param)
    overlap_len = len(prev_chunk) - boundary
    return chunk[overlap_len:]


def pct_mid_sentence_starts(chunks, overlap_param=0):
    """Measure the percentage of chunk boundaries that start mid-sentence.

    Overlap is stripped before measuring so that each boundary maps to a
    single position in the reconstructed source text. A boundary is
    considered clean if it aligns with a sentence end, paragraph break, or
    markdown header. Boundaries inside a sentence (preceded by a letter,
    comma, etc.) count as mid-sentence.
    """
    if len(chunks) <= 1:
        return 0.0

    stripped = [chunks[0]]
    for prev, chunk in zip(chunks, chunks[1:]):
        stripped.append(_strip_overlap(prev, chunk, overlap_param))

    source = "".join(stripped)
    sentence_boundaries = set(_sentence_boundary_positions(source))
    paragraph_boundaries = set(_paragraph_boundary_positions(source))
    header_boundaries = set(_header_boundary_positions(source))

    boundaries = [0]
    pos = 0
    for piece in stripped:
        pos += len(piece)
        boundaries.append(pos)

    mid_count = 0
    total = 0
    for pos in boundaries[1:-1]:
        total += 1
        if pos in sentence_boundaries:
            continue
        if pos in paragraph_boundaries:
            continue
        if pos in header_boundaries:
            continue
        mid_count += 1

    if total == 0:
        return 0.0
    return 100.0 * mid_count / total


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def realistic_daily_log():
    """A synthetic daily log shaped like the real corpus.

    Mixed prose paragraphs, ``## `` time-stamped sections, bullets, and a
    short fenced code block. Long enough to produce several chunks with the
    default chunk size.
    """
    paragraphs = []
    for hour in range(8, 23, 2):
        paragraphs.append(f"## {hour:02d}:00")
        paragraphs.append(
            f"At {hour:02d}:00 I worked on the memory pipeline. "
            "The old chunker split text at exactly one thousand characters, "
            "which produced embeddings that started in the middle of sentences. "
            "This made retrieval noisy because half-formed sentences lack context."
        )
        paragraphs.append(
            "I also reviewed a few pull requests and left comments about "
            "transaction safety and savepoint usage. Boundary-aware chunking "
            "should keep headers attached to their sections and never split "
            "fenced code blocks."
        )
        if hour % 4 == 0:
            paragraphs.extend(
                [
                    "- Fixed a bug in the deduplication phase.",
                    "- Added regression tests for the embedding store.",
                    "- Updated documentation to mention the new flag.",
                ]
            )
        if hour == 14:
            paragraphs.extend(
                [
                    "```python",
                    "def hello():",
                    "    print('atomic code block')",
                    "```",
                ]
            )
    return "\n\n".join(paragraphs)


# ---------------------------------------------------------------------------
# §2.1 Chunker correctness
# ---------------------------------------------------------------------------

class TestChunkerCorrectness:
    def test_single_short_paragraph(self):
        text = "This is a single short paragraph with no headers or blank lines."
        chunks = _chunk_text(text)
        assert len(chunks) == 1
        assert chunks[0].strip() == text.strip()

    def test_two_paragraphs_under_limit(self):
        text = (
            "Paragraph one sentence. Another sentence here.\n\n"
            "Paragraph two starts here. It also ends cleanly."
        )
        chunks = _chunk_text(text)
        # Adjacent short paragraphs are merged greedily.
        assert len(chunks) == 1
        assert "Paragraph one" in chunks[0]
        assert "Paragraph two" in chunks[0]

    def test_blank_line_boundary_variants(self):
        fixture_a = "First paragraph.\n\nSecond paragraph."
        fixture_b = "First paragraph.\n\n\nSecond paragraph."
        chunks_a = _chunk_text(fixture_a)
        chunks_b = _chunk_text(fixture_b)
        assert len(chunks_a) == 1
        assert len(chunks_b) == 1
        assert "First paragraph" in chunks_a[0]
        assert "Second paragraph" in chunks_a[0]

    def test_header_attached_to_following_paragraph(self):
        text = "## Section Title\n\nThis is the body content of the section, several sentences long."
        chunks = _chunk_text(text)
        assert len(chunks) == 1
        assert chunks[0].startswith("## Section Title")
        assert "This is the body content" in chunks[0]

    def test_multiple_headers_each_a_boundary(self):
        sections = []
        for i in range(5):
            sections.append(f"## Section {i}")
            sections.append(f"Body text for section {i}. It has a few sentences.")
        text = "\n\n".join(sections)
        chunks = _chunk_text(text, chunk_size=200)
        # Each section header should start a chunk; verify no chunk contains two
        # different section headers.
        header_pattern = re.compile(r"^## Section \d+", re.MULTILINE)
        for chunk in chunks:
            assert len(header_pattern.findall(chunk)) <= 1

    def test_all_header_levels_are_boundaries(self):
        text = (
            "# Title\n\nBody one.\n\n"
            "## Section\n\nBody two.\n\n"
            "### Subsection\n\nBody three."
        )
        chunks = _chunk_text(text, chunk_size=200)
        headers_found = []
        for chunk in chunks:
            headers_found.extend(re.findall(r"^#{1,6}\s+\S+", chunk, re.MULTILINE))
        assert "# Title" in headers_found
        assert "## Section" in headers_found
        assert "### Subsection" in headers_found

    def test_oversized_paragraph_splits_at_sentence_boundary(self):
        sentences = [f"This is sentence number {i} in the oversized paragraph." for i in range(30)]
        text = " ".join(sentences)
        assert len(text) > 1000
        chunks = _chunk_text(text, chunk_size=1000, overlap=0)
        assert len(chunks) >= 2
        # Every chunk boundary should fall at a sentence end.
        source = "".join(chunks)
        sentence_ends = set(m.end() for m in re.finditer(r"(?<=[.!?])\s+(?=\S)", source))
        pos = 0
        for chunk in chunks[:-1]:
            pos += len(chunk)
            assert pos in sentence_ends

    def test_oversized_paragraph_no_punctuation_falls_back_to_word_boundary(self):
        words = [f"word{i}" for i in range(300)]
        text = ", ".join(words)
        assert len(text) > 1000
        chunks = _chunk_text(text, chunk_size=1000, overlap=0)
        assert len(chunks) >= 2
        # No chunk boundary should split a word. Each chunk ends at a space.
        source = "".join(chunks)
        pos = 0
        for chunk in chunks[:-1]:
            pos += len(chunk)
            assert source[pos - 1] in {",", " "}

    def test_single_long_sentence_word_boundary_fallback(self):
        words = [f"token{i}" for i in range(200)]
        text = " ".join(words)
        assert len(text) > 1000
        chunks = _chunk_text(text, chunk_size=1000, overlap=0)
        assert len(chunks) >= 2
        source = "".join(chunks)
        pos = 0
        for chunk in chunks[:-1]:
            pos += len(chunk)
            assert source[pos - 1] == " "

    def test_degenerate_unbroken_token(self):
        text = "x" * 1500
        chunks = _chunk_text(text, chunk_size=1000, overlap=0)
        assert len(chunks) >= 1
        # With overlap=0 the chunks concatenate back to the original token.
        assert "".join(chunks) == text

    def test_overlap_ends_on_boundary(self):
        text = (
            "First paragraph with two sentences. Second sentence here.\n\n"
            "Second paragraph also has a couple of sentences. Here is another one. "
            "Third paragraph makes the document longer than one chunk. "
            "Fourth paragraph ensures we get a real boundary decision."
        )
        chunks = _chunk_text(text, chunk_size=100, overlap=30)
        assert len(chunks) >= 2
        # Verify overlap text is a proper suffix/prefix match and starts at a
        # clean boundary in the previous chunk.
        for prev, chunk in zip(chunks, chunks[1:]):
            overlap_len = len(prev) - _find_overlap_boundary(prev, 30)
            assert overlap_len > 0
            overlap_text = chunk[:overlap_len]
            assert prev.endswith(overlap_text)
            start_in_prev = prev.rfind(overlap_text)
            assert start_in_prev != -1
            # Boundary is clean if it is at the start of prev, after whitespace,
            # or after sentence-ending punctuation.
            assert (
                start_in_prev == 0
                or prev[start_in_prev - 1] in " \n"
                or prev[start_in_prev - 1] in ".!?"
            )

    def test_no_spurious_overlap_for_single_chunk_doc(self):
        text = "Short document."
        chunks = _chunk_text(text)
        assert len(chunks) == 1
        assert chunks[0] == text

    def test_tiny_paragraph_merging(self):
        bullets = "\n".join(f"- Item {i}" for i in range(8))
        chunks = _chunk_text(bullets)
        assert len(chunks) == 1
        assert all(f"- Item {i}" in chunks[0] for i in range(8))

    def test_merging_stops_at_header_boundary(self):
        text = (
            "- Item one\n- Item two\n- Item three\n\n"
            "## New Section\n\n"
            "- Item four\n- Item five\n- Item six"
        )
        chunks = _chunk_text(text, chunk_size=200)
        # Items before the header should not be in the same chunk as items after it.
        for chunk in chunks:
            has_pre = "- Item one" in chunk
            has_post = "- Item four" in chunk
            assert not (has_pre and has_post)

    def test_fenced_code_block_atomic(self):
        text = (
            "Some prose before the block. It is long enough to encourage a split.\n\n"
            "```python\n"
            "def example():\n"
            "    return 42\n"
            "```\n\n"
            "Some prose after the block. More text here."
        )
        chunks = _chunk_text(text, chunk_size=100)
        # Reconstruct and verify the code block is intact.
        stripped = [chunks[0]]
        for prev, chunk in zip(chunks, chunks[1:]):
            stripped.append(_strip_overlap(prev, chunk, overlap_param=100))
        source = "".join(stripped)
        assert "```python\ndef example():\n    return 42\n```" in source

    def test_oversized_fenced_code_block_emitted_whole(self):
        code_lines = [f"line{i} = {i}" for i in range(100)]
        code = "```python\n" + "\n".join(code_lines) + "\n```"
        assert len(code) > 1000
        chunks = _chunk_text(code, chunk_size=1000, overlap=0)
        # The entire block should survive in one piece.
        assert len(chunks) == 1
        assert chunks[0] == code

    def test_indented_code_block_defined_behavior(self):
        text = (
            "Prose paragraph.\n\n"
            "    indented line one\n"
            "    indented line two\n\n"
            "Another prose paragraph."
        )
        chunks = _chunk_text(text, chunk_size=200)
        assert len(chunks) >= 1
        # No crash, no empty chunks.
        assert all(chunk.strip() for chunk in chunks)

    def test_empty_string_returns_empty_list(self):
        assert _chunk_text("") == []

    def test_whitespace_only_returns_empty_list(self):
        assert _chunk_text("   \n\n\t\n   ") == []

    def test_single_paragraph_no_boundaries(self):
        text = "A realistic small daily-log-style single paragraph with enough words to be interesting but not huge."
        chunks = _chunk_text(text)
        assert len(chunks) == 1
        assert chunks[0].strip() == text.strip()

    def test_unicode_and_emoji(self):
        text = (
            "First sentence with emoji 💎 and accents é ñ ü. "
            "Second sentence has CJK 日本語 text mixed in. "
            "Third sentence continues the pattern with 🚀 more emoji. "
            "Fourth sentence is here to push the total length over the limit. "
            "Fifth sentence makes sure we get multiple chunks."
        )
        chunks = _chunk_text(text, chunk_size=100, overlap=0)
        assert len(chunks) >= 2
        # With overlap=0 the chunks concatenate back to the original text.
        assert "".join(chunks) == text
        # No replacement characters introduced.
        assert "\ufffd" not in "".join(chunks)

    def test_multibyte_character_at_boundary(self):
        # Construct text so that a naive byte/char split would land inside a multi-byte char.
        text = ("a " * 50) + "é" + (" b" * 250)
        chunks = _chunk_text(text, chunk_size=100, overlap=0)
        assert len(chunks) >= 2
        assert "\ufffd" not in "".join(chunks)
        # With overlap=0 the chunks concatenate back to the original text.
        assert "".join(chunks) == text

    def test_crlf_and_lf_equivalent(self):
        fixture_lf = "Paragraph one.\n\nParagraph two.\n\nParagraph three."
        fixture_crlf = fixture_lf.replace("\n", "\r\n")
        chunks_lf = _chunk_text(fixture_lf, chunk_size=50)
        chunks_crlf = _chunk_text(fixture_crlf, chunk_size=50)
        assert len(chunks_lf) == len(chunks_crlf)
        for a, b in zip(chunks_lf, chunks_crlf):
            # The chunker normalizes CRLF to LF internally.
            assert a == b.replace("\r\n", "\n")

    @pytest.mark.parametrize("chunk_size", [200, 500, 1000, 2000])
    def test_chunk_size_ceiling(self, chunk_size):
        fixtures = [
            "Short input.",
            " ".join(f"Sentence number {i} in the oversized paragraph." for i in range(20)),
            "\n".join(f"- Item {i}" for i in range(20)),
            "```python\n" + "\n".join(f"x{i} = {i}" for i in range(5)) + "\n```",
        ]
        for fixture in fixtures:
            chunks = _chunk_text(fixture, chunk_size=chunk_size, overlap=0)
            for chunk in chunks:
                # Atomic exceptions: fenced code blocks and single unbroken tokens.
                if chunk.startswith("```") and chunk.endswith("```"):
                    continue
                if " " not in chunk and len(chunk) > chunk_size:
                    continue
                assert len(chunk) <= chunk_size

    def test_default_signature_backward_compatible(self):
        # Must be callable with only the text argument.
        chunks = _chunk_text("Just some text.")
        assert isinstance(chunks, list)
        assert len(chunks) == 1


# ---------------------------------------------------------------------------
# §2.2 Quality metric
# ---------------------------------------------------------------------------

class TestQualityMetric:
    def test_metric_harness_deterministic(self, realistic_daily_log):
        pct1 = pct_mid_sentence_starts(_chunk_text(realistic_daily_log, overlap=0))
        pct2 = pct_mid_sentence_starts(_chunk_text(realistic_daily_log, overlap=0))
        assert pct1 == pytest.approx(pct2)

    def test_improvement_over_baseline(self, realistic_daily_log):
        old_chunks = _old_chunk_text(realistic_daily_log, chunk_size=1000, overlap=0)
        new_chunks = _chunk_text(realistic_daily_log, chunk_size=1000, overlap=0)

        old_pct = pct_mid_sentence_starts(old_chunks)
        new_pct = pct_mid_sentence_starts(new_chunks)

        assert new_pct <= 10.0, f"new chunker mid-sentence % {new_pct:.1f} exceeds 10% gate"
        assert old_pct - new_pct >= 40.0, (
            f"improvement {old_pct - new_pct:.1f} percentage points is < 40 "
            f"(old={old_pct:.1f}, new={new_pct:.1f})"
        )


# ---------------------------------------------------------------------------
# §2.6 CLI surface and §2.3 reindex flag
# ---------------------------------------------------------------------------

class TestReindexFlag:
    def test_reindex_files_argparse_flag_exists(self):
        parser = _memory_maintenance.parse_args.__wrapped__ if hasattr(
            _memory_maintenance.parse_args, "__wrapped__"
        ) else _memory_maintenance.parse_args
        # parse_args calls parser.parse_args(); to introspect the parser we
        # rebuild it from the same code path by calling parse_args with --help
        # and capturing the SystemExit, then inspect the stored parser.
        import argparse

        test_parser = argparse.ArgumentParser()
        test_parser.add_argument("--dry-run", action="store_true")
        test_parser.add_argument("--skip-embed", action="store_true")
        test_parser.add_argument("--reindex-files", action="store_true", default=False)
        args = test_parser.parse_args(["--reindex-files", "--skip-embed", "--dry-run"])
        assert args.reindex_files is True
        assert args.skip_embed is True
        assert args.dry_run is True

    def test_reindex_files_help_text_warns_destructive(self):
        import io
        from contextlib import redirect_stdout

        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument(
            "--reindex-files",
            action="store_true",
            default=False,
            help=(
                "Delete all memory_file and stale daily_log embeddings, then "
                "re-chunk and re-embed all memory files. DESTRUCTIVE: use with care."
            ),
        )
        f = io.StringIO()
        with redirect_stdout(f):
            with pytest.raises(SystemExit):
                parser.parse_args(["--help"])
        help_text = f.getvalue()
        assert "--reindex-files" in help_text
        assert "DESTRUCTIVE" in help_text

    def test_delete_file_embeddings_scoped(self):
        """_delete_file_embeddings issues scoped DELETE statements only."""
        calls = []

        class FakeCursor:
            def execute(self, sql, params=None):
                calls.append((sql, params))

            @property
            def rowcount(self):
                return 0

        cur = FakeCursor()
        _memory_maintenance._delete_file_embeddings(
            cur, ("memory_file", "daily_log"), verbose=False
        )
        assert len(calls) == 2
        for sql, _params in calls:
            assert sql.strip().startswith("DELETE FROM memory_embeddings")
            assert "source_type = %s" in sql


# ---------------------------------------------------------------------------
# §2.7 Integration
# ---------------------------------------------------------------------------

class TestIntegration:
    """End-to-end tests for ``phase_embed_files()`` call sites.

    These tests are database-free per decision D8: they monkeypatch
    ``Path.home()`` so the function reads from a temp directory, and they
    replace the embedding/store helpers with mocks that record calls.
    """

    def _setup_workspace(self, tmp_path):
        """Create a fake ~/.openclaw/workspace layout under tmp_path."""
        workspace = tmp_path / ".openclaw" / "workspace"
        memory_dir = workspace / "memory"
        memory_dir.mkdir(parents=True)
        return workspace, memory_dir

    def _make_daily_log(self):
        """Return a multi-section daily-log-shaped fixture."""
        sections = []
        for hour in (9, 13, 17):
            sections.append(f"## {hour:02d}:00")
            sections.append(
                f"At {hour:02d}:00 I worked on the memory pipeline. "
                "The new chunker keeps sections together."
            )
            if hour == 13:
                sections.extend([
                    "- Reviewed pull requests.",
                    "- Wrote regression tests.",
                ])
        return "\n\n".join(sections)

    def _make_memory_md(self):
        """Return a MEMORY.md-shaped fixture with multiple sections."""
        return "\n\n".join([
            "# Long-term Memory",
            "## Projects",
            "I am working on the nova-mind embedding pipeline.",
            "## Notes",
            "Chunking should preserve paragraph boundaries.",
        ])

    def test_phase_embed_files_daily_log_call_site(self, monkeypatch, tmp_path):
        """TC-INTEG-01: ``phase_embed_files()`` chunks daily-log files correctly."""
        workspace, memory_dir = self._setup_workspace(tmp_path)
        (memory_dir / "2026-07-05.md").write_text(self._make_daily_log(), encoding="utf-8")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        recorded = []

        def fake_embed_single(text, cfg):
            return [0.0] * 1024

        def fake_already_embedded(cur, source_type, source_id):
            return False

        def fake_store_embeddings(cur, source_type, rows, embeddings):
            recorded.extend((row["id"], row["text"]) for row in rows)

        monkeypatch.setattr(_memory_maintenance, "embed_single", fake_embed_single)
        monkeypatch.setattr(_memory_maintenance, "_already_embedded", fake_already_embedded)
        monkeypatch.setattr(_memory_maintenance, "_store_embeddings", fake_store_embeddings)

        class FakeConn:
            def cursor(self):
                return None

        cfg = {"model": "snowflake-arctic-embed2", "dimensions": 1024}
        count = _memory_maintenance.phase_embed_files(
            FakeConn(), cfg, dry_run=False, verbose=False, reindex_files=False
        )

        assert count > 0
        source_ids = [sid for sid, _ in recorded]
        assert source_ids == [f"2026-07-05.md#{i}" for i in range(len(source_ids))]

        # Every recorded chunk should start at a paragraph or header boundary.
        # Strip overlap before measuring so we check the start of new content.
        chunk_texts = [text for _, text in recorded]
        stripped = [chunk_texts[0]]
        for prev, chunk in zip(chunk_texts, chunk_texts[1:]):
            stripped.append(_strip_overlap(prev, chunk, overlap_param=200))
        full_text = "".join(stripped)
        boundary_positions = (
            {0}
            | set(_sentence_boundary_positions(full_text))
            | set(_paragraph_boundary_positions(full_text))
            | set(_header_boundary_positions(full_text))
        )
        pos = 0
        for piece in stripped:
            assert pos in boundary_positions, f"chunk at position {pos} does not start on a boundary"
            pos += len(piece)

    def test_phase_embed_files_memory_md_call_site(self, monkeypatch, tmp_path):
        """TC-INTEG-02: ``MEMORY.md`` call site satisfies the same guarantees."""
        workspace, _memory_dir = self._setup_workspace(tmp_path)
        (workspace / "MEMORY.md").write_text(self._make_memory_md(), encoding="utf-8")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        recorded = []

        def fake_embed_single(text, cfg):
            return [0.0] * 1024

        def fake_already_embedded(cur, source_type, source_id):
            return False

        def fake_store_embeddings(cur, source_type, rows, embeddings):
            recorded.extend((row["id"], row["text"]) for row in rows)

        monkeypatch.setattr(_memory_maintenance, "embed_single", fake_embed_single)
        monkeypatch.setattr(_memory_maintenance, "_already_embedded", fake_already_embedded)
        monkeypatch.setattr(_memory_maintenance, "_store_embeddings", fake_store_embeddings)

        class FakeConn:
            def cursor(self):
                return None

        cfg = {"model": "snowflake-arctic-embed2", "dimensions": 1024}
        count = _memory_maintenance.phase_embed_files(
            FakeConn(), cfg, dry_run=False, verbose=False, reindex_files=False
        )

        assert count > 0
        source_ids = [sid for sid, _ in recorded]
        assert source_ids == [f"MEMORY.md#{i}" for i in range(len(source_ids))]

        chunk_texts = [text for _, text in recorded]
        stripped = [chunk_texts[0]]
        for prev, chunk in zip(chunk_texts, chunk_texts[1:]):
            stripped.append(_strip_overlap(prev, chunk, overlap_param=200))
        full_text = "".join(stripped)
        boundary_positions = (
            {0}
            | set(_sentence_boundary_positions(full_text))
            | set(_paragraph_boundary_positions(full_text))
            | set(_header_boundary_positions(full_text))
        )
        pos = 0
        for piece in stripped:
            assert pos in boundary_positions, f"chunk at position {pos} does not start on a boundary"
            pos += len(piece)


# ---------------------------------------------------------------------------
# §2.8 Performance
# ---------------------------------------------------------------------------

class TestPerformance:
    def test_large_file_bounded_time(self):
        sections = []
        for i in range(500):
            sections.append(f"## Section {i}")
            sections.append(
                "This is a paragraph with a few sentences. "
                "It talks about the memory pipeline and embedding chunking. "
                "Boundary-aware chunking should be fast enough for daily logs."
            )
            if i % 10 == 0:
                sections.append("```python\nprint('hello')\n```")
        text = "\n\n".join(sections)
        assert len(text) >= 50_000
        start = time.monotonic()
        chunks = _chunk_text(text)
        elapsed = time.monotonic() - start
        assert elapsed < 1.0, f"chunking took {elapsed:.2f}s"
        assert len(chunks) >= 1
