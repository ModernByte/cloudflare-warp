--!nonstrict
-- Cloudflare WARP - warp-cli output parsers.
--
-- Pure functions only: no entry globals, no I/O. The only host API used is
-- noctalia.json.decode, which is allowed in lib modules.

local M = {}

-- Ordered status-phase mapping. Order matters: "disconnected" contains
-- "connected", "disconnecting" contains "connecting", etc., so longer /
-- more specific substrings are checked first. Single-word keys at the end
-- serve the text fallback (which captures only the first word).
local STATUS_PHASES = {
  { "registration missing", "unregistered" },
  { "not registered", "unregistered" },
  { "unable to connect", "error" },
  { "disconnecting", "disconnecting" },
  { "disconnected", "disconnected" },
  { "reconnecting", "connecting" },
  { "connecting", "connecting" },
  { "connected", "connected" },
  { "registration", "unregistered" },
  { "unable", "error" },
}

local function mapStatus(raw: string): string
  local lower = string.lower(raw)
  for _, entry in ipairs(STATUS_PHASES) do
    if string.find(lower, entry[1], 1, true) then
      return entry[2]
    end
  end
  return "unknown"
end

-- parseStatus: JSON first, text fallback. Returns (phase, decodeFailed).
function M.parseStatus(stdout: string): (string, boolean)
  local decoded, _err = noctalia.json.decode(stdout or "")
  if type(decoded) == "table" and type(decoded.status) == "string" then
    return mapStatus(decoded.status), false
  end
  local fallback = (stdout or ""):match("Status update:%s*(%S+)")
  if fallback then
    return mapStatus(fallback), false
  end
  return "unknown", true
end

local function listCount(value: any): number
  if type(value) == "table" then
    return #value
  end
  return 0
end

local function trim(s: string): string
  return s:match("^%s*(.-)%s*$")
end

-- parseSettings: JSON first, line-by-line text fallback. Fields that could
-- not be parsed are returned as nil so the caller never clobbers known values.
function M.parseSettings(stdout: string)
  local decoded, _err = noctalia.json.decode(stdout or "")
  if type(decoded) == "table" then
    if type(decoded.settings) == "table" then
      local s = decoded.settings
      return {
        ok = true,
        decodeFailed = false,
        mode = if s.operation_mode ~= nil then string.lower(tostring(s.operation_mode)) else nil,
        protocol = if s.warp_tunnel_protocol ~= nil then string.lower(tostring(s.warp_tunnel_protocol)) else nil,
        alwaysOn = if s.always_on ~= nil then s.always_on == true else nil,
        switchLocked = if s.switch_locked ~= nil then s.switch_locked == true else nil,
        splitTunnelMode = if s.split_tunnel_mode ~= nil then tostring(s.split_tunnel_mode) else nil,
        splitTunnelCount = if s.split_tunnel_ips ~= nil or s.split_tunnel_hosts ~= nil
          then listCount(s.split_tunnel_ips) + listCount(s.split_tunnel_hosts)
          else nil,
      }
    end
    -- JSON decoded but no settings table: failed response, don't clobber.
    return { ok = false, decodeFailed = true }
  end
  -- JSON failed: text fallback (line-by-line "Label: value").
  local text = stdout or ""
  local mode = text:match("Mode:%s*([^\n]+)")
  local protocol = text:match("WARP tunnel protocol:%s*(%S+)")
  local alwaysOn = text:match("Always On:%s*(%S+)")
  local switchLocked = text:match("Switch Locked:%s*(%S+)")
  if mode or protocol or alwaysOn or switchLocked then
    return {
      ok = true,
      decodeFailed = false,
      mode = if mode then string.lower(trim(mode)) else nil,
      protocol = if protocol then string.lower(protocol) else nil,
      alwaysOn = if alwaysOn then alwaysOn == "true" else nil,
      switchLocked = if switchLocked then switchLocked == "true" else nil,
      splitTunnelMode = nil,
      splitTunnelCount = nil,
    }
  end
  return { ok = false, decodeFailed = true }
end

-- parseRegistration: exit 0 -> registered (+ accountType from JSON);
-- exit != 0 -> not registered. Only account.type is read; account and
-- device credentials are never touched.
function M.parseRegistration(stdout: string, exitCode: number): (boolean, string)
  if exitCode ~= 0 then
    return false, "unknown"
  end
  local decoded, _err = noctalia.json.decode(stdout or "")
  if type(decoded) == "table" and type(decoded.account) == "table" and type(decoded.account.type) == "string" then
    return true, decoded.account.type
  end
  return true, "unknown"
end

-- parseTrace: extract warp/ip/loc/colo from "k=v" lines of a trace response.
function M.parseTrace(body: string)
  local trace = { warp = "", ip = "", loc = "", colo = "" }
  for line in (body or ""):gmatch("([^\r\n]+)") do
    local k, v = line:match("^(%w+)=(.*)$")
    if k == "warp" or k == "ip" or k == "loc" or k == "colo" then
      trace[k] = v
    end
  end
  return trace
end

-- classifyError: map a failed CLI result to (phase, errorCode, daemonOk).
-- daemonOk = nil means "leave unchanged".
function M.classifyError(result: any): (string, string, boolean?)
  if result.timedOut then
    return "error", "timeout", nil
  end
  local stderr = string.lower(tostring(result.stderr or ""))
  if string.find(stderr, "registration", 1, true) or string.find(stderr, "not registered", 1, true) then
    return "unregistered", "unregistered", true
  end
  if string.find(stderr, "daemon", 1, true) or string.find(stderr, "socket", 1, true)
      or string.find(stderr, "connect to", 1, true) or string.find(stderr, "service", 1, true) then
    return "error", "daemon-down", false
  end
  return "error", "command-failed", true
end

-- truncate: cap a string to n characters.
function M.truncate(s: any, n: number): string
  s = tostring(s or "")
  if #s > n then
    return s:sub(1, n)
  end
  return s
end

return M