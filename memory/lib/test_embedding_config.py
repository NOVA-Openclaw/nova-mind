"""Tests for embedding_config shared loader.

Issue: nova-mind #781
"""

import json
import os
import tempfile
from pathlib import Path

import pytest

from embedding_config import load_embedding_config, EmbeddingConfigError


@pytest.fixture
def temp_config():
    tmpdir = tempfile.mkdtemp()
    path = Path(tmpdir) / "embedding-config.json"
    yield path
    os.environ.pop("EMBEDDING_CONFIG_PATH_OVERRIDE", None)


def test_loads_model_from_valid_config(temp_config):
    data = {
        "provider": "ollama",
        "model": "snowflake-arctic-embed2",
        "base_url": "http://localhost:11434",
        "dimensions": 1024,
    }
    temp_config.write_text(json.dumps(data))
    os.environ["EMBEDDING_CONFIG_PATH_OVERRIDE"] = str(temp_config)

    cfg = load_embedding_config()
    assert cfg["model"] == "snowflake-arctic-embed2"
    assert cfg["base_url"] == "http://localhost:11434"
    assert cfg["dimensions"] == 1024


def test_missing_config_errors(temp_config):
    os.environ["EMBEDDING_CONFIG_PATH_OVERRIDE"] = str(temp_config)
    with pytest.raises(EmbeddingConfigError, match="Embedding config not found"):
        load_embedding_config()


def test_invalid_json_errors(temp_config):
    temp_config.write_text("{not valid json")
    os.environ["EMBEDDING_CONFIG_PATH_OVERRIDE"] = str(temp_config)
    with pytest.raises(EmbeddingConfigError, match="Invalid JSON"):
        load_embedding_config()


def test_missing_required_key_errors(temp_config):
    data = {
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        "dimensions": 1024,
    }
    temp_config.write_text(json.dumps(data))
    os.environ["EMBEDDING_CONFIG_PATH_OVERRIDE"] = str(temp_config)
    with pytest.raises(EmbeddingConfigError, match="missing required keys"):
        load_embedding_config()


def test_non_positive_dimensions_errors(temp_config):
    data = {
        "provider": "ollama",
        "model": "snowflake-arctic-embed2",
        "base_url": "http://localhost:11434",
        "dimensions": 0,
    }
    temp_config.write_text(json.dumps(data))
    os.environ["EMBEDDING_CONFIG_PATH_OVERRIDE"] = str(temp_config)
    with pytest.raises(EmbeddingConfigError, match="positive integer"):
        load_embedding_config()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
