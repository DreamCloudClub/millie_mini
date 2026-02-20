# Millie Mini API/IPC Specification

## Architecture Overview

**Current Architecture:**
```
Tablet App ←→ LLM (OpenAI or OpenClaw) ←→ Claude/GPT
                     ↓
            Returns tool calls
                     ↓
         Tablet executes tools locally
                     ↓
         Data stored on tablet (local storage)
```

**Key Point:** Tools are NOT exposed as HTTP APIs. The LLM returns tool call instructions, and the tablet app executes them locally. Data lives on the tablet.

---

## Transport Layer

### OpenClaw WebSocket Connection

**URL:** `ws://brain.local:18789`

**Auth:** Token-based
```json
{
  "auth": {
    "token": "brain"
  }
}
```

### Message Format (Tablet → OpenClaw)

**Chat Send Request:**
```json
{
  "type": "req",
  "method": "chat.send",
  "id": "chat-1",
  "params": {
    "sessionKey": "agent:main:main",
    "idempotencyKey": "idem-1234567890",
    "message": "add milk to my shopping list"
  }
}
```

### Message Format (OpenClaw → Tablet)

**Streaming Response:**
```json
{
  "type": "event",
  "event": "agent",
  "payload": {
    "runId": "idem-1234567890",
    "stream": "assistant",
    "data": {
      "text": "I've added milk to your shopping list."
    }
  }
}
```

**Final Response:**
```json
{
  "type": "event",
  "event": "chat",
  "payload": {
    "runId": "idem-1234567890",
    "state": "final",
    "message": {
      "content": [
        {
          "type": "text",
          "text": "I've added milk to your shopping list."
        }
      ]
    }
  }
}
```

---

## Tool Call Format

For OpenClaw/Bubble to trigger tablet actions, return tool calls in this format:

### Tool Call Response Format

```json
{
  "type": "event",
  "event": "chat",
  "payload": {
    "runId": "idem-1234567890",
    "state": "final",
    "message": {
      "content": [
        {
          "type": "tool_use",
          "id": "tool_1",
          "name": "append_to_note",
          "input": {
            "search_title": "shopping list",
            "content": "- Milk"
          }
        }
      ]
    }
  }
}
```

---

## Tool Definitions & Payloads

### Notes Tools

#### create_note
```json
{
  "name": "create_note",
  "input": {
    "title": "Shopping List",
    "content": "- Eggs\n- Milk\n- Bread"
  }
}
```
**Response:** `{ "success": true, "message": "Created \"Shopping List\" note.", "note_id": "uuid", "note_title": "Shopping List" }`

---

#### update_note
```json
{
  "name": "update_note",
  "input": {
    "search_title": "shopping list",
    "content": "- Eggs\n- Milk\n- Bread\n- Butter"
  }
}
```
Or with ID:
```json
{
  "name": "update_note",
  "input": {
    "note_id": "uuid-here",
    "title": "New Title",
    "content": "Updated content"
  }
}
```
**Response:** `{ "success": true, "message": "Updated the note.", "note_id": "uuid" }`

---

#### append_to_note
```json
{
  "name": "append_to_note",
  "input": {
    "search_title": "shopping list",
    "content": "- Cheese"
  }
}
```
**Response:** `{ "success": true, "message": "Added to the note.", "note_id": "uuid" }`

---

#### get_active_note
```json
{
  "name": "get_active_note",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Current note: Shopping List", "note_id": "uuid", "note_title": "Shopping List", "note_content": "- Eggs\n- Milk" }`

---

#### list_notes
```json
{
  "name": "list_notes",
  "input": {}
}
```
**Response:**
```json
{
  "success": true,
  "message": "Found 3 note(s): Shopping List, Recipe, Todo.",
  "notes": [
    { "id": "uuid-1", "title": "Shopping List" },
    { "id": "uuid-2", "title": "Recipe" },
    { "id": "uuid-3", "title": "Todo" }
  ]
}
```

---

#### show_note
```json
{
  "name": "show_note",
  "input": {
    "search_title": "shopping list"
  }
}
```
Or:
```json
{
  "name": "show_note",
  "input": {
    "note_id": "uuid-here"
  }
}
```
**Response:** `{ "success": true, "message": "Here is your \"Shopping List\" note." }`
**Side Effect:** Tablet navigates to note view

---

#### show_notes_list
```json
{
  "name": "show_notes_list",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Here you go." }`
**Side Effect:** Tablet navigates to notes list

---

#### close_note
```json
{
  "name": "close_note",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Closed the note \"Shopping List\"." }`

---

#### delete_note
```json
{
  "name": "delete_note",
  "input": {
    "note_id": "uuid-here"
  }
}
```
**Response:** `{ "success": true, "message": "Deleted \"Shopping List\"." }`

---

### Alert/Schedule Tools

#### create_alert
```json
{
  "name": "create_alert",
  "input": {
    "title": "Call mom",
    "date": "2024-12-25",
    "time": "14:30",
    "recurrence": "none",
    "notes": "Don't forget birthday"
  }
}
```
**Response:** `{ "success": true, "message": "Done! I've added \"Call mom\" to your schedule for December 25 at 2:30 PM.", "alert_id": "uuid" }`

---

#### update_alert
```json
{
  "name": "update_alert",
  "input": {
    "alert_id": "uuid-here",
    "title": "Call mom and dad",
    "time": "15:00"
  }
}
```
**Response:** `{ "success": true, "message": "Updated the alert." }`

---

#### delete_alert
```json
{
  "name": "delete_alert",
  "input": {
    "alert_id": "uuid-here"
  }
}
```
**Response:** `{ "success": true, "message": "Deleted \"Call mom\"." }`

---

#### list_alerts
```json
{
  "name": "list_alerts",
  "input": {}
}
```
**Response:**
```json
{
  "success": true,
  "message": "You have 2 upcoming alerts.",
  "alerts": [
    {
      "id": "uuid-1",
      "title": "Call mom",
      "scheduled_at": "2024-12-25T14:30:00",
      "recurrence": "none"
    },
    {
      "id": "uuid-2",
      "title": "Take medicine",
      "scheduled_at": "2024-12-20T09:00:00",
      "recurrence": "daily"
    }
  ]
}
```

---

#### show_schedule
```json
{
  "name": "show_schedule",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Here you go." }`
**Side Effect:** Tablet navigates to schedule page

---

### Weather Tools

#### get_weather
```json
{
  "name": "get_weather",
  "input": {
    "location": "San Diego, CA"
  }
}
```
**Response:** `{ "success": true, "message": "It's currently 72°F and sunny in San Diego. Humidity is 45%." }`

---

#### get_forecast
```json
{
  "name": "get_forecast",
  "input": {
    "location": "San Diego, CA",
    "days_ahead": 1
  }
}
```
**Response:** `{ "success": true, "message": "Tomorrow in San Diego: Morning 65°F partly cloudy. Afternoon 75°F sunny. Evening 68°F clear." }`

---

#### get_air_quality
```json
{
  "name": "get_air_quality",
  "input": {
    "location": "San Diego, CA"
  }
}
```
**Response:** `{ "success": true, "message": "Air quality in San Diego is Good (AQI 42). Safe for outdoor activities." }`

---

### Navigation Tools

#### go_back
```json
{
  "name": "go_back",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Sure. What else can I help you with?" }`
**Side Effect:** Tablet navigates to main face/conversation

---

#### pause_conversation
```json
{
  "name": "pause_conversation",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Okay, I'll be here when you're ready. Just tap play to continue." }`
**Side Effect:** Tablet stops listening

---

#### show_chat
```json
{
  "name": "show_chat",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Here is the chat. You can type your message." }`
**Side Effect:** Tablet navigates to text chat page

---

#### show_image_generator
```json
{
  "name": "show_image_generator",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Here is the image generator. Type a description of what you want to create." }`
**Side Effect:** Tablet navigates to image generator

---

#### show_games
```json
{
  "name": "show_games",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Here are the games. Tap a category to start!" }`
**Side Effect:** Tablet navigates to games menu, pauses conversation

---

### Game Tools

#### start_lesson_mode
```json
{
  "name": "start_lesson_mode",
  "input": {
    "category": "riddle"
  }
}
```
Categories: `riddle`, `joke`, `trivia`, `spelling`, `math`, `random`

**Response:** `{ "success": true, "message": "Here are the games! Tap Riddles and press play when you're ready." }`
**Side Effect:** Tablet navigates to games, pauses for user selection

---

#### exit_lesson_mode
```json
{
  "name": "exit_lesson_mode",
  "input": {}
}
```
**Response:** `{ "success": true, "message": "Lesson mode ended." }`

---

### App Launcher Tool

#### open_app
```json
{
  "name": "open_app",
  "input": {
    "app_name": "YouTube",
    "search_query": "cat videos"
  }
}
```
**Response:** `{ "success": true, "message": "Opening YouTube with search for cat videos." }`
**Side Effect:** Tablet opens external app

---

## Data Storage

| Data Type | Storage Location | Format |
|-----------|------------------|--------|
| Notes | Tablet local storage | JSON via SharedPreferences |
| Alerts | Tablet local storage | JSON via SharedPreferences |
| User settings | Tablet local storage | Key-value pairs |
| Conversation history | Tablet memory | Not persisted |

---

## Integration Options for OpenClaw/Bubble

### Option 1: Return Tool Calls (Recommended)
OpenClaw returns tool calls in response. Tablet parses and executes locally.

**Pros:** Data stays on tablet, existing code works
**Cons:** Need to update OpenClaw response parsing

### Option 2: Shared Backend (Supabase)
Move notes/alerts to Supabase. Both tablet and OpenClaw read/write there.

**Pros:** Data accessible from anywhere
**Cons:** Requires backend changes, internet dependency

### Option 3: Pi-Local Storage
Store notes/alerts on Pi. OpenClaw manages directly, tablet syncs.

**Pros:** Works offline from cloud
**Cons:** Data split between Pi and tablet

---

## Current Implementation Status

| Feature | Tablet (Standard LLM) | OpenClaw |
|---------|----------------------|----------|
| Notes | ✅ Full support | ❌ Text only |
| Alerts | ✅ Full support | ❌ Text only |
| Weather | ✅ Via OpenWeather API | ✅ Built-in skill |
| Navigation | ✅ Full support | ❌ Not implemented |
| Games | ✅ Full support | ❌ Not implemented |
| Apps | ✅ Full support | ❌ Not implemented |

**To enable full OpenClaw support:** OpenClaw needs to return tool calls in the response format shown above, and the tablet needs to parse them (currently it only reads text).
