# Cloudflare WARP for Noctalia

[English](Home.md) · [Русский](Home.ru.md)

A desktop plugin that controls the official **Cloudflare WARP** client from the
Noctalia shell: a status icon in the bar, a toggle tile in the Control Center and a
full control panel. No terminal needed for day-to-day use.

## Pages

- **[Installation & Setup](Installation-and-Setup.md)** — get WARP installed, add the plugin, first run.
- **[Architecture](Architecture.md)** — how the service, state and UI fit together.
- **[IPC Reference](IPC-Reference.md)** — drive WARP from scripts and keybindings.
- **[Troubleshooting](Troubleshooting.md)** — what the warnings mean and how to fix them.

## At a glance

- **Bar widget** — left-click opens the panel, right-click toggles WARP, hover for details.
- **Control Center tile** — one-click connect/disconnect.
- **Panel** — power button, mode & protocol selectors, DNS filtering, account info, public-IP card.
- **English & Russian** interface, following your Noctalia language.
- **Safe by design** — runs `warp-cli` only as your user, never uses `sudo`, and the
  one optional network lookup can be switched off in settings.

Requires the Cloudflare WARP client (`warp-cli` / `warp-svc`) and Noctalia plugin API
level 24 or newer. Licensed under MIT by Modern Byte.
