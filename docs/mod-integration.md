# Mod Integration (SMODS/Lua)

## Status

Current `mod/` code is an integration scaffold, not a final game-hook implementation.
It now includes real relay protocol wiring, cadence controls, and adapter-based execution.

## Runtime Flow

1. `mod/main.lua` heartbeat on init.
2. On each safe tick:
   - Check `sync_controller.can_control()`.
   - Extract normalized state via `state_extractor.extract_game_state()`.
   - Push snapshot to bridge `/bridge/mod/snapshot`.
   - Poll `/bridge/mod/next_command`.
   - Handle control command types: `pause_control`, `resume_control`, `request_snapshot`.
   - Execute action for `execute_action` commands via `action_executor.execute()`.
   - Push result to `/bridge/mod/command_result`.

## Files

- `mod/main.lua`
- `mod/bridge_client.lua`
- `mod/state_extractor.lua`
- `mod/action_executor.lua`
- `mod/event_emitter.lua`
- `mod/sync_controller.lua`
- `mod/config.lua`
- `mod/adapter.lua`
- `mod/default_adapter.lua`
- `mod/balatro_adapter.lua`
- `mod/json_util.lua`
- `mod/smods_hooks_template.lua`

## Hook Points To Implement In Balatro

- Round enter/exit
- Shop enter/exit
- Pack choice
- Hand selection changes
- Hand played
- Discard executed
- Game over

## Required Replacements

1. Replace `bridge_client.lua` placeholder HTTP functions with actual Lua HTTP client calls.
2. Verify `socket.http` and JSON lib availability in your SMODS runtime (`cjson` or `dkjson`).
3. Replace `state_extractor.lua` adapter reads with real runtime extraction mapped to `schemas/game_state.schema.json`.
4. Implement a real adapter module for game actions and inject it via `main.set_adapter()`.
5. Add animation/modal lock checks in `sync_controller.lua` to avoid invalid timing.
6. Wire `smods_hooks_template.lua` to real hook events from your SMODS setup.

## Current Completion Checklist

- Bridge relay path: complete
- Mod command polling and result push: complete
- Adapter interface and default implementation: complete
- Tick cadence / heartbeat controls: complete
- Real Balatro runtime hooks: pending
- Real Balatro action calls: pending

## Adapter Wiring Example

```lua
local main = require("mod.main")
local balatro_adapter = require("mod.balatro_adapter")

main.init()
main.set_adapter(balatro_adapter)
```

## Safety Rules

- Execute only whitelisted action types.
- Reject unknown actions and malformed payloads.
- Return structured result `{success, error, warnings}`.
- Keep phase lock strict during animations and score settlement.

## Relay Command Envelope

Commands from bridge are now shaped as:

```json
{
   "command_id": "uuid",
   "command_type": "execute_action|pause_control|resume_control|request_snapshot",
   "payload": { "action": {"action_type": "...", "params": {}} },
   "created_at": 0.0
}
```
