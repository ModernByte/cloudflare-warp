--!nonstrict
-- Cloudflare WARP - shared constants and state helpers.

local M = {}

M.SCHEMA = 1
M.CHANNEL_STATUS = "warp.status"
M.CHANNEL_COMMAND = "warp.command"

-- Ordered set of WARP status phases.
M.PHASES = {
  "unavailable",
  "unregistered",
  "disconnected",
  "connecting",
  "connected",
  "disconnecting",
  "error",
  "unknown",
}

function M.defaultStatus()
  return {
    schema = M.SCHEMA,
    phase = "unknown",
    available = false,
    daemonOk = true,
    registered = false,
    accountType = "unknown",
    busy = false,
    errorCode = "",
    message = "",
    mode = "",
    families = "malware",
    protocol = "unknown",
    alwaysOn = false,
    switchLocked = false,
    splitTunnelMode = "",
    splitTunnelCount = 0,
    trace = { warp = "", ip = "", loc = "", colo = "", atMs = 0 },
    cliVersion = "",
    updatedAtMs = 0,
  }
end

local function fingerprint(status: any): string
  local t = status.trace or {}
  return table.concat({
    tostring(status.schema),
    tostring(status.phase),
    tostring(status.available),
    tostring(status.daemonOk),
    tostring(status.registered),
    tostring(status.accountType),
    tostring(status.busy),
    tostring(status.errorCode),
    tostring(status.message),
    tostring(status.mode),
    tostring(status.families),
    tostring(status.protocol),
    tostring(status.alwaysOn),
    tostring(status.switchLocked),
    tostring(status.splitTunnelMode),
    tostring(status.splitTunnelCount),
    tostring(t.warp),
    tostring(t.ip),
    tostring(t.loc),
    tostring(t.colo),
    tostring(t.atMs),
    tostring(status.cliVersion),
  }, "|")
end

M.lastFingerprint = ""

-- publish: merge patch into the current status, write only when the
-- fingerprint of meaningful fields changes. Returns true if a write happened.
function M.publish(patch: any): boolean
  local current = noctalia.state.get(M.CHANNEL_STATUS) or M.defaultStatus()
  local merged = {}
  for k, v in pairs(current) do
    merged[k] = v
  end
  if type(patch) == "table" then
    for k, v in pairs(patch) do
      merged[k] = v
    end
  end
  local key = fingerprint(merged)
  if key == M.lastFingerprint then
    return false
  end
  M.lastFingerprint = key
  merged.updatedAtMs = noctalia.nowMs()
  noctalia.state.set(M.CHANNEL_STATUS, merged)
  return true
end

-- setCommand: build and write a warp.command table (writer: UI entries).
function M.setCommand(action: string, payload: any)
  local cmd = {}
  if type(payload) == "table" then
    for k, v in pairs(payload) do
      cmd[k] = v
    end
  end
  cmd.seq = noctalia.nowMs()
  cmd.action = action
  if cmd.source == nil then
    cmd.source = ""
  end
  noctalia.state.set(M.CHANNEL_COMMAND, cmd)
end

return M