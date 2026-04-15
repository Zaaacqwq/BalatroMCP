-- SMODS hook template for wiring Balatro runtime calls to balatro-mcp mod.
-- Replace event names and binding functions with actual SMODS API hooks in your setup.

local mcp_mod = require("bmcp.main")

local M = {}

function M.on_mod_loaded()
  mcp_mod.init()
end

function M.on_update_tick()
  mcp_mod.tick()
end

function M.on_round_started()
  -- Optional: emit custom event or force snapshot.
end

function M.on_shop_entered()
  -- Optional: emit custom event or force snapshot.
end

function M.on_game_over()
  -- Optional: emit custom event or flush logs.
end

return M
