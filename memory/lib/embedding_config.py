"""Shared embedding-config loader for Python scripts.

Reads nova-mind's embedding-config.json (provider, model, base_url, dimensions)
from ~/.openclaw/scripts/embedding-config.json. Missing or invalid config is a
loud failure; there is no silent default model.

Issue: nova-mind #781
"""

import json
import os
from pathlib import Path

DEFAULT_EMBEDDING_CONFIG_PATH = os.path.join(
    os.path.expanduser("~"), ".openclaw", "scripts", "embedding-config.json"
)

REQUIRED_KEYS = ("provider", "model", "base_url", "dimensions")


class EmbeddingConfigError(Exception):
    """Raised when embedding-config.json is missing or invalid."""

    pass


def load_embedding_config(config_path=None):
    """Load embedding configuration.

    Args:
        config_path: Optional override. If omitted, the path is taken from the
            EMBEDDING_CONFIG_PATH_OVERRIDE environment variable (test hook) or
            falls back to ~/.openclaw/scripts/embedding-config.json.

    Returns:
        dict with keys provider, model, base_url, dimensions.

    Raises:
        EmbeddingConfigError: if the config is missing or invalid.
    """
    if config_path is None:
        config_path = os.environ.get(
            "EMBEDDING_CONFIG_PATH_OVERRIDE", DEFAULT_EMBEDDING_CONFIG_PATH
        )

    config_path = Path(config_path)
    if not config_path.exists():
        raise EmbeddingConfigError(f"Embedding config not found: {config_path}")

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            raw = f.read()
    except OSError as e:
        raise EmbeddingConfigError(
            f"Cannot read embedding config {config_path}: {e}"
        ) from e

    try:
        config = json.loads(raw)
    except json.JSONDecodeError as e:
        raise EmbeddingConfigError(
            f"Invalid JSON in embedding config {config_path}: {e}"
        ) from e

    if not isinstance(config, dict):
        raise EmbeddingConfigError(
            f"Embedding config must be a JSON object: {config_path}"
        )

    missing = [k for k in REQUIRED_KEYS if k not in config]
    if missing:
        raise EmbeddingConfigError(
            f"Embedding config missing required keys {missing}: {config_path}"
        )

    if (
        not isinstance(config["dimensions"], int)
        or config["dimensions"] <= 0
    ):
        raise EmbeddingConfigError(
            f"Embedding config 'dimensions' must be a positive integer: {config_path}"
        )

    return config
