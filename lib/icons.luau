--!nonstrict
-- Cloudflare WARP - shared icon and label mapping for UI entries.
--
-- Single source of truth for phase -> SVG path / Tabler glyph / text suffix,
-- plus the bar tooltip rows and the phase color role.
-- Shared by widget.luau, shortcut.luau and panel.luau; never writes state.

local State = require("./state.luau")

local M = {}

local KNOWN_PHASES = {}
for _, phase in ipairs(State.PHASES) do
  KNOWN_PHASES[phase] = true
end

-- SVG assets, relative to the plugin directory (the host resolves relative
-- image paths against it, and noctalia.fileExists resolves them the same way).
local SVG = {
  connected = "assets/icons/warp-on.svg",
  disconnected = "assets/icons/warp-off.svg",
  connecting = "assets/icons/warp-connecting.svg",
  disconnecting = "assets/icons/warp-connecting.svg",
  unregistered = "assets/icons/warp-warn.svg",
  error = "assets/icons/warp-error.svg",
  unavailable = "assets/icons/warp-error.svg",
  unknown = "assets/icons/warp-off.svg",
}

-- Tabler glyph fallback for surfaces without SVG support (bar fallback and
-- Control Center, where shortcut.setIcon accepts glyph names only).
local GLYPH = {
  connected = "cloud-lock",
  disconnected = "cloud-off",
  connecting = "cloud",
  disconnecting = "cloud",
  unregistered = "cloud",
  error = "cloud-off",
  unavailable = "cloud-off",
  unknown = "cloud-off",
}

-- Short bar text / shortcut label suffix; callers prefix their own namespace
-- ("widget.text." / "shortcut.").
local TEXT = {
  connected = "on",
  disconnected = "off",
  connecting = "connecting",
  disconnecting = "connecting",
  unregistered = "register",
  error = "error",
  unavailable = "error",
  unknown = "unknown",
}

-- normalizePhase: map any unexpected value to "unknown" so every consumer
-- works with the closed phase set from state.luau.
function M.normalizePhase(phase: any): string
  if type(phase) == "string" and KNOWN_PHASES[phase] then
    return phase
  end
  return "unknown"
end

-- path: SVG asset for a phase; always a string (unknown maps to warp-off).
function M.path(phase: any): string
  return SVG[M.normalizePhase(phase)]
end

-- glyph: Tabler glyph for a phase (fallback / Control Center).
function M.glyph(phase: any): string
  return GLYPH[M.normalizePhase(phase)]
end

-- phaseColor: palette role for phase-colored text: connected
-- reads as success, error/unavailable as error, everything else as primary.
function M.phaseColor(phase: any): string
  local normalized = M.normalizePhase(phase)
  if normalized == "connected" then
    return "success"
  end
  if normalized == "error" or normalized == "unavailable" then
    return "error"
  end
  return "primary"
end

-- textKey: translation suffix for a phase ("on", "connecting", ...).
function M.textKey(phase: any): string
  return TEXT[M.normalizePhase(phase)]
end

-- tooltipRows: bar tooltip as an array of { key, value } rows.
-- status, mode, families (only when known), protocol, ip, location,
-- updated time and the last error message/errorCode.
--
-- i18n policy for tooltip values: raw CLI tokens (mode / families /
-- errorCode) are never user-facing text, so known tokens are translated via
-- the shared mode.* / families.* / error.* keys; unknown tokens are shown
-- as-is instead of risking a raw translation key. Protocol names are brand
-- labels (same in every language), presented capitalized like the panel.
local MODE_KEYS = {
  warp = true,
  doh = true,
  ["warp+doh"] = true,
  dot = true,
  ["warp+dot"] = true,
  proxy = true,
  tunnel_only = true,
}
local FAMILIES_KEYS = { off = true, malware = true, full = true }
local PROTOCOL_LABELS = { wireguard = "WireGuard", masque = "MASQUE" }

function M.tooltipRows(status: any): { { key: string, value: string } }
  local rows = {}
  local ok = type(status) == "table"
  local phase = M.normalizePhase(ok and status.phase or nil)
  table.insert(rows, {
    key = noctalia.tr("widget.tooltip.status"),
    value = noctalia.tr("status." .. phase),
  })
  if ok then
    if type(status.mode) == "string" and status.mode ~= "" then
      local modeLabel = if MODE_KEYS[status.mode] then noctalia.tr("mode." .. status.mode) else status.mode
      table.insert(rows, { key = noctalia.tr("widget.tooltip.mode"), value = modeLabel })
    end
    if type(status.families) == "string" and status.families ~= "" and status.families ~= "unknown" then
      local familiesLabel = if FAMILIES_KEYS[status.families]
        then noctalia.tr("families." .. status.families)
        else status.families
      table.insert(rows, { key = noctalia.tr("widget.tooltip.families"), value = familiesLabel })
    end
    if type(status.protocol) == "string" and status.protocol ~= "" and status.protocol ~= "unknown" then
      table.insert(rows, {
        key = noctalia.tr("widget.tooltip.protocol"),
        value = PROTOCOL_LABELS[status.protocol] or status.protocol,
      })
    end
    local trace = type(status.trace) == "table" and status.trace or {}
    if type(trace.ip) == "string" and trace.ip ~= "" then
      table.insert(rows, { key = noctalia.tr("widget.tooltip.ip"), value = trace.ip })
    end
    if type(trace.loc) == "string" and trace.loc ~= "" then
      table.insert(rows, { key = noctalia.tr("widget.tooltip.location"), value = trace.loc })
    end
    local updatedAtMs = tonumber(status.updatedAtMs) or 0
    if updatedAtMs > 0 then
      table.insert(rows, {
        key = noctalia.tr("widget.tooltip.updated"),
        value = noctalia.formatTime("%H:%M", math.floor(updatedAtMs / 1000)),
      })
    end
    local message = type(status.message) == "string" and status.message or ""
    local errorCode = type(status.errorCode) == "string" and status.errorCode or ""
    if message ~= "" or errorCode ~= "" then
      -- Prefer the translated error text over a raw errorCode; the closed
      -- service-side code set guarantees the key exists in en/ru.
      local errorLabel = if errorCode ~= ""
        then noctalia.tr("error." .. errorCode)
        else message
      table.insert(rows, {
        key = noctalia.tr("widget.tooltip.error"),
        value = errorLabel,
      })
    end
  end
  return rows
end

return M