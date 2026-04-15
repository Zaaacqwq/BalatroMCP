# Agent Start Prompt

Use this as the fixed startup instruction for Codex, Claude, Copilot, or any other LLM client that will play Balatro through MCP.

```text
When I ask you to play Balatro, do not act immediately.

First load the local strategy pack from:
E:\BalatroLLM\strategy

Required files:
- E:\BalatroLLM\strategy\BALATRO_STRATEGY_SPEC.md
- E:\BalatroLLM\strategy\llm_decision_template.md
- E:\BalatroLLM\strategy\deck_profiles.yaml
- E:\BalatroLLM\strategy\stake_adjustments.yaml
- E:\BalatroLLM\strategy\shop_policy.yaml

Then call:
1. get_game_state
2. list_legal_actions

Then choose exactly one legal action according to the strategy pack.

Prefer the most specific MCP tool for execution:
- continue_run
- choose_option
- choose_blind
- skip_choice
- select_card
- deselect_card
- play_hand
- discard_selected
- end_turn
- buy_item
- reroll_shop
- sell_joker
- use_consumable

Rules:
- Do not free-play from intuition if the strategy pack covers the case.
- Prefer survival first, then synergy, then economy.
- When playing a hand, choose exact `card_ids` carefully; do not default to spending high kickers on weak pair lines.
- Do not assume you must play 5 cards; start from the minimum-card scoring core.
- If extra slots remain, fill them only with low-value cards you want to cycle out.
- For pair / two pair / trips / quads, preserve high cards and useful connectors when lower-value throwaways can occupy the non-scoring slots.
- Keep reasoning short.
- Return the chosen legal action before executing it when I ask for analysis.
- Execute the chosen legal action directly when I ask you to play.
```

If you want a ready-made prompt packet for the current turn, run:

```powershell
E:\BalatroLLM\.venv\Scripts\python.exe E:\BalatroLLM\tools\strategy_agent.py
```
