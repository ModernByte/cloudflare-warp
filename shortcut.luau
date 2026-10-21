--!nonstrict
-- Cloudflare WARP - Control Center tile.
--
-- Live tile bound to warp.status: label, active state and enabled state
-- track the current phase; clicks write toggle/refresh commands to
-- warp.command. shortcut.setIcon accepts glyph names only, so the tile uses
-- Tabler glyphs while the bar shows phase SVG icons.

local State = require("./lib/state.luau")
local Icons = require("./lib/icons.luau")

local status = State.defaultStatus()

local function render()
  local phase = status.phase
  shortcut.setLabel(noctalia.tr("shortcut." .. Icons.textKey(phase)))
  shortcut.setIcon("cloud-lock", "cloud-off")
  shortcut.setActive(phase == "connected" or phase == "connecting")
  shortcut.setEnabled(status.available == true and status.busy ~= true)
end

local function applyStatus(value)
  if type(value) ~= "table" then
    return
  end
  status = value
  status.phase = Icons.normalizePhase(status.phase)
  render()
end

function onClick()
  if status.busy == true then
    return
  end
  State.setCommand("toggle", { source = "shortcut" })
end

function onRightClick()
  State.setCommand("refresh", { source = "shortcut" })
end

applyStatus(noctalia.state.get(State.CHANNEL_STATUS) or State.defaultStatus())
noctalia.state.watch(State.CHANNEL_STATUS, applyStatus)
