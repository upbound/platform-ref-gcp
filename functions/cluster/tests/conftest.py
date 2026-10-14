"""Make the generated models importable during tests.

`up project build` generates them into .up/python at the repository root, and installs them into
the function's environment when it builds the function. Tests run outside that environment, so the
generated tree goes on sys.path directly.
"""

import sys
from pathlib import Path

import pytest

_MODELS = Path(__file__).resolve().parents[3] / ".up" / "python"

if not _MODELS.is_dir():
    # Fail here, before collection, with something more useful than a ModuleNotFoundError.
    raise pytest.UsageError(
        f"generated models not found at {_MODELS}; generate them with `up project build`"
    )

sys.path.insert(0, str(_MODELS))
