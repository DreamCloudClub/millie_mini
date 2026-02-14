enum VoiceState {
  /// System is not active (on dashboard)
  sleep,
  
  /// Microphone is active, listening for user speech
  listening,
  
  /// Processing STT result and calling LLM
  processing,
  
  /// Playing TTS audio response
  speaking,
  
  /// System is paused but context preserved
  paused,
}

enum FaceState {
  /// Slightly dim static
  idle,
  
  /// Slightly brighter, minimal breathing pulse
  listening,
  
  /// Static, fully bright
  processing,
  
  /// Gentle rhythmic pulse
  speaking,
}

extension VoiceStateExtension on VoiceState {
  bool get isMicActive => this == VoiceState.listening;
  
  bool get canAcceptInput => this == VoiceState.listening;
  
  bool get isSessionActive => 
      this == VoiceState.listening || 
      this == VoiceState.processing || 
      this == VoiceState.speaking ||
      this == VoiceState.paused;
  
  FaceState get toFaceState {
    switch (this) {
      case VoiceState.sleep:
        return FaceState.idle;
      case VoiceState.listening:
        return FaceState.listening;
      case VoiceState.processing:
        return FaceState.processing;
      case VoiceState.speaking:
        return FaceState.speaking;
      case VoiceState.paused:
        return FaceState.idle;
    }
  }
  
  String get statusText {
    switch (this) {
      case VoiceState.sleep:
        return 'Ready';
      case VoiceState.listening:
        return 'Listening...';
      case VoiceState.processing:
        return 'Thinking...';
      case VoiceState.speaking:
        return 'Speaking...';
      case VoiceState.paused:
        return 'Paused';
    }
  }
}

