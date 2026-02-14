# Chunked Processing Implementation Plan

## Goal
Process and play LLM responses in chunks to reduce perceived latency. Instead of waiting for entire response → TTS → playback, we'll:
- Split response into sentences
- Generate TTS for first sentence immediately
- Play first chunk while generating remaining chunks
- Queue and play chunks sequentially
- Resume listening while audio is playing

## Implementation Steps

1. **Add audio queue management**
   - Queue for multiple audio files
   - Sequential playback
   - Clear queue when needed

2. **Add sentence splitting**
   - Split text by sentence boundaries (., !, ?)
   - Handle edge cases (abbreviations, etc.)
   - Minimum chunk size to avoid too many small chunks

3. **Modify processAudio to use chunked processing**
   - After LLM response, split into chunks
   - Generate TTS for first chunk immediately
   - Start playing first chunk
   - Generate remaining chunks in parallel
   - Queue for sequential playback
   - Resume listening after first chunk plays

4. **Keep existing functionality**
   - All error handling
   - Pause/resume triggers
   - Wake word detection
   - Continuous mode

## Files to Modify
- `lib/services/voice_pipeline_service.dart` - Add chunked processing logic

