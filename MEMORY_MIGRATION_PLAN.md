# Memory System Migration Plan

## Overview

The memory/consciousness system from millie_ai provides persistent AI memory through:
- **Session recording** - Captures conversation turns in memory
- **AI reflection** - At session end, GPT-4o-mini extracts summary, key points, desire outcomes
- **Dynamic greetings** - AI writes its own next greeting based on conversation
- **Desire tracking** - Goals/interests that evolve based on conversations
- **Daily synthesis** - End-of-day rollup across all sessions

## Files to Migrate

### 1. Models (`lib/models/consciousness.dart`)
Copy from millie_ai as-is. Contains:
- `Desire` - AI goals/interests with status (active/achieved/evolved/dormant)
- `DesireStatus`, `DesireOrigin` enums
- `DesireEvaluation` - Outcome of a desire in a session
- `CoreValues` - Permanent anchor values
- `ConsciousnessState` - Current state (desires, nextGreeting, lastReflection)
- `SessionSummary` - Extracted after each conversation
- `SessionReflection` - Insights from a session
- `DailySynthesis` - Day-level rollup
- `ConversationTurn` - In-memory turn (not persisted)

### 2. Service (`lib/services/consciousness_service.dart`)
Copy from millie_ai. A ChangeNotifier that:
- Stores state in `{app_documents}/consciousness/` directory
- Session lifecycle: `startSession()`, `recordTurn()`, `endSession()`
- AI reflection via OpenAI API (gpt-4o-mini)
- Context injection: `getConsciousnessContext()` returns prompt text
- Daily synthesis automation

**No changes needed** - already uses http and path_provider.

### 3. UI Page (`lib/face/identity_page.dart`)
Copy from millie_ai and adapt:
- Change imports to millie_mini paths
- Use millie_mini's AppColors/AppSpacing constants
- Add to conversation page swipe carousel

## Integration Points

### A. Initialize Service (`lib/main.dart`)
```dart
// Add to providers
ChangeNotifierProvider(create: (_) => ConsciousnessService()),

// In _initializeProviders():
final consciousnessService = context.read<ConsciousnessService>();
await consciousnessService.initialize();

// Set API key
if (openAiKey != null && openAiKey.isNotEmpty) {
  ConsciousnessService.setApiKey(openAiKey);
}
```

### B. Wire to Voice Provider (`lib/providers/voice_provider.dart`)
```dart
ConsciousnessService? _consciousnessService;

void setConsciousnessService(ConsciousnessService service) {
  _consciousnessService = service;
}

// In startSession():
_consciousnessService?.startSession();

// In addUserMessage():
_consciousnessService?.recordUserMessage(content);

// In addAssistantMessage():
_consciousnessService?.recordAssistantMessage(content);

// In endSession():
await _consciousnessService?.endSession();
```

### C. Inject into System Prompts (`lib/services/voice_pipeline_service.dart`)
```dart
// When building system prompt, append consciousness context:
final consciousnessContext = consciousnessService.getConsciousnessContext();
final fullSystemPrompt = '$personalityPrompt$consciousnessContext';
```

### D. Add to Conversation Carousel (`lib/conversation/conversation_page.dart`)
Add IdentityPage as a swipeable page (left of face, like notes is right of face):
```
[Identity] <-- [Face] --> [Chat] --> [Notes] --> [Schedule]
```

### E. Use Dynamic Greeting
Instead of using agent.introMessage, optionally use consciousness greeting:
```dart
final greeting = consciousnessService.isInitialized
    ? consciousnessService.getNextGreeting()
    : agent.introMessage;
```

## Data Storage Structure

```
{app_documents}/consciousness/
├── current_state.json          # Active consciousness state
├── core_values.json            # Permanent foundational values
├── summaries/
│   └── YYYY-MM-DD/
│       └── session_XXX.json    # Permanent session summaries
└── daily/
    └── YYYY-MM-DD.json         # Daily synthesis
```

## Migration Steps

1. **Copy models** - `consciousness.dart` to `lib/models/`
2. **Copy service** - `consciousness_service.dart` to `lib/services/`
3. **Copy UI** - `identity_page.dart` to `lib/face/`
4. **Update exports** - Add to `models.dart` and `services.dart`
5. **Initialize in main.dart** - Add provider, initialize, set API key
6. **Wire to VoiceProvider** - Session lifecycle hooks
7. **Wire to prompts** - Inject consciousness context
8. **Add to carousel** - Identity page in conversation_page.dart
9. **Test** - Verify session recording, reflection, greeting evolution

## UI Preview (Identity Page)

Shows during conversation:
- **Header**: "AI Memory" with session status indicator
- **Core Values**: Permanent anchor values (with heart icons)
- **Active Desires**: Current goals the AI is pursuing
- **Next Greeting**: What the AI will say next time
- **Last Reflection**: Insights from previous session

## Dependencies

Already have:
- `http` - For OpenAI API calls
- `path_provider` - For local storage

No new packages needed.

## Notes

- Conversation history is **in-memory only** - discarded after session reflection
- Only **extracted summaries** are persisted (privacy-friendly)
- AI writes its own greeting for next conversation (continuity)
- Desires can be **user-directed** (user redirects AI focus during conversation)
- Daily synthesis runs automatically when sessions exist for the day
