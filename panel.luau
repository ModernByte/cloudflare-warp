--!nonstrict
-- Cloudflare WARP - detail panel.
--
-- Renderer plus command writer: every action goes through warp.command via
-- State.setCommand(source = "panel"). This entry never runs CLI calls, never
-- touches the network and never writes warp.status; the tree re-renders on
-- state changes while the panel is open.
--
-- The banner is a 27-frame sequence derived from the source animation, stopping
-- three frames before the GIF end. The host cannot animate GIFs or tint
-- declarative images, so each frame carries a baked saturation ramp (frame 0 =
-- 20% color, 26 = full color) and a bottom alpha fade into the panel body.
-- Opening the panel with a live tunnel (or connecting) plays 0 -> 26;
-- disconnecting plays 26 -> 0 in reverse. Opening while off shows the frame 0
-- state without animating, so the banner always matches the phase.
--
-- The host owns the panel size and adds a fixed 14 px padding around plugin
-- content. The root cancels that inset horizontally so the inner 16 px gutter
-- is the only side padding; the banner wrapper pulls the top inset and the
-- panel height is tuned to the tallest regular state (no scroll).

local State = require("./lib/state.luau")
local Icons = require("./lib/icons.luau")

-- Fixed orderings shared by the selects; commands carry the canonical
-- lowercase values the service whitelists.
local MODE_ORDER = { "warp", "doh", "warp+doh", "dot", "warp+dot", "proxy", "tunnel_only" }
local PROTOCOL_ORDER = { "wireguard", "masque" }
local FAMILIES_ORDER = { "off", "malware", "full" }
local FAMILIES_DEFAULT = "malware"

-- Visual tokens.
local BRAND_ORANGE = "#F6821F"
local EMBER = "#C75B43"
local CYAN = "#59D6FF"
local SUCCESS = "#3BE3A3"

-- Phase presentation: the one loud accent shared by the hero card.
local PHASE_ACCENT = {
  connected = SUCCESS,
  disconnected = EMBER,
  connecting = CYAN,
  disconnecting = CYAN,
  unregistered = "#FFB340",
  error = "#FF5C6C",
  unavailable = "#FF5C6C",
  unknown = "#8A93A6",
}

local COPY_FEEDBACK_MS = 1600
local REFRESH_FEEDBACK_MS = 1500
local IP_DISPLAY_MAX = 28

-- Geometry shared with plugin.toml: the host wraps content in a scaled
-- Style::panelPadding on every side, so the banner compensates with negative
-- padding to reach the panel edges.
local PANEL_WIDTH = 400
local HOST_PADDING = 14
local BANNER_HEIGHT = 160
local BANNER_WRAP_HEIGHT = BANNER_HEIGHT - HOST_PADDING
local BANNER_RADIUS = 12

-- Banner frame sequence (assets/banner/frame-XX.webp).
-- The sequence ends three frames early by design; the baked saturation
-- ramp still reaches full color on the final used frame.
local BANNER_FRAME_COUNT = 27
local BANNER_FRAME_MS = 100 -- native GIF delay, 10 ticks per frame
-- Each frame also has a baked bottom alpha fade so the banner blends into the panel.

-- Animation timing (milliseconds).
local FRAME_STEP_MS = 33
local ENTRANCE_MS = 420
local ACCENT_TAU_MS = 140
local HOVER_TAU_MS = 70
local WAVE_PERIOD_MS = 900

local status = State.defaultStatus()
local isOpen = false
local copiedUntilMs = 0
local refreshUntilMs = 0
-- Animated presentation state: phase accent, banner frame/direction, hover
-- easing and the one-shot entrance progress.
local accentR, accentG, accentB = 138, 147, 166
local bannerFrame = 0
local bannerAnimDir = 0 -- +1 forward, -1 reverse, 0 static
local bannerAnimAccMs = 0
local entranceT = 1
local hoverCurrent = { off = 0, malware = 0, full = 0 }
local hoverTarget = { off = 0, malware = 0, full = 0 }
local frameAccMs = 0
local frameTicksOn = false

local render -- forward declaration: callbacks below re-render after local actions.
local wakeAnimation

local function isConnectedLike(phase)
  return phase == "connected" or phase == "connecting"
end

-- The forward replay starts at the 20% first frame; a replay already
-- running is left alone so a connecting -> connected poll cannot restart it,
-- and a reverse in flight just flips direction to avoid a saturation jump.
local function startBannerForward(force)
  if not force then
    if bannerAnimDir == 1 then
      return
    end
    if bannerAnimDir == -1 then
      bannerAnimDir = 1
      bannerAnimAccMs = 0
      wakeAnimation()
      return
    end
  end
  bannerFrame = 0
  bannerAnimDir = 1
  bannerAnimAccMs = 0
  wakeAnimation()
end

-- Reverse continues from the current frame so a disconnect mid-forward does
-- not jump; from the static last frame it replays 26 -> 0 exactly.
local function startBannerReverse()
  if bannerAnimDir == -1 or bannerFrame <= 0 then
    return
  end
  bannerFrame = math.min(bannerFrame, BANNER_FRAME_COUNT - 1)
  bannerAnimDir = -1
  bannerAnimAccMs = 0
  wakeAnimation()
end

local function bannerFramePath()
  return string.format("assets/banner/frame-%02d.webp", bannerFrame)
end

local function nowMs()
  return tonumber(noctalia.nowMs()) or 0
end

local function hexToRgb(hex)
  return tonumber(string.sub(hex, 2, 3), 16) or 255,
    tonumber(string.sub(hex, 4, 5), 16) or 255,
    tonumber(string.sub(hex, 6, 7), 16) or 255
end

local function clampByte(value)
  return math.max(0, math.min(255, math.floor(value + 0.5)))
end

local function rgbHex(r, g, b)
  return string.format("#%02X%02X%02X", clampByte(r), clampByte(g), clampByte(b))
end

local function approach(current, target, dtMs, tauMs)
  if dtMs >= tauMs then
    return target
  end
  return current + (target - current) * (dtMs / tauMs)
end

local function easeOutCubic(t)
  local inv = 1 - t
  return 1 - inv * inv * inv
end

local function accentHex()
  return rgbHex(accentR, accentG, accentB)
end

local function applyStatus(value)
  if type(value) ~= "table" then
    return
  end
  local prevPhase = status.phase
  local nextStatus = {}
  for k, v in pairs(value) do
    nextStatus[k] = v
  end
  nextStatus.phase = Icons.normalizePhase(nextStatus.phase)
  status = nextStatus
  if isOpen and status.phase ~= prevPhase then
    local wasConnected = isConnectedLike(prevPhase)
    local nowConnected = isConnectedLike(status.phase)
    if nowConnected and not wasConnected then
      startBannerForward(false)
    elseif wasConnected and (status.phase == "disconnecting" or status.phase == "disconnected") then
      startBannerReverse()
    end
    wakeAnimation()
  end
end

local function phaseAccent()
  return PHASE_ACCENT[status.phase] or PHASE_ACCENT.unknown
end

local function isBusy()
  return status.busy == true
end

local function isTransitionPhase()
  local phase = status.phase
  return phase == "connecting" or phase == "disconnecting"
end

-- Mutations require a live CLI, an idle service and a registered client.
local function controlsEnabled()
  return status.available == true and status.busy ~= true and status.registered ~= false
end

-- A held transition deliberately keeps busy set, so power ignores busy there:
-- it is the escape hatch (toggle maps connecting -> disconnect, disconnecting -> connect).
local function powerEnabled()
  local phase = status.phase
  if status.available ~= true or status.registered == false then
    return false
  end
  if phase == "unregistered" or phase == "unavailable" then
    return false
  end
  if isTransitionPhase() then
    return true
  end
  return status.busy ~= true
end

local function traceIp()
  local trace = type(status.trace) == "table" and status.trace or {}
  local ip = trace.ip
  return type(ip) == "string" and ip or ""
end

-- The CLI never reports the DNS families value, so an unset/unknown value is
-- presented as the Cloudflare default instead of an empty segmented control.
local function effectiveFamilies()
  local value = status.families
  if value == "off" or value == "malware" or value == "full" then
    return value
  end
  return FAMILIES_DEFAULT
end

-- modeLabels: the seven translated mode names in MODE_ORDER order.
local function modeLabels()
  local labels = {}
  for _, id in ipairs(MODE_ORDER) do
    labels[#labels + 1] = noctalia.tr("mode." .. id)
  end
  return labels
end

-- modeIndex / protocolIndex: 0-based index into the real option list; nil when
-- the value is unknown.
local function modeIndex()
  for i, id in ipairs(MODE_ORDER) do
    if id == status.mode then
      return i - 1
    end
  end
  return nil
end

local function protocolIndex()
  for i, id in ipairs(PROTOCOL_ORDER) do
    if id == status.protocol then
      return i - 1
    end
  end
  return nil
end

-- The host select always selects option 0 for a non-empty list, so `nil`
-- cannot display its placeholder. An unknown value gets an explicit leading
-- placeholder option instead; the change handlers ignore that index.
local function selectData(labels, index, placeholder)
  if index ~= nil then
    return labels, index, 0
  end
  local options = { placeholder }
  for _, label in ipairs(labels) do
    options[#options + 1] = label
  end
  return options, 0, 1
end

-- Timers: second ticks drive the copy/refresh feedback windows.
local function syncTicks()
  panel.setWantsSecondTicks(copiedUntilMs > 0 or refreshUntilMs > 0)
end

-- Animation helpers ----------------------------------------------------------

local function needsAnimation()
  if entranceT < 1 then
    return true
  end
  local tr, tg, tb = hexToRgb(phaseAccent())
  if math.abs(accentR - tr) + math.abs(accentG - tg) + math.abs(accentB - tb) > 2 then
    return true
  end
  if bannerAnimDir ~= 0 then
    return true
  end
  if isTransitionPhase() or refreshUntilMs > 0 then
    return true
  end
  for _, id in ipairs(FAMILIES_ORDER) do
    if math.abs(hoverCurrent[id] - hoverTarget[id]) > 0.01 then
      return true
    end
  end
  return false
end

wakeAnimation = function()
  if not isOpen then
    return
  end
  if not frameTicksOn then
    frameTicksOn = true
    panel.setNeedsFrameTick(true)
  end
end

local function syncFrameTicks()
  if isOpen and needsAnimation() then
    wakeAnimation()
  elseif frameTicksOn then
    frameTicksOn = false
    panel.setNeedsFrameTick(false)
  end
end

local function displayedBannerOpacity()
  return math.max(0, math.min(1, easeOutCubic(entranceT)))
end

local function transitionWave()
  if not isTransitionPhase() then
    return nil
  end
  local t = nowMs() / WAVE_PERIOD_MS * math.pi * 2
  local bars = {}
  for i = 1, 5 do
    local level = 0.5 + 0.5 * math.sin(t + (i - 1) * 0.7)
    bars[i] = ui.column({
      key = "transition-bar-" .. i,
      width = 3,
      height = math.floor(4 + 10 * level + 0.5),
      radius = 2,
      fill = CYAN,
      opacity = 0.45 + 0.55 * level,
    })
  end
  return ui.row({
    key = "transition-wave",
    height = 14,
    gap = 3,
    align = "center",
  }, bars)
end

local function refreshPulseOpacity()
  if refreshUntilMs <= 0 then
    return 1
  end
  return 0.55 + 0.45 * math.abs(math.sin(nowMs() / 650 * math.pi))
end

local function familiesSegmentColors(value)
  local selected = effectiveFamilies() == value
  local hover = hoverCurrent[value] or 0
  local fillAlpha
  local borderAlpha
  if selected then
    fillAlpha = 0x1F + 0x12 * hover
    borderAlpha = 0x99 + 0x33 * hover
  else
    fillAlpha = 0x0A * hover
    borderAlpha = 0x40 * hover
  end
  return CYAN .. string.format("%02X", clampByte(fillAlpha)),
    CYAN .. string.format("%02X", clampByte(borderAlpha))
end

-- Named hover callback: a stable name lets the host keep the hover wired
-- across the re-renders that animate the segment.
function familiesHover(state, key)
  local value = string.gsub(tostring(key or ""), "^families%-", "")
  if hoverTarget[value] == nil then
    return
  end
  local entering = state == "true"
  for _, id in ipairs(FAMILIES_ORDER) do
    hoverTarget[id] = (entering and id == value) and 1 or 0
  end
  wakeAnimation()
end

function onFrameTick(deltaMs)
  if not isOpen then
    if frameTicksOn then
      frameTicksOn = false
      panel.setNeedsFrameTick(false)
    end
    return
  end
  local delta = tonumber(deltaMs) or FRAME_STEP_MS
  if delta <= 0 then
    delta = FRAME_STEP_MS
  end
  frameAccMs = frameAccMs + math.min(delta, 120)
  if frameAccMs < FRAME_STEP_MS then
    return
  end
  local dt = math.min(frameAccMs, 120)
  frameAccMs = 0

  if entranceT < 1 then
    entranceT = math.min(1, entranceT + dt / ENTRANCE_MS)
  end
  local tr, tg, tb = hexToRgb(phaseAccent())
  accentR = approach(accentR, tr, dt, ACCENT_TAU_MS)
  accentG = approach(accentG, tg, dt, ACCENT_TAU_MS)
  accentB = approach(accentB, tb, dt, ACCENT_TAU_MS)
  if bannerAnimDir ~= 0 then
    bannerAnimAccMs = bannerAnimAccMs + dt
    while bannerAnimAccMs >= BANNER_FRAME_MS do
      bannerAnimAccMs = bannerAnimAccMs - BANNER_FRAME_MS
      bannerFrame = bannerFrame + bannerAnimDir
      if bannerFrame >= BANNER_FRAME_COUNT - 1 then
        bannerFrame = BANNER_FRAME_COUNT - 1
        bannerAnimDir = 0
        bannerAnimAccMs = 0
        break
      end
      if bannerFrame <= 0 then
        bannerFrame = 0
        bannerAnimDir = 0
        bannerAnimAccMs = 0
        break
      end
    end
  end
  for _, id in ipairs(FAMILIES_ORDER) do
    hoverCurrent[id] = approach(hoverCurrent[id], hoverTarget[id], dt, HOVER_TAU_MS)
  end

  render()
  syncFrameTicks()
end

-- Command callbacks. Guards mirror the service checks so a stray callback can
-- never emit a second command while one is in flight.
local function onModeChange(index, offset)
  local i = tonumber(index)
  offset = tonumber(offset) or 0
  if controlsEnabled() and status.switchLocked ~= true
      and i ~= nil and i >= offset and i - offset < #MODE_ORDER then
    local mode = MODE_ORDER[i - offset + 1]
    if mode ~= status.mode then
      State.setCommand("set-mode", { mode = mode, source = "panel" })
    end
  end
  -- Re-render to snap the controlled select back to the published value.
  render()
end

local function onProtocolChange(index, offset)
  local i = tonumber(index)
  offset = tonumber(offset) or 0
  if controlsEnabled() and i ~= nil and i >= offset and i - offset < #PROTOCOL_ORDER then
    local protocol = PROTOCOL_ORDER[i - offset + 1]
    if protocol ~= status.protocol then
      State.setCommand("set-protocol", { protocol = protocol, source = "panel" })
    end
  end
  render()
end

local function onFamilies(families)
  if controlsEnabled() and effectiveFamilies() ~= families then
    State.setCommand("set-families", { families = families, source = "panel" })
  end
  render()
end

local function onPower()
  if not powerEnabled() then
    return
  end
  State.setCommand("toggle", { source = "panel" })
end

local function onRegister()
  if status.available == true and status.registered == false and status.busy ~= true then
    State.setCommand("register", { source = "panel" })
  end
end

local function onCopyIp()
  local ip = traceIp()
  if ip == "" then
    return
  end
  local copied = noctalia.copyToClipboard(ip, "text/plain")
  if copied ~= true then
    return
  end
  copiedUntilMs = nowMs() + COPY_FEEDBACK_MS
  syncTicks()
  render()
end

local function onRefresh()
  if refreshUntilMs > 0 then
    return
  end
  refreshUntilMs = nowMs() + REFRESH_FEEDBACK_MS
  syncTicks()
  wakeAnimation()
  State.setCommand("refresh", { source = "panel" })
  render()
end

local function onSettings()
  noctalia.openSettings()
end

local function onCloseClicked()
  panel.close()
end

-- Tree builders --------------------------------------------------------------

local function caption(text)
  return ui.label({ text = text, fontSize = 11, color = "on_surface_variant" })
end

local function sectionLabel(text)
  return ui.label({ text = text, fontSize = 12, color = "on_surface_variant" })
end

local function shortIp(ip)
  if #ip <= IP_DISPLAY_MAX then
    return ip
  end
  return string.sub(ip, 1, 13) .. "…" .. string.sub(ip, -12)
end

-- Banner: full-bleed animated frame. The root cancels the host's horizontal
-- inset, so only the top inset is pulled with negative padding here. The
-- sequence is pre-cropped to the 400:160 aspect, so cover adds no extra crop.
local function banner()
  return ui.column({
    key = "banner-wrap",
    height = BANNER_WRAP_HEIGHT,
    paddingV = -HOST_PADDING,
  }, {
    ui.image({
      key = "banner",
      path = bannerFramePath(),
      width = PANEL_WIDTH,
      height = BANNER_HEIGHT,
      radius = BANNER_RADIUS,
      fit = "cover",
      opacity = displayedBannerOpacity(),
    }),
  })
end

-- Header: small brand glyph, title, refresh (loader while working) and close.
local function headerRow()
  local refreshing = refreshUntilMs > 0
  return ui.row({
    width = "100%",
    gap = 8,
    align = "center",
    paddingH = 16,
    paddingV = 8,
  }, {
    ui.glyph({ name = "cloud-lock", size = 18, color = BRAND_ORANGE }),
    ui.label({
      text = noctalia.tr("panel.title"),
      fontSize = 15,
      fontWeight = "bold",
      color = "on_surface",
    }),
    ui.spacer({ flexGrow = 1 }),
    ui.button({
      key = "header-refresh",
      glyph = "refresh",
      variant = "ghost",
      opacity = refreshPulseOpacity(),
      tooltip = noctalia.tr("panel.action.refresh"),
      enabled = not refreshing,
      onClick = onRefresh,
    }),
    ui.button({
      key = "header-close",
      glyph = "close",
      variant = "ghost",
      tooltip = noctalia.tr("panel.action.close"),
      onClick = onCloseClicked,
    }),
  })
end

local function powerButton()
  local phase = status.phase
  local disconnect = phase == "connected" or phase == "connecting" or phase == "disconnecting"
  return ui.button({
    key = "power",
    glyph = "power",
    controlSize = "md",
    glyphSize = 18,
    variant = disconnect and "outline" or "primary",
    tooltip = noctalia.tr(if disconnect then "panel.action.disconnect" else "panel.action.connect"),
    enabled = powerEnabled(),
    onClick = onPower,
  })
end

-- Hero: the one loud accent on the panel; status reads first.
local function heroCard()
  local accent = accentHex()
  local updatedAtMs = tonumber(status.updatedAtMs) or 0
  local updated = if updatedAtMs > 0
    then noctalia.formatTime("%H:%M", math.floor(updatedAtMs / 1000))
    else "—"
  local subtitle = noctalia.tr("panel.hero.subtitle." .. status.phase)
  local errorCode = type(status.errorCode) == "string" and status.errorCode or ""
  -- unavailable and unknown never carry a useful phase sentence when an
  -- errorCode is set, so the translated error text replaces the subtitle
  -- there; the "error" phase folds error + detail into the same row.
  if (status.phase == "unavailable" or status.phase == "unknown") and errorCode ~= "" then
    subtitle = noctalia.tr("error." .. errorCode)
  elseif status.phase == "error" then
    -- Fold the error into the subtitle row so the card keeps a stable height.
    local parts = {}
    if errorCode ~= "" then
      parts[#parts + 1] = noctalia.tr("error." .. errorCode)
    end
    local message = type(status.message) == "string" and status.message or ""
    if message ~= "" then
      parts[#parts + 1] = message
    end
    if #parts > 0 then
      subtitle = table.concat(parts, " — ")
    end
  end
  -- Connected reads as the native Tabler shield-check in the success accent;
  -- other phases keep their phase glyph. No busy override: the transition wave
  -- carries activity.
  local statusGlyph = if status.phase == "connected"
    then "shield-check"
    else Icons.glyph(status.phase)
  local children = {
    ui.row({ width = "100%", gap = 10, align = "center" }, {
      ui.glyph({
        name = statusGlyph,
        size = 22,
        color = accent,
      }),
      ui.label({
        text = noctalia.tr("status." .. status.phase),
        fontSize = 21,
        fontWeight = "bold",
        color = "on_surface",
        maxLines = 1,
        flexGrow = 1,
      }),
      powerButton(),
    }),
    ui.row({ width = "100%", gap = 8, align = "center" }, {
      ui.label({
        text = subtitle,
        fontSize = 12,
        color = "on_surface_variant",
        maxLines = 2,
        flexGrow = 1,
      }),
      ui.label({
        text = noctalia.tr("panel.updated") .. " " .. updated,
        fontSize = 11,
        color = "on_surface_variant",
      }),
    }),
  }
  if isTransitionPhase() then
    local wave = transitionWave()
    if wave ~= nil then
      children[#children + 1] = wave
    end
  end
  return ui.column({
    key = "hero-card",
    width = "100%",
    gap = 8,
    radius = 16,
    borderWidth = 1,
    paddingH = 16,
    paddingV = 12,
    fill = accent .. "14",
    border = accent .. "66",
  }, children)
end

local function modeColumn()
  local options, selectedIndex, offset = selectData(
    modeLabels(),
    modeIndex(),
    noctalia.tr("panel.mode.unknown")
  )
  return ui.column({ flexGrow = 1, gap = 6, align = "stretch" }, {
    sectionLabel(noctalia.tr("panel.section.mode")),
    ui.select({
      key = "mode-select",
      options = options,
      selectedIndex = selectedIndex,
      placeholder = noctalia.tr("panel.mode.unknown"),
      enabled = controlsEnabled() and status.switchLocked ~= true,
      height = 38,
      onChange = function(index)
        onModeChange(index, offset)
      end,
    }),
  })
end

local function protocolColumn()
  local options, selectedIndex, offset = selectData(
    { "WireGuard", "MASQUE" },
    protocolIndex(),
    noctalia.tr("panel.protocol.unknown")
  )
  return ui.column({ flexGrow = 1, gap = 6, align = "stretch" }, {
    sectionLabel(noctalia.tr("panel.section.protocol")),
    ui.select({
      key = "protocol-select",
      options = options,
      selectedIndex = selectedIndex,
      placeholder = noctalia.tr("panel.protocol.unknown"),
      enabled = controlsEnabled(),
      height = 38,
      onChange = function(index)
        onProtocolChange(index, offset)
      end,
    }),
  })
end

-- Controls: Mode and Protocol side by side; a lock caption sits underneath.
local function controlsSection()
  local children = {
    ui.row({
      width = "100%",
      gap = 10,
      align = "stretch",
      opacity = isBusy() and 0.55 or 1.0,
    }, {
      modeColumn(),
      protocolColumn(),
    }),
  }
  if status.switchLocked == true then
    children[#children + 1] = caption(noctalia.tr("panel.mode.locked"))
  end
  return ui.column({ width = "100%", gap = 6 }, children)
end

-- Families: custom segmented control (not a select - the value is write-only).
-- One segment is always selected; unknown values present as the default.
local function familiesSegment(value)
  local selected = effectiveFamilies() == value
  local enabled = controlsEnabled()
  local fill, border = familiesSegmentColors(value)
  return ui.column({
    key = "families-" .. value,
    height = 38,
    radius = 9,
    flexGrow = 1,
    align = "center",
    justify = "center",
    -- Explicit colors in both states: the host reconciler keeps absent flex
    -- fill/border props, which would leave a stale cyan cell after deselect.
    fill = fill,
    border = border,
    borderWidth = 1,
    -- The track dims during busy; only an unregistered client dims segments
    -- on their own so the two opacities never compound.
    opacity = (not enabled and not isBusy()) and 0.55 or 1.0,
    onHover = "familiesHover",
    onClick = function()
      onFamilies(value)
    end,
  }, {
    ui.label({
      text = noctalia.tr("families." .. value),
      fontSize = 12,
      fontWeight = selected and "semibold" or nil,
      color = selected and "on_surface" or "on_surface_variant",
    }),
  })
end

local function familiesSection()
  return ui.column({ width = "100%", gap = 6 }, {
    sectionLabel(noctalia.tr("panel.section.families")),
    ui.row({
      width = "100%",
      gap = 3,
      padding = 3,
      radius = 12,
      fill = "surface_variant/0.45",
      border = "outline/0.25",
      borderWidth = 1,
      opacity = isBusy() and 0.55 or 1.0,
    }, {
      familiesSegment(FAMILIES_ORDER[1]),
      familiesSegment(FAMILIES_ORDER[2]),
      familiesSegment(FAMILIES_ORDER[3]),
    }),
  })
end

-- Identity: egress data from the cdn-cgi/trace probe, honest when missing.
local function identityRow(labelText, valueText)
  return ui.row({ width = "100%", gap = 8, align = "center" }, {
    ui.label({ text = labelText, fontSize = 12, color = "on_surface_variant" }),
    ui.label({
      text = valueText,
      fontSize = 12,
      color = "on_surface",
      maxLines = 1,
      textAlign = "end",
      flexGrow = 1,
    }),
  })
end

local function ipRow()
  local ip = traceIp()
  local copyControl
  if copiedUntilMs > 0 then
    copyControl = ui.column({
      key = "identity-copied",
      width = 32,
      height = 32,
      align = "center",
      justify = "center",
    }, {
      ui.glyph({ name = "check", size = 14, color = SUCCESS }),
    })
  else
    copyControl = ui.button({
      key = "identity-copy-ip",
      glyph = "copy",
      controlSize = "sm",
      glyphSize = 14,
      variant = "ghost",
      tooltip = noctalia.tr("panel.action.copy_ip"),
      enabled = ip ~= "",
      onClick = onCopyIp,
    })
  end
  return ui.row({ width = "100%", gap = 8, align = "center" }, {
    ui.label({ text = noctalia.tr("panel.identity.ip"), fontSize = 12, color = "on_surface_variant" }),
    ui.label({
      text = if ip ~= "" then shortIp(ip) else noctalia.tr("panel.trace.none"),
      fontSize = 12,
      color = "on_surface",
      maxLines = 1,
      textAlign = "end",
      flexGrow = 1,
    }),
    copyControl,
  })
end

local function identitySection()
  local trace = type(status.trace) == "table" and status.trace or {}
  local loc = type(trace.loc) == "string" and trace.loc ~= "" and trace.loc or "—"
  local colo = type(trace.colo) == "string" and trace.colo ~= "" and trace.colo or "—"
  local warp = type(trace.warp) == "string" and trace.warp or ""
  local warpValue = if warp == "on" or warp == "plus" or warp == "off"
    then noctalia.tr("panel.trace.warp." .. warp)
    else noctalia.tr("panel.trace.warp.unknown")
  local atMs = tonumber(trace.atMs) or 0
  local traced = if atMs > 0
    then noctalia.formatTime("%H:%M", math.floor(atMs / 1000))
    else noctalia.tr("panel.trace.never")
  return ui.column({
    key = "identity-card",
    width = "100%",
    gap = 5,
    radius = 16,
    padding = 12,
    fill = "surface_variant/0.35",
    border = "outline/0.35",
    borderWidth = 1,
  }, {
    ui.row({ width = "100%", gap = 8, align = "center" }, {
      ui.label({
        text = noctalia.tr("panel.section.identity"),
        fontSize = 13,
        fontWeight = "semibold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.glyph({ name = "world", size = 14, color = CYAN }),
    }),
    ui.separator({ thickness = 1, color = "outline/0.25", spacing = 0 }),
    ipRow(),
    identityRow(noctalia.tr("panel.identity.loc"), loc),
    identityRow(noctalia.tr("panel.identity.colo"), colo),
    identityRow(noctalia.tr("panel.identity.warp"), warpValue),
    identityRow(noctalia.tr("panel.identity.time"), traced),
  })
end

-- Copy feedback replaces the outline button for ~1.6 s with an unmissable
-- success state (native buttons do not take a text color). The identity-row
-- copy control mirrors it so unregistered clients get feedback too.
local function copiedFeedback()
  return ui.column({
    key = "action-copied",
    height = 38,
    flexGrow = 1,
    radius = 10,
    borderWidth = 1,
    fill = SUCCESS .. "1F",
    border = SUCCESS .. "99",
    align = "center",
    justify = "center",
    onClick = onCopyIp,
  }, {
    ui.row({ gap = 6, align = "center", justify = "center" }, {
      ui.glyph({ name = "check", size = 16, color = SUCCESS }),
      ui.label({
        text = noctalia.tr("panel.action.copied"),
        fontSize = 13,
        fontWeight = "medium",
        color = SUCCESS,
      }),
    }),
  })
end

local function footerActions()
  local ip = traceIp()
  local children = {}
  -- Register replaces Copy IP only while the client is genuinely unregistered.
  if status.registered == false and status.available == true then
    children[#children + 1] = ui.button({
      key = "action-register",
      text = noctalia.tr("panel.action.register"),
      glyph = "user-plus",
      variant = "primary",
      flexGrow = 1,
      enabled = status.busy ~= true,
      onClick = onRegister,
    })
  elseif copiedUntilMs > 0 then
    children[#children + 1] = copiedFeedback()
  else
    children[#children + 1] = ui.button({
      key = "action-copy-ip",
      text = noctalia.tr("panel.action.copy_ip"),
      glyph = "copy",
      variant = "outline",
      flexGrow = 1,
      enabled = ip ~= "",
      onClick = onCopyIp,
    })
  end
  children[#children + 1] = ui.button({
    key = "action-settings",
    text = noctalia.tr("panel.action.settings"),
    glyph = "settings",
    variant = "ghost",
    onClick = onSettings,
  })
  return ui.row({ width = "100%", gap = 8, align = "center", paddingH = 16, paddingV = 8 }, children)
end

local function buildTree()
  local contentChildren = {
    heroCard(),
  }
  -- Missing CLI: controls are useless, so the hero carries the error and the
  -- identity card keeps the last known values.
  if status.available == true then
    contentChildren[#contentChildren + 1] = controlsSection()
    contentChildren[#contentChildren + 1] = familiesSection()
  end
  contentChildren[#contentChildren + 1] = identitySection()
  return ui.column({
    width = "100%",
    gap = 0,
    paddingH = -HOST_PADDING,
    paddingV = 0,
    align = "stretch",
    flexGrow = 1,
  }, {
    banner(),
    headerRow(),
    ui.column({
      key = "content-body",
      width = "100%",
      flexGrow = 1,
      gap = 10,
      paddingH = 16,
      paddingV = 6,
      opacity = easeOutCubic(entranceT),
    }, contentChildren),
    ui.separator({ thickness = 1, color = "outline/0.25" }),
    footerActions(),
  })
end

render = function()
  if not isOpen then
    return
  end
  panel.render(buildTree())
end

-- Entry lifecycle -------------------------------------------------------------

function onOpen(_context)
  -- Apply while still closed so opening does not run the phase-transition dip.
  applyStatus(noctalia.state.get(State.CHANNEL_STATUS))
  isOpen = true
  accentR, accentG, accentB = hexToRgb(phaseAccent())
  -- Match the banner to the current phase on open: replay the ramp only when
  -- the tunnel is live; off/error states stay static on the 20% frame.
  if status.phase == "disconnecting" then
    bannerFrame = BANNER_FRAME_COUNT - 1
    startBannerReverse()
  elseif isConnectedLike(status.phase) then
    startBannerForward(true)
  else
    bannerFrame = 0
    bannerAnimDir = 0
    bannerAnimAccMs = 0
  end
  entranceT = 0
  frameAccMs = 0
  for _, id in ipairs(FAMILIES_ORDER) do
    hoverCurrent[id] = 0
    hoverTarget[id] = 0
  end
  wakeAnimation()
  render()
end

function onClose()
  isOpen = false
  copiedUntilMs = 0
  refreshUntilMs = 0
  bannerAnimDir = 0
  bannerAnimAccMs = 0
  entranceT = 1
  for _, id in ipairs(FAMILIES_ORDER) do
    hoverCurrent[id] = 0
    hoverTarget[id] = 0
  end
  panel.setWantsSecondTicks(false)
  if frameTicksOn then
    frameTicksOn = false
    panel.setNeedsFrameTick(false)
  end
end

-- Second ticks: clear expired feedback and stop ticking once both windows are
-- idle. Feedback lasts at least its window, until the next tick past it.
function update()
  if not isOpen then
    return
  end
  local now = nowMs()
  local changed = false
  if copiedUntilMs > 0 and now >= copiedUntilMs then
    copiedUntilMs = 0
    changed = true
  end
  if refreshUntilMs > 0 and now >= refreshUntilMs then
    refreshUntilMs = 0
    changed = true
  end
  if copiedUntilMs == 0 and refreshUntilMs == 0 then
    panel.setWantsSecondTicks(false)
  end
  syncFrameTicks()
  if changed then
    render()
  end
end

noctalia.state.watch(State.CHANNEL_STATUS, function(value)
  applyStatus(value)
  if isOpen then
    render()
  end
end)

applyStatus(noctalia.state.get(State.CHANNEL_STATUS))
accentR, accentG, accentB = hexToRgb(phaseAccent())
