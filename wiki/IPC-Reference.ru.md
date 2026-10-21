# IPC-справочник

[English](IPC-Reference.md) · [Русский](IPC-Reference.ru.md)

Каждое действие панели доступно и через шину сообщений плагинов Noctalia — удобно для
клавиатурных сокращений и скриптов. Все команды ниже безопасны для туннеля, кроме тех,
что явно его меняют.

## Формат адреса

```sh
noctalia msg plugin ModernByte/cloudflare-warp:service all <действие> [значение]
```

`all` — цель сервисной entry, она всегда одна.

## Действия

| Действие | Аргумент | Эффект |
|---|---|---|
| `toggle` | — | Включить, если выключено; выключить, если включено |
| `connect` | — | Включить WARP |
| `disconnect` | — | Выключить WARP |
| `refresh` | — | Перечитать статус, настройки, регистрацию и (если включено) публичный идентитет |
| `register` | — | Зарегистрировать устройство в WARP (откроется вход Cloudflare, до 30 с) |
| `set-mode` | режим | Один из `warp`, `doh`, `warp+doh`, `dot`, `warp+dot`, `proxy`, `tunnel_only` |
| `set-families` | фильтр | DNS-фильтрация: `off`, `malware` или `full` |
| `set-protocol` | протокол | `wireguard` или `masque` (регистр не важен) |

Недопустимые значения игнорируются и пишутся в лог; конфигурация WARP не меняется.

## Примеры

```sh
# Переключать WARP горячей клавишей
noctalia msg plugin ModernByte/cloudflare-warp:service all toggle

# Перейти в режим DNS-over-HTTPS и проверить результат
noctalia msg plugin ModernByte/cloudflare-warp:service all set-mode doh
noctalia msg plugin ModernByte/cloudflare-warp:service all refresh

# Открыть и закрыть панель
noctalia msg panel-toggle ModernByte/cloudflare-warp:panel
```

## Чтение статуса

Служба публикует состояние в общий канал `warp.status`. Продвинутые интеграции могут
следить за ним вместо собственного опроса CLI:

| Поле | Значение |
|---|---|
| `phase` | `connected` / `connecting` / `disconnecting` / `disconnected` / `unregistered` / `error` / `unavailable` |
| `available`, `daemonOk` | Установлен ли `warp-cli`? Отвечает ли служба `warp-svc`? |
| `registered` | Есть ли у устройства аккаунт WARP? |
| `mode`, `protocol`, `families` | Текущие настройки туннеля |
| `ip`, `loc`, `colo`, `warp` | Результат последней трассировки публичного идентитета |
| `busy` | Действие прямо сейчас выполняется |

Команды отправляются в канал `warp.command` с теми же именами действий; запись в него
эквивалентна форме `noctalia msg` выше.
