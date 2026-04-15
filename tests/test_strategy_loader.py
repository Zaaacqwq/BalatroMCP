from __future__ import annotations

from balatro_mcp.agent.strategy_loader import build_turn_prompt, load_strategy_context


def test_load_strategy_context_detects_deck_and_stake() -> None:
    state = {
        "phase": "shop",
        "deck": {"name": "Checkered Deck"},
        "stake": {"name": "Blue Stake"},
    }

    context = load_strategy_context(state)

    assert context.deck == "checkered"
    assert context.stake == "blue"
    assert context.deck_excerpt is not None
    assert "checkered" in context.deck_excerpt.lower()
    assert context.stake_excerpt is not None
    assert "blue" in context.stake_excerpt.lower()
    assert context.shop_excerpt is not None


def test_build_turn_prompt_mentions_strategy_and_state() -> None:
    state = {
        "phase": "in_round",
        "resources": {"money": 4},
        "meta": {"stake_name": "White Stake"},
    }
    legal = [{"action_type": "play_hand"}, {"action_type": "discard_selected"}]

    prompt = build_turn_prompt(state, legal)

    assert "Do not start free-playing from intuition." in prompt
    assert '"action_type": "play_hand"' in prompt
    assert '"detected_stake": "white"' in prompt
