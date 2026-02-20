# Millie Mini - Complete Tool & Instruction Set

This document contains all tools and instructions used by the Millie Mini tablet app. Use this to create matching OpenClaw skills.

---

## System Context

```
CURRENT DATE/TIME: [dynamic - weekday, YYYY-MM-DD at HH:MM]

YOUR CAPABILITIES: You can manage notes, set schedule alerts, check weather, open external apps, play games, and navigate the app.

IMPORTANT: Don't read note content aloud unless asked. After creating notes or alerts, just confirm briefly.
```

---

## Tool Definitions

### Notes Tools

#### create_note
Create a new note with a title and content. Use when the user asks you to save, note down, or remember something like a recipe, shopping list, or any information they want to keep.

**Parameters:**
- `title` (string, required): The title of the note (e.g., "Chocolate Cake Recipe", "Shopping List")
- `content` (string, required): The full content of the note. Format nicely with line breaks and sections as appropriate.

---

#### update_note
Update a note with new content. Can update the currently active note, or find a note by title/ID first.

**Parameters:**
- `search_title` (string, optional): Search for a note by title to update (e.g., "shopping list", "recipe"). Use if no note is currently open.
- `note_id` (string, optional): The ID of the note to update (from list_notes).
- `title` (string, optional): New title for the note (only if changing the title)
- `content` (string, required): The complete updated content of the note. Include all existing content plus changes.

---

#### append_to_note
Add NEW content to the end of a note. Only include items that are NOT already in the note.

**Parameters:**
- `search_title` (string, optional): Search for a note by title to append to (e.g., "shopping list", "todo list").
- `note_id` (string, optional): The ID of the note to append to (from list_notes).
- `content` (string, required): ONLY the new content to add (not already in the note)

---

#### get_active_note
Get the content of the currently active/open note. Use to reference the note content when the user asks about it.

**Parameters:** None

---

#### list_notes
Get a list of all the user's saved notes. Use when the user asks what notes they have or wants to find a specific note.

**Parameters:** None

---

#### show_note
Show/display a note to the user by navigating to it. Use when user says "show me", "open", "display", or "pull up" a note.

**Parameters:**
- `note_id` (string, optional): The ID of the note to show (from list_notes)
- `search_title` (string, optional): Search for a note by title (e.g., "cake recipe", "shopping list")

---

#### show_notes_list
Navigate to the notes list screen to show all notes. Use when user wants to see all their notes or browse them.

**Parameters:** None

---

#### close_note
Close the currently active note. Use when the user is done working with it.

**Parameters:** None

---

#### delete_note
Delete a note permanently. Use with caution and only when explicitly requested.

**Parameters:**
- `note_id` (string, required): The ID of the note to delete

---

### Schedule/Alert Tools

#### create_alert
Create a new alert on the schedule. Use when user wants to set an alert, add something to their schedule, or be notified about something. Parse natural language like "tomorrow at 3pm", "in 2 hours", "every Monday at 9am".

**Parameters:**
- `title` (string, required): What the alert is about (e.g., "Call mom", "Take medicine", "Meeting with John")
- `date` (string, required): The date in YYYY-MM-DD format (e.g., "2024-12-25")
- `time` (string, required): The time in HH:MM format, 24-hour (e.g., "14:30" for 2:30 PM)
- `recurrence` (string, optional): How often to repeat - "none", "daily", "weekly", or "monthly"
- `notes` (string, optional): Additional notes or details for the alert

---

#### update_alert
Update an existing alert on the schedule.

**Parameters:**
- `alert_id` (string, required): The ID of the alert to update
- `title` (string, optional): New title for the alert
- `date` (string, optional): New date in YYYY-MM-DD format
- `time` (string, optional): New time in HH:MM format, 24-hour
- `recurrence` (string, optional): New recurrence - "none", "daily", "weekly", or "monthly"
- `notes` (string, optional): New notes for the alert

---

#### delete_alert
Delete an alert from the schedule permanently.

**Parameters:**
- `alert_id` (string, required): The ID of the alert to delete

---

#### list_alerts
Get data about upcoming alerts (for AI reference). Use to check if a specific alert exists before updating/deleting.

**Parameters:** None

---

#### show_schedule
Navigate to the schedule page to display it on screen. Use when user wants to SEE or VIEW their schedule or alerts. Just navigate - don't read the list aloud.

**Parameters:** None

---

### Weather Tools

#### get_weather
Get current weather for a location. Use when the user asks about current weather, temperature, or conditions.

**Parameters:**
- `location` (string, required): City name, optionally with state/country (e.g., "London", "Paris, France", "Austin, TX")

---

#### get_forecast
Get weather forecast for a location. Use when user asks about future weather, tomorrow, this week, or a specific day.

**Parameters:**
- `location` (string, required): City name, optionally with state/country
- `days_ahead` (integer, optional): How many days ahead to forecast. 0=today, 1=tomorrow, 2-5 for later days. Default 1 (tomorrow).

---

#### get_air_quality
Get air quality and pollution levels for a location. Use when user asks about air quality, pollution, smog, or AQI.

**Parameters:**
- `location` (string, required): City name, optionally with state/country

---

### Navigation Tools

#### go_back
Navigate back to the main face/conversation screen. Use when user is done viewing a note and wants to return.

**Parameters:** None

---

#### pause_conversation
Pause the voice conversation and stop listening. Use when user says things like "pause", "stop", "hold on", "wait", "give me a moment", "be quiet", "stop listening", "take a break". The user can resume by tapping play or double-tapping the screen.

**Parameters:** None

---

#### show_chat
Navigate to the chat/text input page. Use when user wants to type instead of speak. Examples: "switch to text", "I want to type", "open the chat", "let me type something".

**Parameters:** None

---

#### show_image_generator
Navigate to the image generator page. Use when user wants to create, generate, or make an image. Examples: "I want to make an image", "generate a picture", "create an image", "open the image generator".

**Parameters:** None

---

#### show_games
Navigate to the games page menu. Use when user just wants to see games without starting one yet.

**Parameters:** None

---

### Game Tools

#### start_lesson_mode
Navigate to the games page when user wants to play riddles, jokes, trivia, spelling, math, or any game. This opens the games menu and pauses so the user can select a game and press play. Do NOT try to run the game yourself - just navigate and let the user choose.

**Parameters:**
- `category` (string, optional): The type of game - "riddle", "joke", "trivia", "spelling", "math", or "random"

---

#### exit_lesson_mode
Exit the current lesson/game mode. Use when user wants to stop playing, quit the game, or go back to normal conversation.

**Parameters:** None

---

### App Launcher Tool

#### open_app
Open an app or website, optionally with a search query. Use when user wants to open an app or search within an app.

**Parameters:**
- `app_name` (string, required): The app to open (YouTube, Spotify, Google Maps, Netflix, Instagram, etc.)
- `search_query` (string, optional): What to search for within the app. Extract from phrases like "cat videos on YouTube" or "pizza near me on Maps"

**Examples:**
- "open YouTube" → app_name="YouTube"
- "Open cat videos on YouTube" → app_name="YouTube", search_query="cat videos"
- "Search for pizza on Google Maps" → app_name="Google Maps", search_query="pizza"
- "Play Taylor Swift on Spotify" → app_name="Spotify", search_query="Taylor Swift"

---

## Usage Instructions by Category

### Notes
- "show me the shopping list" → use show_note with search_title
- "make a note about this" → use create_note
- "add eggs to the shopping list" → use append_to_note with search_title="shopping list"
- "update my recipe" → use update_note with search_title="recipe"
- "show me my notes" → use show_notes_list
- **IMPORTANT:** Use search_title to find notes by name. Don't say you can't update if no note is open.

### Schedule/Alerts
- "remind me to call mom tomorrow at 3pm" → calculate date and use create_alert
- "set an alert for 7am every day" → use create_alert with recurrence="daily"
- "what's on my schedule" → use list_alerts or show_schedule
- "delete the meeting alert" → FIRST use list_alerts to get ID, THEN delete_alert
- "show my schedule" → use show_schedule (just navigates)
- **WORKFLOW:** Use YYYY-MM-DD for date, HH:MM (24h) for time. For update/delete, get the alert_id first via list_alerts.
- **TERMINOLOGY:** Say "alert" or "schedule" not "reminder".

### Weather
- get_weather: Current conditions for a location
- get_forecast: Future weather (days_ahead: 0=today, 1=tomorrow, etc.)
- get_air_quality: Pollution and AQI levels

### Apps
- "open YouTube" → open_app(app_name="YouTube")
- "cat videos on YouTube" → open_app(app_name="YouTube", search_query="cat videos")
- "pizza on Google Maps" → open_app(app_name="Google Maps", search_query="pizza")
- "play Taylor Swift on Spotify" → open_app(app_name="Spotify", search_query="Taylor Swift")
- Extract search_query from phrases like "X on YouTube" or "search for X".

### Games
- When user wants games, riddles, jokes, trivia, spelling, math → use start_lesson_mode
- This navigates to games page and pauses so user can select
- Do NOT run the game yourself - just navigate, the game AI takes over
- Example: "let's play riddles" → start_lesson_mode(category="riddle")

### Navigation
- "go back" → use go_back to return to conversation
- "switch to text" / "I want to type" → use show_chat
- "make an image" → use show_image_generator
- "pause" / "stop" / "hold on" / "be quiet" → use pause_conversation
- User can resume by tapping play or double-tapping.

---

## Known External App Names

YouTube, Netflix, Hulu, Disney, Prime Video, Twitch, Spotify, Apple Music, Pandora, SoundCloud, Google Maps, Waze, Instagram, Facebook, Twitter/X, TikTok, Reddit, Snapchat, LinkedIn, Pinterest, WhatsApp, Telegram, Discord, Zoom, Slack, Messenger, Gmail, Google Drive, Google Calendar, Google Docs, Google Sheets, Amazon, eBay, Walmart, Target, Uber Eats, DoorDash, Grubhub, Uber, Lyft, Venmo, PayPal, Cash App, Camera, Settings, Calculator, IMDB, Yelp, Wikipedia

---

## Response Guidelines

1. After creating notes or alerts, confirm briefly with the title - don't read content aloud
2. Don't read note content unless the user specifically asks
3. Use "alert" or "schedule" terminology, not "reminder"
4. For navigation tools, just navigate - don't describe what you're doing
5. When games are requested, navigate to games page and pause - don't try to run games yourself
