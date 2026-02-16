# Custom Quizzes Implementation Plan

## Overview
Allow users to create custom quiz "mixes" by selecting which categories to include. These appear as additional buttons on the game menu alongside the built-in categories (Riddles, Jokes, Trivia, Spelling, Random).

## User Flow
1. User goes to Dashboard → Settings → Custom Quizzes section
2. Clicks "Add" to create a new custom quiz
3. Names it (e.g., "Study Time") and checks categories (Riddles, Spelling)
4. Saves → appears in Custom Quizzes list with name and category pills
5. On Game page, custom quizzes appear below the built-in options
6. When selected, pulls randomly from only the checked categories

---

## Phase 1: Data Model & Database

### New Model: `lib/models/custom_quiz.dart`
```dart
class CustomQuiz {
  final String id;
  final String userId;
  final String name;
  final List<String> categories; // ['riddle', 'spelling', 'trivia', 'joke']
  final DateTime createdAt;
  final DateTime updatedAt;

  // fromJson, toJson, copyWith
}
```

### Database Migration: `supabase/migrations/20260215_create_custom_quizzes.sql`
```sql
CREATE TABLE custom_quizzes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  categories TEXT[] NOT NULL, -- PostgreSQL array
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS: Users can only access their own quizzes
ALTER TABLE custom_quizzes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own quizzes" ON custom_quizzes
  FOR ALL USING (auth.uid() = user_id);
```

---

## Phase 2: Provider

### New Provider: `lib/providers/custom_quiz_provider.dart`
```dart
class CustomQuizProvider extends ChangeNotifier {
  List<CustomQuiz> _quizzes = [];
  bool _isLoading = false;

  List<CustomQuiz> get quizzes => _quizzes;
  bool get isLoading => _isLoading;

  Future<void> loadQuizzes() async { ... }
  Future<CustomQuiz?> getQuizById(String id) async { ... }
  Future<void> createQuiz({name, categories}) async { ... }
  Future<void> updateQuiz({id, name, categories}) async { ... }
  Future<void> deleteQuiz(String id) async { ... }
}
```

### Register in `lib/providers/providers.dart`
Add to MultiProvider in main.dart

---

## Phase 3: Settings UI - List View

### Update: `lib/dashboard/game_settings_edit_page.dart`
Add "Custom Quizzes" section at bottom:
```
─────────────────────────
Custom Quizzes          [Add]
─────────────────────────
┌─────────────────────────┐
│ Study Time         [Edit]│
│ Riddles • Spelling       │
└─────────────────────────┘
┌─────────────────────────┐
│ Fun Mix            [Edit]│
│ Jokes • Trivia           │
└─────────────────────────┘
```

Pattern: Follow AI Services page for section header + list

---

## Phase 4: Create/Edit Quiz Page

### New Page: `lib/dashboard/edit_custom_quiz_page.dart`
```
┌─────────────────────────────┐
│ ← Create Custom Quiz        │
├─────────────────────────────┤
│                             │
│ Quiz Name                   │
│ ┌─────────────────────────┐ │
│ │ Study Time              │ │
│ └─────────────────────────┘ │
│                             │
│ Include Categories          │
│ ☑ Riddles                  │
│ ☑ Jokes                    │
│ ☐ Trivia                   │
│ ☑ Spelling                 │
│                             │
│ [    Save Quiz    ]         │
│ [    Delete       ]  ← only │
│                      on edit│
└─────────────────────────────┘
```

Structure:
- `quizId: String?` (null = create, string = edit)
- `onBack: VoidCallback`
- `onSaved: VoidCallback`
- TextEditingController for name
- Map<String, bool> for category checkboxes
- Save validates: name required, at least 1 category

---

## Phase 5: Game Menu Integration

### Update: `lib/game/game_page_content.dart`

In `_buildMenuState()`, after built-in buttons:
```dart
// Built-in categories
_GameOptionButton(icon: ..., title: 'Riddles', ...),
_GameOptionButton(icon: ..., title: 'Jokes', ...),
_GameOptionButton(icon: ..., title: 'Trivia', ...),
_GameOptionButton(icon: ..., title: 'Spelling', ...),
_GameOptionButton(icon: ..., title: 'Random', ...),

// Custom quizzes from provider
...customQuizProvider.quizzes.map((quiz) =>
  _GameOptionButton(
    icon: Icons.auto_awesome,  // or custom icon
    title: quiz.name,
    subtitle: quiz.categories.join(' • '),
    isSelected: selectedCategory == 'custom:${quiz.id}',
    onTap: () => voiceProvider.selectLessonCategory('custom:${quiz.id}'),
  ),
),
```

---

## Phase 6: GameController - Custom Quiz Logic

### Update: `lib/game/game_controller.dart`

In `_getNextItem()`:
```dart
Future<LessonItem?> _getNextItem(String category) async {
  // Handle custom quiz
  if (category.startsWith('custom:')) {
    return _getNextFromCustomQuiz(category.substring(7)); // quiz ID
  }

  // Existing logic for spelling, random, specific categories
  ...
}

Future<LessonItem?> _getNextFromCustomQuiz(String quizId) async {
  // Load quiz from provider
  final quiz = await _customQuizProvider.getQuizById(quizId);
  if (quiz == null) return null;

  // Randomly pick a category from the quiz's categories
  final randomCategory = quiz.categories[Random().nextInt(quiz.categories.length)];

  // Route to appropriate source
  if (randomCategory == 'spelling') {
    return _getNextSpellingWord();
  } else {
    return _getNextFromGameQuestions(randomCategory);
  }
}
```

### Update intro text:
```dart
String _getIntroText(String category) {
  if (category.startsWith('custom:')) {
    return "Let's play! I'll ask you some questions from your custom mix.";
  }
  // ... existing cases
}
```

---

## Files Summary

### New Files
1. `lib/models/custom_quiz.dart` - Data model
2. `lib/providers/custom_quiz_provider.dart` - State management
3. `lib/dashboard/edit_custom_quiz_page.dart` - Create/Edit page
4. `supabase/migrations/20260215_create_custom_quizzes.sql` - Database table

### Modified Files
1. `lib/providers/providers.dart` - Register new provider
2. `lib/main.dart` - Add provider to MultiProvider
3. `lib/dashboard/game_settings_edit_page.dart` - Add Custom Quizzes section
4. `lib/game/game_page_content.dart` - Show custom quiz buttons
5. `lib/game/game_controller.dart` - Handle custom quiz category selection

---

## Implementation Order

1. Database migration (create table)
2. CustomQuiz model
3. CustomQuizProvider
4. Register provider in main.dart
5. Edit Custom Quiz page (create/edit form)
6. Game Settings page (add section with list)
7. Game menu (show custom quiz buttons)
8. GameController (handle custom quiz selection)
9. Test full flow

---

## Future Enhancements (Not in Scope)
- Custom icons/colors for quizzes
- Reorder quizzes
- Share quizzes between users
- Quiz-specific difficulty override
