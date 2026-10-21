# Cloudflare WARP for Noctalia

**English · [Русский](README.ru.md)**

A [Noctalia](https://github.com/noctalia-dev) desktop plugin that puts Cloudflare
WARP where you already look at it: a status icon in the bar, a toggle tile in the
Control Center, and a full control panel. Check your connection, switch WARP on or
off, change the operating mode or DNS filtering, and see your current public IP —
without opening a terminal.

Made by **Modern Byte**. Licensed under the MIT License (see [LICENSE](LICENSE)).

![Preview](thumbnail.webp)

---

## What you need first

This plugin is a friendly front-end for the official Cloudflare WARP client — it
does not replace it. Before installing:

1. **Install the WARP client.** It provides the `warp-cli` command and the `warp-svc`
   background service. On most systems:
   ```sh
   # Debian / Ubuntu
   sudo apt install cloudflare-warp
   ```
   (Other platforms: see Cloudflare's WARP install guide.)
2. **Register once.** Start WARP and register your device so it has an account:
   ```sh
   warp-cli registration new
   ```
   The plugin's panel also has a **Register** button that walks you through this.
3. **Accept the terms of service** the first time `warp-cli` runs.

If WARP is not installed or the service is stopped, the plugin shows a clear
warning instead of failing — see [Troubleshooting](#troubleshooting).

## Install the plugin

Noctalia loads this plugin from its source folder.

1. Download or clone this repository to your machine, e.g. to `~/plugins/cloudflare-warp`.
2. Tell Noctalia where it lives and turn it on:
   ```sh
   noctalia msg plugins source add cloudflare-warp path ~/plugins/cloudflare-warp
   noctalia msg plugins enable ModernByte/cloudflare-warp
   ```
   (You can also add the source and enable the plugin from Noctalia's Settings → Plugins.)

That's it — the bar icon appears right away.

## Using it

**Bar widget**
- **Left-click** opens the control panel.
- **Right-click** toggles WARP on or off.
- The icon colour shows the state: connected, disconnected, connecting, warning or error.
- Hovering the icon gives a tooltip with status, mode, DNS filtering, protocol and IP.

**Control Center tile**
- One click toggles the tunnel; a right-click refreshes the status.

**Control panel** (from the bar widget)
- A large status card at the top with a big power button.
- Animated banner that fills with colour while WARP is connecting or connected.
- **Mode** and **Tunnel protocol** selectors, **DNS filtering** (Off / Malware / Full),
  and your account details.
- A network identity card showing your public IP, location and whether WARP is in use.
- **Register**, **Refresh** and **Copy IP** actions.

The panel is available in English and Russian, following your Noctalia language.

## Settings

Open Noctalia's Settings and find **Cloudflare WARP**.

| Setting | Default | What it does |
|---|---|---|
| Poll interval | 3000 ms | How often the plugin checks WARP's real status (1000–60000 ms). Keeps the bar in sync even if you change WARP in a terminal or the connection drops. |
| Notify on change | on | A desktop notification when WARP connects or disconnects. |
| Notify on error | on | A notification when something goes wrong (WARP missing, service stopped, command failed). |
| Auto trace | on | Periodically look up your public network identity. |
| Trace interval | 60 s | How often to refresh the identity (15–3600 s). Only shown when Auto trace is on. |
| Show text in bar | on | Show a short status word next to the icon. |
| Compact mode | off | Icon only, for tight bars. |

## How it works (architecture)

The plugin is one background **service** plus three thin, non-privileged UI pieces.
The service is the only thing that talks to your computer and to Cloudflare:

```
        ┌─────────────────────────────────────────────┐
        │                  service                      │
        │  polls warp-cli, holds the one true status    │
        └───────────────┬─────────────────────────────┘
                        │  publishes status · accepts commands
                 ┌──────┴───────┐
                 │  state store │   warp.status / warp.command
                 └──────┬───────┘
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
     widget         shortcut          panel
   (bar icon)    (Control Center)   (control UI)
```

- The **service** runs `warp-cli` on a timer, turns its output into a clean status,
  and writes that status to a shared state store. When you click something, the UI
  pieces only write a command; the service carries it out. Nothing else runs the
  command line.
- The **widget**, **Control Center tile** and **panel** only read the status and
  send commands. They never touch the network or the command line, and they never
  need elevated rights.
- WARP's status can change on its own (a dropped connection, or a change made in a
  terminal). The timer-based poll re-reads the real state every few seconds, so the
  bar always reflects reality.
- Because the status channels are shared, keep only **one** WARP plugin enabled at a
  time — disable any other WARP toggle plugin before enabling this one.

### What it runs and where it connects

- All WARP control happens through the local `warp-cli` command, always as your
  normal user. The plugin **never** uses `sudo` or runs anything as another user.
- The only network request is an optional lookup of your public identity to
  `https://www.cloudflare.com/cdn-cgi/trace`, which reports your egress IP, location
  and WARP status back to Cloudflare — the same thing `warp-cli` and a browser visit
  to that address would show. Turn **Auto trace** off in settings to stop it entirely.
- No accounts, keys or credentials are read or stored by the plugin.

## Advanced: controlling it from scripts

The same actions the panel offers can be triggered over Noctalia's plugin message
bus, useful for keybindings or scripts:

```sh
noctalia msg plugin ModernByte/cloudflare-warp:service all toggle
noctalia msg plugin ModernByte/cloudflare-warp:service all connect
noctalia msg plugin ModernByte/cloudflare-warp:service all disconnect
noctalia msg plugin ModernByte/cloudflare-warp:service all refresh
```

## Troubleshooting

| The bar shows | What it means | What to do |
|---|---|---|
| "Not installed" / missing icon state | `warp-cli` is not on your PATH | Install the Cloudflare WARP package, then press Refresh. |
| "Service stopped" / offline warning | The `warp-svc` background service isn't running | Start it: `sudo systemctl start warp-svc` (in your terminal), then Refresh. |
| "Not registered" | WARP has no account on this device | Click **Register** in the panel, or run `warp-cli registration new`. |
| A red error after an action | A command failed or timed out | The tooltip and panel show the reason; try Refresh. |
| Mode selector greyed out | The current mode is locked by WARP settings | Unlock it in WARP's own configuration; the selector re-enables itself. |

If WARP is missing or the service is down, the plugin stays alive and shows a
warning — it never crashes or hides itself.

## Known limitations

- **DNS filtering value** is set-only through `warp-cli`, so after a reboot the panel
  shows the default (Malware) until you change it again in the session.
- The **Control Center tile** uses a text/glyph label (the platform doesn't accept a
  custom image there); the bar widget uses the full colour icons.
- Keep only one WARP plugin enabled at a time (shared status channels).

## License

Copyright (c) 2026 Modern Byte, released under the **MIT License**.

"Cloudflare" and "WARP" are trademarks of Cloudflare, Inc. This is an independent
community plugin and is not affiliated with, endorsed by, or produced by Cloudflare.
