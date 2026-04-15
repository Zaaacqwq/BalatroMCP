"""Entry point for `balatro-mcp` console script (uv / pip install)."""
import asyncio
import sys
import os

# Allow running as `uv run balatro-mcp` from the repo root even when the
# package is not installed: add the repo root to sys.path.
_here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _here not in sys.path:
    sys.path.insert(0, _here)

from balatro_mcp_stdio import main as _async_main  # noqa: E402


def main() -> None:
    asyncio.run(_async_main())
