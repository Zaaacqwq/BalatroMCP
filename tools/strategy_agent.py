from __future__ import annotations

import argparse
import json
import urllib.request
from typing import Any

from balatro_mcp.agent.strategy_loader import build_turn_prompt, load_strategy_context


MOD_URL = "http://127.0.0.1:12346"
MCP_URL = f"{MOD_URL}/mcp/call"


def post_json(url: str, payload: dict[str, Any], timeout_s: float = 15.0) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        return json.loads(resp.read().decode("utf-8"))


def mcp_call(name: str, arguments: dict[str, Any]) -> Any:
    return post_json(MCP_URL, {"name": name, "arguments": arguments}).get("content")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a strategy-first prompt packet for Balatro LLM agents."
    )
    parser.add_argument(
        "--format",
        choices=["prompt", "json"],
        default="prompt",
        help="Render a full prompt or a structured JSON packet.",
    )
    args = parser.parse_args()

    game_state = mcp_call("get_game_state", {})
    legal_actions = mcp_call("list_legal_actions", {})
    context = load_strategy_context(game_state)

    if args.format == "json":
        packet = {
            "detected_deck": context.deck,
            "detected_stake": context.stake,
            "strategy_files": {
                "core_spec": context.core_spec,
                "decision_template": context.decision_template,
                "deck_excerpt": context.deck_excerpt,
                "stake_excerpt": context.stake_excerpt,
                "shop_excerpt": context.shop_excerpt,
            },
            "game_state": game_state,
            "legal_actions": legal_actions,
        }
        print(json.dumps(packet, ensure_ascii=False, indent=2))
        return

    print(build_turn_prompt(game_state, legal_actions))


if __name__ == "__main__":
    main()
