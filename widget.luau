--!nonstrict
-- Cloudflare WARP - bar widget.
--
-- Presentation only: renders the phase SVG icon, a short status text and a
-- detail tooltip from the warp.status channel. Left click opens the panel,
-- right click writes a toggle command to warp.command. No CLI calls, no HTTP,
-- no bulk file reads: the only filesystem touch is a noctalia.fileExists()
-- probe for the phase SVG asset, run on every render, so a missing asset falls
-- back to a Tabler glyph instead of an empty bar.

local State = require("./lib/state.luau")
local Icons = require("./lib/icons.luau")

local showText = noctalia.getConfig("show_text_in_bar") ~= false
local compact = noctalia.getConfig("compact_mode") == true

local status = State.defaultStatus()
local svgFallbackLogged = false

local function render()
  local phase = status.phase
  local path = Icons.path(phase)
  local usingImage = false
  if noctalia.fileExists(path) then
    barWidget.setImage(path, false, 16, 16)
    usingImage = true
  elseif not svgFallbackLogged then
    -- One warning per entry lifetime; never spam the log on every change.
    svgFallbackLogged = true
    noctalia.log("cloudflare-warp: warn icon " .. path .. " not found, falling back to glyph")
  end
  if not usingImage then
    barWidget.setGlyph(Icons.glyph(phase))
  end
  local text = ""
  if showText and not compact then
    text = noctalia.tr("widget.text." .. Icons.textKey(phase))
  end
  barWidget.setText(text)
  barWidget.setTooltip(Icons.tooltipRows(status))
  barWidget.setVisible(true)
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
  noctalia.togglePanel("ModernByte/cloudflare-warp:panel")
end

function onRightClick()
  if status.busy == true then
    return
  end
  State.setCommand("toggle", { source = "widget" })
end

function update() end

applyStatus(noctalia.state.get(State.CHANNEL_STATUS) or State.defaultStatus())
noctalia.state.watch(State.CHANNEL_STATUS, applyStatus)
