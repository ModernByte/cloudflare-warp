# Troubleshooting

[English](Troubleshooting.md) · [Русский](Troubleshooting.ru.md)

Most problems show up directly in the widget tooltip and the panel header, with a
short reason and a suggested action. Nothing below requires touching the plugin
itself — every fix is either a button in the panel or one command in your terminal.

## Symptom → fix

| Symptom | Cause | Fix |
|---|---|---|
| Icon shows "Not installed" | `warp-cli` is not on your PATH | Install the Cloudflare WARP package, then press **Refresh** in the panel. |
| "Daemon offline" / service warning | The `warp-svc` background service is not running | Start it from your terminal: `sudo systemctl start warp-svc`, then press **Refresh**. The plugin never runs sudo itself. |
| "Not registered" | This device has no WARP account yet | Click **Register** in the panel, or run `warp-cli registration new` once in the terminal. |
| Terms-of-service notice appears | Fresh install, ToS not accepted yet | Run `warp-cli --accept-tos status` once in the terminal. |
| A red error after an action | A command failed or timed out | The tooltip and panel show the reason (e.g. `timeout`, `command-failed`). Press **Refresh**; if it persists, check `warp-cli status` in the terminal. |
| Stuck on "Connecting…" for a long time | WARP is retrying in the background, or the tunnel is really down | Wait for the transition to resolve; then toggle off/on or run `warp-cli disconnect` followed by `warp-cli connect`. |
| Mode selector is greyed out | The WARP client has *Switch Locked* enabled by policy | Nothing is broken — the administrator of the account locks the mode. Enable/disable Switch Lock in your WARP account settings if you own it. |
| Public IP / location never appears | Trace lookups are off or blocked | Enable **Auto trace** in plugin settings; check that `https://www.cloudflare.com/cdn-cgi/trace` is reachable from your network. |
| Status looks wrong right after you changed it in the terminal | The plugin polls on a timer | Wait one poll cycle (default 3 s) or press **Refresh**. |

## Error codes

When something fails, the panel shows a code. Each one means:

| Code | Meaning | What to do |
|---|---|---|
| `cli-missing` | `warp-cli` was not found | Install the WARP client package. |
| `daemon-down` | `warp-svc` is not answering | Start the service (`sudo systemctl start warp-svc`). |
| `unregistered` | No account on this device | Click **Register**. |
| `timeout` | A CLI call took too long | Retry with **Refresh**; check the client in the terminal. |
| `command-failed` | The CLI returned an error | Read the tooltip message; usually Refresh fixes it. |
| `decode-failed` | Unexpected CLI output format | Update the WARP client and the plugin; then Refresh. |

## Only one WARP plugin

The plugin shares its state over global Noctalia channels. If you also have another
Cloudflare WARP plugin installed, keep **exactly one** enabled — two polling instances will fight over the same `warp-cli`.

## Still stuck?

1. Re-run the basics in the terminal and compare with the panel:
   ```sh
   warp-cli --version
   warp-cli status
   warp-cli settings list
   ```
2. Check Noctalia's log for plugin errors:
   ```sh
   grep cloudflare-warp ~/.cache/noctalia/noctalia.log | tail -20
   ```
3. Reload the plugin (Settings → Plugins → disable, enable) — a reload re-probes
   the CLI and rebuilds the panel.
4. If the behavior differs from this documentation, open an issue at
   https://github.com/ModernByte/cloudflare-warp/issues.
