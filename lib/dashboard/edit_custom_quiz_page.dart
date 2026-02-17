import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/custom_quiz_provider.dart';
import '../utils/constants.dart';
import '../widgets/widgets.dart';

class EditCustomQuizPage extends StatefulWidget {
  final String? quizId; // null = create, string = edit
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const EditCustomQuizPage({
    super.key,
    this.quizId,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<EditCustomQuizPage> createState() => _EditCustomQuizPageState();
}

class _EditCustomQuizPageState extends State<EditCustomQuizPage> {
  final _nameController = TextEditingController();
  final Map<String, bool> _selectedCategories = {
    // Fun Games
    'riddle': false,
    'joke': false,
    'trivia': false,
    'truefalse': false,
    // Learning Games
    'spelling': false,
    'letters': false,
    'shapes': false,
    'math': false,
    'animals': false,
  };
  bool _isLoading = false;
  bool _isDeleting = false;

  bool get isNewQuiz => widget.quizId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQuiz();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _loadQuiz() {
    if (widget.quizId == null) return;

    final provider = context.read<CustomQuizProvider>();
    final quiz = provider.getQuizById(widget.quizId!);

    if (quiz != null) {
      _nameController.text = quiz.name;
      for (final category in quiz.categories) {
        if (_selectedCategories.containsKey(category)) {
          _selectedCategories[category] = true;
        }
      }
      setState(() {});
    }
  }

  List<String> get _selectedCategoryList {
    return _selectedCategories.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
  }

  bool get _isValid {
    return _nameController.text.trim().isNotEmpty &&
        _selectedCategoryList.isNotEmpty;
  }

  Future<void> _handleSave() async {
    if (!_isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name and select at least one category'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<CustomQuizProvider>();
      final name = _nameController.text.trim();
      final categories = _selectedCategoryList;

      if (isNewQuiz) {
        await provider.createQuiz(name: name, categories: categories);
      } else {
        await provider.updateQuiz(
          quizId: widget.quizId!,
          name: name,
          categories: categories,
        );
      }

      if (!mounted) return;

      widget.onSaved();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving quiz: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete Quiz',
      message: 'Are you sure you want to delete this custom quiz?',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDangerous: true,
      confirmColor: AppColors.primaryOrange,
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final provider = context.read<CustomQuizProvider>();
      await provider.deleteQuiz(widget.quizId!);

      if (!mounted) return;

      widget.onSaved();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDeleting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting quiz: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            isNewQuiz ? 'Create Custom Quiz' : 'Edit Custom Quiz',
            style: AppTextStyles.heading2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Quiz Name
              AppTextField(
                controller: _nameController,
                label: 'Quiz Name',
                hint: 'e.g., Study Time, Fun Mix',
                textCapitalization: TextCapitalization.words,
              ),

              const SizedBox(height: AppSpacing.xl),

              // Categories section
              const Text(
                'Include Categories',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Select which categories to include in this quiz mix.',
                style: AppTextStyles.bodySmall,
              ),

              const SizedBox(height: AppSpacing.lg),

              // Fun Games section
              _buildSectionHeader('Fun Games', Icons.celebration),
              _buildCategoryCheckbox('riddle', 'Riddles', Icons.psychology),
              _buildCategoryCheckbox('joke', 'Jokes', Icons.sentiment_very_satisfied),
              _buildCategoryCheckbox('trivia', 'Trivia', Icons.quiz_outlined),
              _buildCategoryCheckbox('truefalse', 'True or False', Icons.check_circle_outline),

              const SizedBox(height: AppSpacing.lg),

              // Learning Games section
              _buildSectionHeader('Learning Games', Icons.school),
              _buildCategoryCheckbox('spelling', 'Spelling', Icons.spellcheck),
              _buildCategoryCheckbox('letters', 'Letters', Icons.abc),
              _buildCategoryCheckbox('shapes', 'Shapes', Icons.category),
              _buildCategoryCheckbox('math', 'Math', Icons.calculate),
              _buildCategoryCheckbox('animals', 'Animals', Icons.pets),

              const SizedBox(height: AppSpacing.xl),

              // Save button (blue)
              AppButton(
                label: isNewQuiz ? 'Create Quiz' : 'Save Changes',
                onPressed: (_isLoading || _isDeleting) ? null : _handleSave,
                isLoading: _isLoading,
                isFullWidth: true,
                customColor: AppColors.dreamCloudBlue,
              ),

              // Delete button (orange, only for existing quizzes)
              if (!isNewQuiz) ...[
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Delete Quiz',
                  onPressed: (_isLoading || _isDeleting) ? null : _handleDelete,
                  isLoading: _isDeleting,
                  isFullWidth: true,
                  customColor: AppColors.primaryOrange,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.dreamCloudBlue),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.dreamCloudBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCheckbox(String key, String label, IconData icon) {
    return CheckboxListTile(
      value: _selectedCategories[key],
      onChanged: (value) {
        setState(() {
          _selectedCategories[key] = value ?? false;
        });
      },
      title: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade700),
          const SizedBox(width: AppSpacing.sm),
          Text(label),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.dreamCloudBlue,
    );
  }
}
