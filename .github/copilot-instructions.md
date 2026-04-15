# Copilot Instructions For Balatro MCP

When asked to play Balatro in this repository, use the MCP tools instead of guessing.

Always follow this sequence:

1. Read the local strategy pack in `E:\BalatroLLM\strategy`
2. Call `get_game_state`
3. Call `list_legal_actions`
4. Choose exactly one legal action that matches the strategy pack
5. Execute that action with the most specific MCP tool available

Prefer these explicit MCP tools over the generic fallback:

- `continue_run`
- `choose_option`
- `choose_blind`
- `skip_choice`
- `select_card`
- `deselect_card`
- `play_hand`
- `discard_selected`
- `end_turn`
- `buy_item`
- `reroll_shop`
- `sell_joker`
- `use_consumable`

Decision rules:

- Survival first, then synergy, then economy
- Prefer reliable scoring over fragile high-roll lines
- When choosing `play_hand`, optimize exact `card_ids`, not just the hand type
- Do not assume you must play 5 cards; start with the minimum-card set that forms the intended hand
- If there are extra slots, use them only for cards you actively want to cycle out as disposable junk
- For pair, two pair, trips, and quads, preserve premium side cards and use low future-value throwaways in extra slots
- Preserve A/K/Q/J and strong straight or flush connectors unless they are required for the hand or clearly needed to survive this turn
- Do not invent actions that are not present in `list_legal_actions`
- Keep reasoning short
- If the user asks for analysis, state the chosen legal action before executing
- If the user asks you to play, execute the chosen legal action directly
