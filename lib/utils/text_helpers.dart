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


/// Formats a phone number for on-screen display.
///
/// Speech transcriptions arrive as bare digit strings ("5551234567") or with
/// stray words and punctuation, so strip to digits and group them the way a
/// person expects to read a phone number back. Anything that doesn't look like
/// a phone number is returned trimmed but otherwise untouched.
String formatPhoneNumberForDisplay(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

  // US/Canada with a leading country code: 1-555-123-4567
  if (digits.length == 11 && digits.startsWith('1')) {
    final local = digits.substring(1);
    return '(${local.substring(0, 3)}) ${local.substring(3, 6)}-${local.substring(6)}';
  }

  // US/Canada: 555-123-4567
  if (digits.length == 10) {
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  }

  // Local seven-digit number
  if (digits.length == 7) {
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  }

  // International numbers have no single grouping convention - keep the digits
  // and the country-code marker, but don't invent separators.
  if (digits.length > 11) {
    return '+$digits';
  }

  return raw.trim();
}

/// Removes markdown formatting the model sometimes adds (**bold**, headings,
/// links, code ticks). Replies are shown as plain text and spoken aloud, so
/// the markers would otherwise appear literally and be read out.
String stripMarkdown(String text) {
  return text
      // [label](url) -> label
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      // **bold** / __bold__
      .replaceAll(RegExp(r'\*\*|__'), '')
      // *italic* / _italic_ - only when wrapped around words, so snake_case
      // and "5 * 3" survive
      .replaceAllMapped(
        RegExp(r'(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s.,!?;:)]|$)', multiLine: true),
        (m) => '${m[1]}${m[2]}',
      )
      // "## Heading" - requires the space, so "#8 screws" is untouched
      .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
      .replaceAll('`', '');
}

const Map<String, String> _spokenFractions = {
  '1/2': 'a half',
  '1/3': 'a third',
  '1/4': 'a quarter',
  '3/4': 'three quarters',
  '1/8': 'an eighth',
  '3/8': 'three eighths',
  '5/8': 'five eighths',
  '7/8': 'seven eighths',
  '5/16': 'five sixteenths',
  '23/32': 'twenty-three thirty-seconds',
};

/// Prepares text for text-to-speech.
///
/// Beyond stripping markdown, this rewrites hardware-store notation that TTS
/// mangles: "#8 x 2-1/2 in." becomes "number 8 by 2 and a half inch". It also
/// removes the periods in unit abbreviations, which matters because speech is
/// split into sentences on periods - "in." would cut a product name in half.
String toSpeakableText(String text) {
  var result = stripMarkdown(text)
      // Bullet markers at line start
      .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
      .replaceAll('°F', ' degrees')
      .replaceAll('°C', ' degrees')
      .replaceAll('°', ' degrees')
      .replaceAll('℉', ' degrees')
      .replaceAll('℃', ' degrees');

  // Screw/nail gauge: #8 -> number 8
  result = result.replaceAllMapped(RegExp(r'#(\d+)'), (m) => 'number ${m[1]}');

  // Mixed numbers: 2-1/2 -> 2 and a half
  result = result.replaceAllMapped(RegExp(r'\b(\d+)-(\d+/\d+)\b'), (m) {
    final fraction = _spokenFractions[m[2]];
    return fraction == null ? m[0]! : '${m[1]} and $fraction';
  });

  // Bare fractions: 1/2 -> a half. Unknown ones (12/2 wire) are left alone.
  result = result.replaceAllMapped(RegExp(r'(?<![\d/])(\d+/\d+)(?![\d/])'), (m) {
    return _spokenFractions[m[1]] ?? m[0]!;
  });

  // "a 1/2 in." became "a a half" - keep a single article
  result = result.replaceAllMapped(
    RegExp(r'\b(?:a|an)\s+(a|an)\s+(?=half|third|quarter|eighth)', caseSensitive: false),
    (m) => '${m[1]} ',
  );

  // Dimensions: 2 in. x 4 in. -> 2 in. by 4 in.
  result = result.replaceAll(RegExp(r'\s+x\s+(?=[\d#a-z])'), ' by ');

  // Unit abbreviations, only right after a number (or square/cubic) so a
  // sentence ending in "put it in." is untouched.
  const units = {
    'sq': 'square',
    'cu': 'cubic',
    'in': 'inch',
    'ft': 'foot',
    'yd': 'yard',
    'gal': 'gallon',
    'lb': 'pound',
    'lbs': 'pounds',
    'oz': 'ounce',
  };
  units.forEach((abbr, word) {
    result = result.replaceAllMapped(
      RegExp('(?<=(?:\\d|half|third|quarter|quarters|eighth|eighths|sixteenths|seconds|square|cubic)\\s?)$abbr\\.',
          caseSensitive: false),
      (_) => word,
    );
  });

  return result.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}
