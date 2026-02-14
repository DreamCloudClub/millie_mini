# Usage Tracking Integration Complete

## What Was Done

The usage tracking system has been fully integrated into the voice pipeline. Here's what was implemented:

### 1. OpenAI Service Updates (`lib/services/openai_service.dart`)
- **Updated `callChatCompletions()`** to return a `ChatCompletionResponse` object containing:
  - Response content
  - Token usage (`promptTokens`, `completionTokens`, `totalTokens`)
- Extracts token usage from OpenAI API response

### 2. Voice Pipeline Service Updates (`lib/services/voice_pipeline_service.dart`)
- **Added user context fields**:
  - `_currentUserId`
  - `_currentUserEmail`
  - `_currentSubscriptionStatus`
- **Updated method signatures**:
  - `startListening()` now accepts `userId`, `userEmail`, `subscriptionStatus`
  - `playIntroMessage()` now accepts these same parameters
- **Updated `_callLLM()` method**:
  - **Before LLM call**: Checks usage limit using `UsageTrackingService.checkUsageLimit()`
    - Estimates tokens needed based on transcription length
    - Shows friendly error if limit exceeded
    - Allows calls to proceed if no user info available (for development/testing)
  - **After LLM call**: Records token usage using `UsageTrackingService.recordUsage()`
    - Uses actual token count from OpenAI API response
    - Non-blocking (errors don't fail the voice call)

### 3. Voice Provider Updates (`lib/providers/voice_provider.dart`)
- **Updated `startSession()`** to accept and pass user info:
  - `userId`
  - `userEmail`
  - `subscriptionStatus`

### 4. Face Page Updates (`lib/face/face_page.dart`)
- **Updated `_startSession()`** to:
  - Get `userId` and `userEmail` from `AuthProvider`
  - Get `subscriptionStatus` from `AIServiceProvider.dreamCloudService`
  - Pass all user info to `voiceProvider.startSession()`

## How It Works

### Flow:
1. **User starts voice session** → Face page gets user info and subscription status
2. **User speaks** → Recording → STT → Transcription received
3. **Before LLM call**:
   - Estimates tokens needed
   - Checks usage limit in Supabase
   - If limit exceeded → Shows error, stops processing
   - If within limit → Proceeds to LLM call
4. **LLM call** → OpenAI API returns response + token usage
5. **After LLM call**:
   - Records actual token usage to Supabase
   - Returns response to user
6. **TTS → Play Audio** → User hears response

### Error Handling:
- **Usage check fails**: Call proceeds (allows development/testing without user info)
- **Usage recording fails**: Call succeeds, error logged (non-blocking)
- **Limit exceeded**: Friendly error message shown, call blocked

## Token Limits Enforced

| Subscription | Monthly Limit |
|--------------|---------------|
| Holder       | 8M tokens     |
| Basic        | 8M tokens     |
| Pro          | 16M tokens    |
| Trial        | 8M tokens     |
| Inactive     | 0 tokens      |

## Testing Checklist

- [ ] Test with Basic subscription - verify 8M token limit
- [ ] Test with Pro subscription - verify 16M token limit
- [ ] Test with Holder role - verify 8M token limit
- [ ] Test limit exceeded scenario - verify error message appears
- [ ] Test usage recording - verify tokens are tracked in Supabase
- [ ] Test monthly reset - verify new month creates new usage record
- [ ] Test without user info - verify app still works (development mode)
- [ ] Test error scenarios - verify graceful handling of API failures

## Usage Display (Future Enhancement)

Consider adding a usage display widget to show:
- Current month's usage: "2.5M / 8M tokens"
- Progress bar
- Days until reset
- Link to upgrade (if near limit)

This could be added to:
- Dashboard page
- AI Account Settings page
- Control bar modal

## Notes

- Token estimation is rough (4 chars per token) - actual usage from API is more accurate
- Usage checks happen before every LLM call
- Usage recording happens after every successful LLM call
- The system gracefully handles missing user info (useful for development)
- Monthly reset happens automatically when year-month changes

## Next Steps

1. **Test the integration** with real subscriptions
2. **Monitor usage** in Supabase `usage_tracking` table
3. **Add usage display UI** (optional but recommended)
4. **Set up alerts** if desired (e.g., email when user reaches 80% of limit)

