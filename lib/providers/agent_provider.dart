import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';

class AgentProvider extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();

  List<Agent> _agents = [];
  Agent? _activeAgent;
  bool _isLoading = false;
  String? _error;

  AgentProvider(this._storage);

  List<Agent> get agents => _agents;
  Agent? get activeAgent => _activeAgent;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Check if an agent is the default Millie agent (protected from deletion)
  /// The default agent is identified as the oldest agent (earliest createdAt)
  bool isDefaultMillieAgent(String agentId) {
    try {
      if (_agents.isEmpty) {
        return false;
      }

      // Find the oldest agent (earliest createdAt)
      final sortedAgents = List<Agent>.from(_agents);
      sortedAgents.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final oldestAgent = sortedAgents.first;

      // The default agent is the oldest one
      return agentId == oldestAgent.id;
    } catch (e) {
      // Agent not found, return false
      return false;
    }
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint('AgentProvider init - loading from local storage');

      // Load agents from local storage
      _agents = await _storage.getAgents();
      debugPrint('Loaded ${_agents.length} agents from local storage');

      // Get active agent
      final activeId = await _storage.getActiveAgentId();
      if (activeId != null && _agents.isNotEmpty) {
        _activeAgent = _agents.firstWhere(
          (a) => a.id == activeId,
          orElse: () => _agents.first,
        );
      } else if (_agents.isNotEmpty) {
        _activeAgent = _agents.firstWhere(
          (a) => a.isActive,
          orElse: () => _agents.first,
        );
      }

      // Ensure at least one agent exists - create with proper UUID
      if (_agents.isEmpty) {
        debugPrint('No agents found, creating default agent');
        final now = DateTime.now();
        final defaultAgent = Agent(
          id: _uuid.v4(),
          name: 'Millie',
          faceColor: FaceColor.white,
          eyeShape: EyeShape.roundedSquares,
          aiServiceId: 'openai_default',
          voice: 'Alloy',
          personalityId: 'default_home',
          introMessage:
              'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        _agents = [defaultAgent];
        _activeAgent = defaultAgent;
        await _saveAgentsLocal();
      }
    } catch (e) {
      debugPrint('Agent init error: $e');
      _error = 'Failed to load agents';
      // Fallback to default agent
      if (_agents.isEmpty) {
        _agents = [Agent.defaultAgent()];
        _activeAgent = _agents.first;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setActiveAgent(String agentId) async {
    final agent = _agents.firstWhere((a) => a.id == agentId);

    // Update all agents to reflect active state
    _agents = _agents.map((a) {
      return a.copyWith(
        isActive: a.id == agentId,
        updatedAt: DateTime.now(),
      );
    }).toList();

    _activeAgent = agent.copyWith(isActive: true);

    // Move active agent to top
    _agents.removeWhere((a) => a.id == agentId);
    _agents.insert(0, _activeAgent!);

    await _storage.setActiveAgentId(agentId);
    await _saveAgentsLocal();

    notifyListeners();
  }

  Future<Agent> createAgent({
    required String name,
    required FaceColor faceColor,
    required EyeShape eyeShape,
    String? faceImageId,
    String? customFaceId,
    required String aiServiceId,
    required String voice,
    String voiceMode = 'turn_taking',
    required String personalityId,
    String? introMessage,
  }) async {
    final now = DateTime.now();
    final agent = Agent(
      id: _uuid.v4(),
      name: name,
      faceColor: faceColor,
      eyeShape: eyeShape,
      faceImageId: faceImageId,
      customFaceId: customFaceId,
      aiServiceId: aiServiceId,
      voice: voice,
      voiceMode: voiceMode,
      personalityId: personalityId,
      introMessage: introMessage ??
          'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    debugPrint('Creating new agent: ${agent.id} - ${agent.name}');

    // Deactivate other agents
    _agents = _agents.map((a) => a.copyWith(isActive: false)).toList();

    // Add new agent at the top
    _agents.insert(0, agent);
    _activeAgent = agent;

    await _storage.setActiveAgentId(agent.id);
    await _saveAgentsLocal();

    notifyListeners();

    return agent;
  }

  Future<void> updateAgent({
    required String agentId,
    String? name,
    FaceColor? faceColor,
    EyeShape? eyeShape,
    String? faceImageId,
    bool clearFaceImageId = false,
    String? customFaceId,
    bool clearCustomFaceId = false,
    String? aiServiceId,
    String? voice,
    String? voiceMode,
    String? personalityId,
    String? introMessage,
  }) async {
    final index = _agents.indexWhere((a) => a.id == agentId);
    if (index == -1) return;

    final updated = _agents[index].copyWith(
      name: name,
      faceColor: faceColor,
      eyeShape: eyeShape,
      faceImageId: faceImageId,
      clearFaceImageId: clearFaceImageId,
      customFaceId: customFaceId,
      clearCustomFaceId: clearCustomFaceId,
      aiServiceId: aiServiceId,
      voice: voice,
      voiceMode: voiceMode,
      personalityId: personalityId,
      introMessage: introMessage,
      updatedAt: DateTime.now(),
    );

    _agents[index] = updated;

    if (_activeAgent?.id == agentId) {
      _activeAgent = updated;
    }

    await _saveAgentsLocal();

    notifyListeners();
  }

  Future<void> deleteAgent(String agentId) async {
    // Don't delete if it's the default Millie agent
    if (isDefaultMillieAgent(agentId)) {
      _error = 'Cannot delete the default Millie agent';
      notifyListeners();
      return;
    }

    // Don't delete if it's the last agent
    if (_agents.length <= 1) {
      _error = 'Cannot delete the last agent';
      notifyListeners();
      return;
    }

    _agents.removeWhere((a) => a.id == agentId);

    // If deleted agent was active, activate the first one
    if (_activeAgent?.id == agentId) {
      _activeAgent = _agents.first.copyWith(isActive: true);
      _agents[0] = _activeAgent!;
      await _storage.setActiveAgentId(_activeAgent!.id);
    }

    await _saveAgentsLocal();

    notifyListeners();
  }

  Agent? getAgentById(String id) {
    try {
      return _agents.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAgentsLocal() async {
    await _storage.saveAgents(_agents);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
