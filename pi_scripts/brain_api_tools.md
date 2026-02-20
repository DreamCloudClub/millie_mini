# Brain API Tools

HTTP API for controlling a headless Raspberry Pi from a tablet app or AI agent.

## Base URL

```
http://brain.local:8080
```

## Authentication

All endpoints require Bearer token authentication.

```
Authorization: Bearer brain
```

The token is configured via `BRAIN_TOKEN` environment variable (default: `brain`).

---

## Endpoints

### GET /status

Get current Pi status including online state, temperature, memory, uptime, and IP address.

**Request:**
```http
GET /status HTTP/1.1
Host: brain.local:8080
Authorization: Bearer brain
```

**Response (200 OK):**
```json
{
  "online": true,
  "temperature": 47.2,
  "uptime": "up 7 hours, 21 minutes",
  "memory": "1.3Gi/15Gi",
  "ip": "192.168.1.31"
}
```

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized"
}
```

---

### POST /shutdown

Safely shut down the Pi. Requires physical access to power back on.

**Request:**
```http
POST /shutdown HTTP/1.1
Host: brain.local:8080
Authorization: Bearer brain
```

**Response (200 OK):**
```json
{
  "message": "Shutting down..."
}
```

**Usage Rules:**
- Always confirm with user before calling
- Pi will be unreachable after this call
- Requires physical power cycle to restart

---

### POST /reboot

Reboot the Pi. It will come back online automatically.

**Request:**
```http
POST /reboot HTTP/1.1
Host: brain.local:8080
Authorization: Bearer brain
```

**Response (200 OK):**
```json
{
  "message": "Rebooting..."
}
```

**Usage Rules:**
- Confirm with user before calling
- Pi will be offline for ~60 seconds
- Will auto-reconnect once back online

---

## Tool Definitions (OpenAI Function Calling Format)

```json
[
  {
    "type": "function",
    "function": {
      "name": "get_brain_status",
      "description": "Get the current status of the Pi (brain). Returns online state, CPU temperature, memory usage, uptime, and IP address. Use when user asks about the Pi's status, temperature, or health.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "shutdown_brain",
      "description": "Safely shut down the Pi. ALWAYS confirm with the user first. After shutdown, the Pi requires physical access to turn back on. Use when user explicitly asks to shut down or turn off the Pi/brain.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "reboot_brain",
      "description": "Reboot the Pi. ALWAYS confirm with the user first. The Pi will be offline for about a minute then come back automatically. Use when user asks to restart or reboot the Pi/brain.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    }
  }
]
```

---

## OpenClaw Skill Format

To use these as an OpenClaw skill, create `~/.openclaw/skills/brain/skill.md`:

```markdown
# Brain Control Skill

Control the headless Raspberry Pi (brain) - check status, reboot, or shut down.

## Tools

### get_brain_status
Check if the Pi is online and get its current temperature, memory, uptime, and IP.

```bash
curl -s -H "Authorization: Bearer brain" http://brain.local:8080/status
```

### reboot_brain
Reboot the Pi. Always confirm with the user first.

```bash
curl -s -X POST -H "Authorization: Bearer brain" http://brain.local:8080/reboot
```

### shutdown_brain
Shut down the Pi. Always confirm first - requires physical access to restart.

```bash
curl -s -X POST -H "Authorization: Bearer brain" http://brain.local:8080/shutdown
```
```

---

## Usage Rules

1. **Always confirm destructive actions** - shutdown and reboot should prompt user confirmation
2. **Status is safe** - can be called anytime to check Pi health
3. **Token must match** - API rejects requests with wrong/missing token
4. **Local network only** - brain.local resolves via mDNS on same WiFi
5. **Timeout handling** - if Pi is offline, requests will timeout (~5s)

---

## Integration Notes

- The tablet app calls these endpoints directly via HTTP
- Same token (`brain`) is used for both Brain API and OpenClaw gateway
- Status endpoint is polled on page load and via manual refresh
- Shutdown/reboot show confirmation dialogs before executing
