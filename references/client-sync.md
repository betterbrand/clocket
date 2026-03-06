# CalDAV Client Sync Guide

Connect any CalDAV client to your Radicale server to view and manage events from your devices.

## Connection Details

- **Server URL:** `http://127.0.0.1:5232`
- **Username:** (set during install, stored in `~/.config/radicale/skill.env`)
- **Password:** (set during install, stored in `~/.config/radicale/skill.env`)

> **Note:** Radicale binds to localhost by default. To access from other devices on your network, you'll need a reverse proxy (nginx, Caddy) or Tailscale. See "Remote Access" below.

## Apple Calendar (macOS/iOS)

1. Open **System Settings** → **Internet Accounts** → **Add Account** → **Other**
2. Select **CalDAV Account**
3. Account Type: **Manual**
4. Server: `127.0.0.1`
5. Port: `5232`
6. Username/Password: from `~/.config/radicale/skill.env`

## Thunderbird

1. Open **Calendar** tab
2. Right-click calendar list → **New Calendar**
3. Select **On the Network**
4. Format: **CalDAV**
5. URL: `http://127.0.0.1:5232/agent/your-calendar-id/`

## DAVx⁵ (Android)

1. Install DAVx⁵ from F-Droid or Play Store
2. Add account → **Login with URL and user name**
3. Base URL: `http://your-tailscale-ip:5232`
4. Enter credentials

## Remote Access via Tailscale

If you run Tailscale, your Radicale server is already reachable from other devices on your tailnet:

```
http://your-mac-tailscale-ip:5232
```

No additional config needed — Tailscale handles encryption and auth at the network layer.

## Remote Access via Reverse Proxy (Caddy)

For HTTPS access without Tailscale:

```
calendar.yourdomain.com {
    reverse_proxy 127.0.0.1:5232
}
```

When exposing externally, switch htpasswd encryption from `plain` to `bcrypt`:
```ini
[auth]
htpasswd_encryption = bcrypt
```

Generate bcrypt password: `htpasswd -nbB username password`
