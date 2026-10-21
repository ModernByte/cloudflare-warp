# Architecture

[English](Architecture.md) · [Русский](Architecture.ru.md)

The plugin has **four parts**: one background service and three small UI entries.
Only the service touches your system or the network.

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
  (bar icon)     (Control Center)   (control UI)
```

## The service (the brain)

- Runs `warp-cli status` on a timer (default every 3 s) and turns the output into one
  clean, normalized status: `connected`, `connecting`, `disconnecting`, `disconnected`,
  `unregistered`, `error` or `unavailable`.
- It is the **single source of truth**. When WARP changes on its own — a dropped
  connection, or a change made in a terminal — the next poll notices and updates the
  bar within a couple of seconds.
- When the UI asks for an action (toggle, connect, change mode…), the service is the
  only place that runs the command, with per-action guards so two actions can't
  overlap.
- It can look up your public network identity (an optional trace) so the panel can
  show your egress IP and location.

## The state store (the message bus)

Two shared channels decouple the service from the UI:

- **`warp.status`** — written by the service, read by the widget, tile and panel.
- **`warp.command`** — written by the UI when you click, read (and executed) by the service.

Because the UI never runs commands directly, it stays simple, safe and non-privileged.

## The UI entries (the faces)

- **Widget** — the bar icon, colour and tooltip; left-click opens the panel, right-click
  sends a toggle command.
- **Shortcut** — the Control Center tile; a checked state that mirrors the connection.
- **Panel** — the rich control surface: status hero, animated banner, selectors,
  account/identity cards and action buttons.

The widget and panel render original colour SVG icons; if an icon file is ever
missing, they fall back to a built-in text glyph rather than breaking.

## Security model

- Commands are always run as your normal user through `warp-cli`. There is **no
  `sudo`, `pkexec` or `systemctl`** anywhere in the plugin.
- Each command uses a fixed argument list (never a shell string), and the values for
  mode, DNS filtering and protocol are checked against a small allow-list.
- The only outbound request is the optional public-identity trace to Cloudflare's
  `cdn-cgi/trace`; disable it with the **Auto trace** setting.
- The plugin reads no credentials and stores nothing secret.

## One plugin at a time

The status channels are global, so enable only **one** WARP plugin. Disable any other
WARP toggle before enabling this one to avoid two services fighting over the state.
