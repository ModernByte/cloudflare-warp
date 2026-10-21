# IPC Reference

[English](IPC-Reference.md) · [Русский](IPC-Reference.ru.md)

Every panel action is also available over Noctalia's plugin message bus — handy for
keyboard shortcuts and scripts. All commands below are read-only for your tunnel
except the ones that clearly change it.

## Address format

```sh
noctalia msg plugin ModernByte/cloudflare-warp:service all <action> [value]
```

`all` is the service entry's target; it is always the same.

## Actions

| Action | Argument | Effect |
|---|---|---|
| `toggle` | — | Connect if off, disconnect if on |
| `connect` | — | Turn WARP on |
| `disconnect` | — | Turn WARP off |
| `refresh` | — | Re-read status, settings, registration and (if enabled) the public identity |
| `register` | — | Register the device with WARP (opens the Cloudflare sign-in flow, up to 30 s) |
| `set-mode` | mode | One of `warp`, `doh`, `warp+doh`, `dot`, `warp+dot`, `proxy`, `tunnel_only` |
| `set-families` | filter | DNS filtering: `off`, `malware` or `full` |
| `set-protocol` | protocol | `wireguard` or `masque` (case-insensitive) |

Invalid values are ignored and logged; your WARP setup is left untouched.

## Examples

```sh
# Toggle WARP with a keyboard shortcut
noctalia msg plugin ModernByte/cloudflare-warp:service all toggle

# Switch to DNS-over-HTTPS mode and check the result
noctalia msg plugin ModernByte/cloudflare-warp:service all set-mode doh
noctalia msg plugin ModernByte/cloudflare-warp:service all refresh

# Open and close the panel
noctalia msg panel-toggle ModernByte/cloudflare-warp:panel
```

## Reading the status

The service publishes its state to the shared `warp.status` channel. Advanced
integrations can observe it instead of polling the CLI themselves:

| Field | Meaning |
|---|---|
| `phase` | `connected` / `connecting` / `disconnecting` / `disconnected` / `unregistered` / `error` / `unavailable` |
| `available`, `daemonOk` | Is `warp-cli` installed? Is the `warp-svc` service answering? |
| `registered` | Does the device have a WARP account? |
| `mode`, `protocol`, `families` | Current tunnel settings |
| `ip`, `loc`, `colo`, `warp` | Last public-identity trace result |
| `busy` | An action is running right now |

Commands are sent through the `warp.command` channel with the same action names;
writing to it is equivalent to the `noctalia msg` form above.
