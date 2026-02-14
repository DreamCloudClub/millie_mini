/// Helper functions for text processing and placeholder replacement

/// Safely replaces {username} placeholder in intro messages
/// Only replaces the exact {username} placeholder, ignores malformed placeholders
String replaceUsernamePlaceholder(String text, String username) {
  // Only replace the exact {username} placeholder
  // This prevents issues if users accidentally type {username or username} etc.
  return text.replaceAll('{username}', username);
}

/// Replaces both {username} and {agent_name} placeholders in intro messages
String replaceIntroMessagePlaceholders(
  String text,
  String? username,
  String? agentName,
) {
  String result = text;
  
  // Replace {username} placeholder
  if (username != null && username.isNotEmpty) {
    result = result.replaceAll('{username}', username);
  } else {
    result = result.replaceAll('{username}', 'there');
  }
  
  // Replace {agent_name} placeholder
  if (agentName != null && agentName.isNotEmpty) {
    result = result.replaceAll('{agent_name}', agentName);
  } else {
    result = result.replaceAll('{agent_name}', 'Millie');
  }
  
  return result;
}

/// Replaces {agent_name} placeholder in personality prompts
String replaceAgentNamePlaceholder(String text, String? agentName) {
  if (agentName != null && agentName.isNotEmpty) {
    return text.replaceAll('{agent_name}', agentName);
  } else {
    return text.replaceAll('{agent_name}', 'Millie');
  }
}

/// Validates intro message for common issues
String? validateIntroMessage(String? message) {
  if (message == null || message.trim().isEmpty) {
    return 'Intro message cannot be empty';
  }
  
  if (message.length > 500) {
    return 'Intro message is too long (max 500 characters)';
  }
  
  // Warn about unmatched braces (but don't block)
  final openBraces = '{'.allMatches(message).length;
  final closeBraces = '}'.allMatches(message).length;
  if (openBraces != closeBraces) {
    // Don't return error, just let them know in the UI
    // The replaceUsernamePlaceholder function will safely ignore malformed placeholders
  }
  
  return null; // Valid
}

