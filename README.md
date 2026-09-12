# Millie Mini

A tablet-first, phone-safe AI Desktop Robot Face + Voice Agent built with Flutter.

# Run Millie Mini

### Samsung Galaxy A7
flutter clean
flutter pub get
flutter run -d R9ZX80AFYBF

### Samsung Galaxy A9
flutter clean
flutter pub get
flutter run -d R9ZY309GSKV

### Samsung Galaxy A9+
flutter clean
flutter pub get
flutter run -d R95YA01NVDK

### Samsung Galaxy A9+
flutter clean
flutter pub get
flutter run -d R95Y908GYYD
## Overview

Millie Mini is a voice-controlled AI assistant with an animated face interface. The application follows a strict turn-based conversation model where the user speaks, Millie listens, processes, and responds - with no interruptions or streaming.

## Features

### Core Features
- **Animated Robot Face** - Expressive eyes and mouth that animate based on state (idle, listening, processing, speaking)
- **Turn-Based Voice Interaction** - Clean conversation flow with no interruptions
- **Multiple AI Service Support** - Dream Cloud AI, OpenAI, Gemini, Anthropic
- **Agent Profiles** - Create and customize multiple AI agents with different personalities
- **Wake Word Detection** - "Hey Millie" wake phrase powered by Porcupine

### Touch Controls
- **Double Tap** - Toggle pause/play
- **Tap & Hold** - Reveal bottom control bar with Pause, Play, Refresh, and Exit buttons

### Voice Commands
- "Pause", "Stop", "Hold on", "Be quiet" - Pause the system

## App Structure

```
lib/
├── main.dart                    # App entry point and navigation
├── splash_page.dart             # Brand splash screen
├── auth/                        # Authentication screens
│   ├── login_page.dart
│   ├── signup_page.dart
│   └── change_password_page.dart
├── dashboard/                   # Main dashboard
│   ├── dashboard_page.dart      # 4-card dashboard layout
│   ├── user_profile_edit_page.dart
│   └── account_settings_edit_page.dart
├── agents/                      # Agent management
│   ├── agent_profiles_page.dart
│   └── edit_agent_page.dart
├── personalities/               # Personality management
│   └── personality_builder_page.dart
├── ai_services/                 # AI service configuration
│   ├── ai_services_page.dart
│   ├── edit_dream_cloud_page.dart
│   └── edit_custom_service_page.dart
├── face/                        # Face UI and animations
│   ├── face_page.dart           # Main face screen
│   ├── face_eyes.dart           # Animated eyes
│   ├── face_mouth.dart          # Animated mouth
│   └── control_bar.dart         # Bottom control overlay
├── models/                      # Data models
│   ├── user_profile.dart
│   ├── agent.dart
│   ├── personality.dart
│   ├── ai_service.dart
│   ├── voice_state.dart
│   └── conversation.dart
├── providers/                   # State management
│   ├── auth_provider.dart
│   ├── agent_provider.dart
│   ├── personality_provider.dart
│   ├── ai_service_provider.dart
│   └── voice_provider.dart
├── services/                    # Business logic
│   ├── storage_service.dart
│   ├── voice_pipeline_service.dart
│   └── agent_router.dart
├── widgets/                     # Reusable UI components
│   ├── app_card.dart
│   ├── app_button.dart
│   ├── app_text_field.dart
│   ├── app_dropdown.dart
│   ├── error_modal.dart
│   ├── confirm_dialog.dart
│   └── face_preview.dart
└── utils/
    └── constants.dart           # Colors, styles, spacing
```

## State Machine

```
DASHBOARD
   ↓ (Launch Button)
ACTIVE SESSION
   ↓
LISTENING → PROCESSING → SPEAKING → LISTENING (continuous loop)

-- DOUBLE TAP / VOICE COMMAND -->
PAUSED
-- DOUBLE TAP / WAKE WORD / PLAY BUTTON -->
LISTENING

-- TAP & HOLD -->
BOTTOM CONTROL BAR
   ├─ ⏸ Pause   → PAUSED
   ├─ ▶ Play    → LISTENING
   ├─ ⟳ Refresh → Restart Session (Intro → LISTENING)
   └─ ✕ Exit    → DASHBOARD
```

## Voice Pipeline

The voice pipeline follows a strict non-streaming approach:

```
MIC → VAD → STT → VALIDATION → LLM → TTS → PLAY AUDIO
```

- **No streaming** for LLM tokens
- **No streaming** for TTS audio
- **Microphone is muted** during TTS playback
- **No barge-in** or speech interruption

## Configuration

### Face Customization
- **Colors**: White, Blue, Green, Yellow, Orange, Red, Purple
- **Eye Shapes**: Circles, Squares, Rounded Squares

### Personalities
- **Home** (default, immutable) - Warm, friendly assistant
- **Office** (default, immutable) - Professional, efficient assistant
- **Custom** - Create your own with custom behavior prompts

### AI Services
- **Dream Cloud AI** - Primary service (subscription-based)
- **OpenAI** - Custom API key
- **Gemini** - Custom API key
- **Anthropic** - Custom API key

## Getting Started

### Prerequisites
- Flutter SDK 3.9.0+
- Android Studio / Xcode for mobile builds
- Porcupine access key for wake word detection

### Installation

```bash
# Clone the repository
cd millie_mini

# Install dependencies
flutter pub get

# Run on connected device
flutter run

# Build for production
flutter build apk --release  # Android
flutter build ios --release  # iOS
flutter build web --release  # Web
```

### Wake Word Setup

To enable "Hey Millie" wake word detection:

1. Get an access key from [Picovoice Console](https://console.picovoice.ai/)
2. Train a custom wake word model for "Hey Millie"
3. Add the model file to `assets/`
4. Configure in `voice_pipeline_service.dart`

## API Integration

The voice pipeline requires implementing actual API calls in `voice_pipeline_service.dart`:

- `_speechToText()` - Connect to STT service (Whisper, Google STT, etc.)
- `_callLLM()` - Connect to LLM service (OpenAI, Anthropic, etc.)
- `_textToSpeech()` - Connect to TTS service (OpenAI TTS, Google TTS, etc.)

Each agent's configured AI service determines which APIs are called.

## Design Principles

- **Tablet-first, phone-safe** - Responsive design for all screen sizes
- **Turn-based interaction** - No interruptions, clear conversation flow
- **Error handling via modals** - Never spoken, never visual face changes
- **Short responses by default** - Longer only when explicitly requested
- **Context preservation** - Pause maintains conversation history

## License

Proprietary - All rights reserved.
