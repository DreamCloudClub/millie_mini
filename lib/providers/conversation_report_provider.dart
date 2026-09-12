import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/conversation_report.dart';
import '../services/storage_service.dart';

class ConversationReportProvider extends ChangeNotifier {
  final StorageService _storage;

  List<ConversationReport> _reports = [];
  ConversationReport? _activeSession; // Currently running session
  bool _isLoading = false;
  String? _error;

  ConversationReportProvider(this._storage);

  // Getters
  List<ConversationReport> get reports => _reports;
  List<ConversationReport> get completedReports =>
      _reports.where((r) => r.isComplete).toList();
  ConversationReport? get activeSession => _activeSession;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasActiveSession => _activeSession != null;

  // Initialize
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _storage.getString('conversation_reports');
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        _reports = decoded
            .map((d) => ConversationReport.fromJson(d as Map<String, dynamic>))
            .toList();

        // Sort by startedAt descending (newest first)
        _reports.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      }
    } catch (e) {
      debugPrint('Error loading conversation reports: $e');
      _error = 'Failed to load reports';
    }

    _isLoading = false;
    notifyListeners();
  }

  // Save to storage
  Future<void> _save() async {
    final data = _reports.map((r) => r.toJson()).toList();
    await _storage.saveString('conversation_reports', jsonEncode(data));
  }

  // Start a new session
  ConversationReport startSession({
    required String templateId,
    required String templateName,
  }) {
    _activeSession = ConversationReport.start(
      templateId: templateId,
      templateName: templateName,
    );
    notifyListeners();
    return _activeSession!;
  }

  // Record a response in the active session
  void recordResponse(String key, String value) {
    if (_activeSession == null) return;

    _activeSession = _activeSession!.addResponse(key, value);
    notifyListeners();
  }

  // Complete and save the session
  Future<ConversationReport?> completeSession() async {
    if (_activeSession == null) return null;

    final completed = _activeSession!.complete();
    _reports.insert(0, completed); // Add to front (newest first)
    _activeSession = null;

    await _save();
    notifyListeners();
    return completed;
  }

  // Cancel the active session without saving
  void cancelSession() {
    _activeSession = null;
    notifyListeners();
  }

  // Get report by ID
  ConversationReport? getReportById(String id) {
    try {
      return _reports.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  // Get reports for a specific template
  List<ConversationReport> getReportsForTemplate(String templateId) {
    return _reports.where((r) => r.templateId == templateId).toList();
  }

  // Delete a report
  Future<void> deleteReport(String reportId) async {
    _reports.removeWhere((r) => r.id == reportId);
    await _save();
    notifyListeners();
  }

  // Clear all reports
  Future<void> clearAllReports() async {
    _reports.clear();
    await _save();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
