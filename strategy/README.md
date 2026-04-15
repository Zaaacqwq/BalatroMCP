# Balatro Strategy Pack

This directory contains a portable strategy layer for Balatro-focused LLM agents.

Goal:

- Keep strategy outside the model so it works across devices and across LLMs.
- Make decisions more stable than a free-form prompt.
- Separate factual game knowledge from policy/inference.

Recommended usage:

1. Load `BALATRO_STRATEGY_SPEC.md` as the main strategy reference.
2. Load `llm_decision_template.md` as the decision procedure.
3. Load the relevant entries from `deck_profiles.yaml` and `stake_adjustments.yaml`.
4. Optionally load `shop_policy.yaml` for shop-specific turns.

Suggested integration pattern:

- On each turn, call `get_game_state`.
- Call `list_legal_actions`.
- Detect current context:
  - deck
  - stake
  - phase
  - ante
  - blind
  - money
  - joker lineup
  - consumables
- Inject only the relevant strategy fragments into the model prompt.
- Ask the model to choose exactly one legal action and explain it briefly.

This pack is model-agnostic:

- No fine-tuning required
- No device-specific memory required
- Easy to version and update in git

Primary factual references used when authoring this pack:

- https://balatrogame.fandom.com/wiki/Balatro_Wiki
- https://balatrogame.fandom.com/wiki/Jokers
- https://balatrogame.fandom.com/wiki/Decks
- https://balatrogame.fandom.com/wiki/Poker_Hands
- https://balatrogame.fandom.com/wiki/Card_Modifiers
- https://balatrogame.fandom.com/wiki/The_Shop
- https://balatrogame.fandom.com/wiki/Stakes
- https://balatrogame.fandom.com/wiki/Blinds_and_Antes
- https://balatrogame.fandom.com/wiki/Tags
- https://balatrogame.fandom.com/wiki/Tarot_Cards
- https://balatrogame.fandom.com/wiki/Planet_Cards
- https://balatrogame.fandom.com/wiki/Spectral_Cards
- https://balatrogame.fandom.com/wiki/Vouchers
- https://balatrogame.fandom.com/wiki/Booster_Packs
