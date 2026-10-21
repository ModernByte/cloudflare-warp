# Installation & Setup

[English](Installation-and-Setup.md) · [Русский](Installation-and-Setup.ru.md)

## 1. Install the WARP client

The plugin is a front-end for the official Cloudflare WARP client — install it first.

On Debian/Ubuntu:
```sh
sudo apt install cloudflare-warp
```
Other platforms: follow Cloudflare's official WARP installation guide.

Then register your device once and accept the terms of service:
```sh
warp-cli registration new
warp-cli --accept-tos status
```

## 2. Add the plugin to Noctalia

Clone or download this repository, then point Noctalia at the folder:

```sh
git clone https://github.com/ModernByte/cloudflare-warp.git ~/plugins/cloudflare-warp
noctalia msg plugins source add cloudflare-warp path ~/plugins/cloudflare-warp
noctalia msg plugins enable ModernByte/cloudflare-warp
```

Alternatively use **Noctalia → Settings → Plugins** to add the source and toggle the
plugin on. The WARP icon appears in the bar immediately.

## 3. Get to know the three surfaces

| Surface | Actions |
|---|---|
| Bar widget | Left-click: open panel · Right-click: toggle WARP · Hover: tooltip |
| Control Center tile | Left-click: toggle · Right-click: refresh |
| Panel | Power button, Mode, Tunnel protocol, DNS filtering, Register, Refresh, Copy IP |

## 4. Tuning

In Settings you can adjust the poll interval (default 3 s), desktop notifications for
state changes and errors, automatic public-IP lookups and their interval, plus the
widget's text and compact mode. Everything works out of the box; tune only to taste.

## 5. Language

The interface follows Noctalia's language: English or Russian. Switch the shell
language in Noctalia's settings and reload the plugin.
