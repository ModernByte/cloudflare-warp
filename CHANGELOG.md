# Changelog

All notable changes to the **Cloudflare WARP** plugin for Noctalia are documented
here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-21

First stable release, published by Modern Byte.

### Added
- **Bar widget**: a colour-coded status icon with an optional word. Left-click opens
  the panel, right-click toggles WARP, and hovering shows a full tooltip (status,
  mode, DNS filtering, protocol, IP).
- **Control Center tile**: one-click toggle with a live checked state.
- **Control panel**: status hero with a power button, an animated banner, Mode and
  Tunnel protocol selectors, DNS filtering (Off / Malware / Full), account info,
  a public-IP identity card, plus Register, Refresh and Copy IP actions.
- **Background service**: the single source of truth. Polls the real WARP state every
  few seconds so the bar stays accurate even when WARP changes outside the plugin.
- **Settings**: poll interval, notify on change, notify on error, auto trace and trace
  interval, show-text-in-bar and compact mode.
- **Translations**: complete English and Russian user interface.
- Clear messages for every problem state — WARP not installed, service stopped,
  device not registered, command failed or timed out — each with what to do next.
- Network identity is refreshed right after you connect, disconnect or change
  mode/protocol, so the shown public IP reflects the new route.
- A catalogue preview image.

### Notes
- Requires the official Cloudflare WARP client (`warp-cli` / `warp-svc`) and Noctalia
  with plugin API level 24 or newer.
- The plugin never uses elevated privileges and makes at most one kind of network
  request (an optional public-IP trace), which you can switch off in settings.
