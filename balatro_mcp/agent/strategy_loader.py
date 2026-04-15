from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import re
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
STRATEGY_DIR = REPO_ROOT / "strategy"


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _extract_yaml_block(text: str, root_key: str, entry_key: str) -> str | None:
    root_match = re.search(rf"(?ms)^{re.escape(root_key)}:\n(?P<body>.+)$", text)
    if not root_match:
        return None

    body = root_match.group("body")
    entry_match = re.search(
        rf"(?ms)^  {re.escape(entry_key)}:\n(?P<entry>(?:^    .*\n?)*)",
        body,
    )
    if not entry_match:
        return None

    return f"{root_key}:\n  {entry_key}:\n{entry_match.group('entry').rstrip()}\n"


def _find_first_string(value: Any, candidates: set[str]) -> str | None:
    if isinstance(value, str):
        normalized = value.strip().lower().replace(" ", "_")
        if normalized in candidates:
            return normalized
        for candidate in sorted(candidates, key=len, reverse=True):
            if candidate in normalized:
                return candidate
        return None

    if isinstance(value, dict):
        for item in value.values():
            found = _find_first_string(item, candidates)
            if found:
                return found
        return None

    if isinstance(value, list):
        for item in value:
            found = _find_first_string(item, candidates)
            if found:
                return found
        return None

    return None


@dataclass
class StrategyContext:
    deck: str | None
    stake: str | None
    core_spec: str
    decision_template: str
    deck_excerpt: str | None
    stake_excerpt: str | None
    shop_excerpt: str | None

    def as_prompt_sections(self) -> str:
        sections = [
            "# Strategy Files",
            "## Core Spec",
            self.core_spec.strip(),
            "",
            "## Decision Template",
            self.decision_template.strip(),
        ]

        if self.deck_excerpt:
            sections.extend(["", "## Deck Profile", self.deck_excerpt.strip()])
        if self.stake_excerpt:
            sections.extend(["", "## Stake Adjustment", self.stake_excerpt.strip()])
        if self.shop_excerpt:
            sections.extend(["", "## Shop Policy", self.shop_excerpt.strip()])

        return "\n".join(sections).strip() + "\n"


def detect_deck_name(game_state: dict[str, Any]) -> str | None:
    known = {
        "red",
        "blue",
        "yellow",
        "green",
        "black",
        "magic",
        "nebula",
        "ghost",
        "abandoned",
        "checkered",
        "zodiac",
        "painted",
        "anaglyph",
        "plasma",
        "erratic",
    }
    candidates: list[Any] = [
        game_state.get("deck"),
        game_state.get("deck_name"),
        (game_state.get("meta") or {}).get("deck"),
        (game_state.get("meta") or {}).get("deck_name"),
    ]
    for candidate_value in candidates:
        found = _find_first_string(candidate_value, known)
        if found:
            return found
    return None


def detect_stake_name(game_state: dict[str, Any]) -> str | None:
    known = {"white", "red", "green", "black", "blue", "purple", "orange", "gold"}
    candidates: list[Any] = [
        game_state.get("stake"),
        game_state.get("stake_name"),
        (game_state.get("meta") or {}).get("stake"),
        (game_state.get("meta") or {}).get("stake_name"),
    ]
    for candidate_value in candidates:
        found = _find_first_string(candidate_value, known)
        if found:
            return found
    return None


def load_strategy_context(game_state: dict[str, Any]) -> StrategyContext:
    core_spec = _read_text(STRATEGY_DIR / "BALATRO_STRATEGY_SPEC.md")
    decision_template = _read_text(STRATEGY_DIR / "llm_decision_template.md")
    decks_text = _read_text(STRATEGY_DIR / "deck_profiles.yaml")
    stakes_text = _read_text(STRATEGY_DIR / "stake_adjustments.yaml")
    shop_text = _read_text(STRATEGY_DIR / "shop_policy.yaml")

    deck = detect_deck_name(game_state)
    stake = detect_stake_name(game_state)

    deck_excerpt = _extract_yaml_block(decks_text, "decks", deck) if deck else None
    stake_excerpt = _extract_yaml_block(stakes_text, "stakes", stake) if stake else None
    shop_excerpt = shop_text if game_state.get("phase") == "shop" else None

    return StrategyContext(
        deck=deck,
        stake=stake,
        core_spec=core_spec,
        decision_template=decision_template,
        deck_excerpt=deck_excerpt,
        stake_excerpt=stake_excerpt,
        shop_excerpt=shop_excerpt,
    )


def build_turn_prompt(game_state: dict[str, Any], legal_actions: list[dict[str, Any]]) -> str:
    context = load_strategy_context(game_state)
    payload = {
        "game_state": game_state,
        "legal_actions": legal_actions,
        "detected_deck": context.deck or "unknown",
        "detected_stake": context.stake or "unknown",
    }

    return (
        "You are a Balatro strategy agent.\n"
        "Do not start free-playing from intuition.\n"
        "Read the supplied strategy files first, then choose exactly one legal action.\n\n"
        f"{context.as_prompt_sections()}\n"
        "# Current Turn\n"
        f"{json.dumps(payload, ensure_ascii=False, indent=2)}\n\n"
        "Return JSON only using the schema in the decision template.\n"
    )
