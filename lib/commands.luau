--!nonstrict
-- Cloudflare WARP - warp-cli argv builders and run wrappers.

local M = {}

-- Base argv for every warp-cli call.
M.CLI = { "warp-cli", "--accept-tos", "--json", "--no-paginate", "--no-ansi" }

-- Whitelists.
M.MODES = {
  warp = true,
  doh = true,
  ["warp+doh"] = true,
  dot = true,
  ["warp+dot"] = true,
  proxy = true,
  tunnel_only = true,
}
M.FAMILIES = { off = true, malware = true, full = true }
M.PROTOCOLS = { wireguard = true, masque = true }

local function withBase(suffix: {string}): ({string})
  local args = {}
  for _, a in ipairs(M.CLI) do
    args[#args + 1] = a
  end
  for _, a in ipairs(suffix) do
    args[#args + 1] = a
  end
  return args
end

function M.statusArgv(): ({string}) return withBase({ "status" }) end
function M.settingsArgv(): ({string}) return withBase({ "settings", "list" }) end
function M.registrationArgv(): ({string}) return withBase({ "registration", "show" }) end
function M.registerArgv(): ({string}) return withBase({ "registration", "new" }) end
function M.connectArgv(): ({string}) return withBase({ "connect" }) end
function M.disconnectArgv(): ({string}) return withBase({ "disconnect" }) end
function M.modeArgv(mode: string): ({string}) return withBase({ "mode", mode }) end
function M.familiesArgv(families: string): ({string}) return withBase({ "dns", "families", families }) end
function M.protocolArgv(protocol: string): ({string}) return withBase({ "tunnel", "protocol", "set", protocol }) end
function M.versionArgv(): ({string}) return { "warp-cli", "--version" } end

-- Trace probe. The host's noctalia.http path times out on this platform
-- (curl 28, 0 bytes), while the system curl reaches the same URL, so the
-- service prefers argv-only curl and falls back to http when it is absent.
function M.traceArgv(url: string): ({string})
  return {
    "curl",
    "--silent",
    "--show-error",
    "--fail",
    "--max-time", "10",
    "--connect-timeout", "5",
    url,
  }
end

-- run: thin wrapper over the argv form of noctalia.runAsync. Returns true if
-- the process was launched.
function M.run(base: {string}, cb: (any) -> (), timeoutMs: number): boolean
  return noctalia.runAsync(base, cb, timeoutMs)
end

return M