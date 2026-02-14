import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';

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
  
  /// Always get current user ID from Supabase
  String? get _userId => SupabaseConfig.currentUser?.id;
  
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      debugPrint('AgentProvider init - userId: $_userId');
      
      if (_userId != null) {
        // Try to load from Supabase first
        await _loadAgentsFromSupabase();
      }
      
      // Fallback to local storage if no agents loaded
      if (_agents.isEmpty) {
        _agents = await _storage.getAgents();
        debugPrint('Loaded ${_agents.length} agents from local storage');
      }
      
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
          id: _uuid.v4(), // Use proper UUID instead of hardcoded ID
          name: 'Millie',
          faceColor: FaceColor.white,
          eyeShape: EyeShape.roundedSquares,
          aiServiceId: 'dream_cloud_default',
          voice: 'Alloy',
          personalityId: 'default_home',
          introMessage: 'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        _agents = [defaultAgent];
        _activeAgent = defaultAgent;
        await _saveAgentsLocal();
        // Sync default agent to Supabase
        await _insertAgentToSupabase(defaultAgent);
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
  
  Future<void> _loadAgentsFromSupabase() async {
    if (_userId == null) return;
    
    try {
      debugPrint('Loading agents from Supabase for user: $_userId');
      final response = await SupabaseConfig.client
          .from('agents')
          .select()
          .eq('user_id', _userId!)
          .order('is_active', ascending: false)
          .order('updated_at', ascending: false);
      
      debugPrint('Supabase agents response: $response');
      
      if (response != null && (response as List).isNotEmpty) {
        _agents = response.map<Agent>((row) {
          // Fix old default values to new defaults (white=0, roundedSquares=2)
          int faceColorValue = row['face_color'] as int? ?? 0;
          int eyeShapeValue = row['eye_shape'] as int? ?? 2;
          bool needsUpdate = false;
          Map<String, dynamic> updateData = {};
          
          // Fix blue (1) to white (0) - old default
          if (faceColorValue == 1) {
            faceColorValue = 0;
            updateData['face_color'] = 0;
            needsUpdate = true;
          }
          
          // Fix circles (0) to rounded squares (2) - old default
          if (eyeShapeValue == 0) {
            eyeShapeValue = 2;
            updateData['eye_shape'] = 2;
            needsUpdate = true;
          }
          
          // Update in Supabase if needed
          if (needsUpdate) {
            updateData['updated_at'] = DateTime.now().toIso8601String();
            SupabaseConfig.client
                .from('agents')
                .update(updateData)
                .eq('id', row['id'] as String)
                .then((_) => debugPrint('Fixed agent defaults for ${row['id']}: $updateData'))
                .catchError((e) => debugPrint('Error fixing agent defaults: $e'));
          }
          
          return Agent(
            id: row['id'] as String,
            name: row['name'] as String? ?? 'Millie',
            faceColor: FaceColor.values[faceColorValue],
            eyeShape: EyeShape.values[eyeShapeValue],
            aiServiceId: row['ai_service_id'] as String? ?? 'dream_cloud_default',
            voice: row['voice'] as String? ?? 'Alloy',
            personalityId: row['personality_id'] as String? ?? 'default_home',
            introMessage: row['intro_message'] as String? ?? 'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?',
            isActive: row['is_active'] as bool? ?? false,
            createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: DateTime.tryParse(row['updated_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
        
        debugPrint('Loaded ${_agents.length} agents from Supabase');
        
        // Also save to local storage for offline access
        await _storage.saveAgents(_agents);
      } else {
        debugPrint('No agents found in Supabase');
      }
    } catch (e) {
      debugPrint('Error loading agents from Supabase: $e');
    }
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
    
    // Update active states in Supabase
    await _updateAgentActiveStates();
    
    notifyListeners();
  }
  
  Future<Agent> createAgent({
    required String name,
    required FaceColor faceColor,
    required EyeShape eyeShape,
    required String aiServiceId,
    required String voice,
    required String personalityId,
    String? introMessage,
  }) async {
    final now = DateTime.now();
    final agent = Agent(
      id: _uuid.v4(),
      name: name,
      faceColor: faceColor,
      eyeShape: eyeShape,
      aiServiceId: aiServiceId,
      voice: voice,
      personalityId: personalityId,
      introMessage: introMessage ?? 'Hello {username}, it\'s me {agent_name} your personal AI Agent. How can I help you?',
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
    
    // Insert new agent to Supabase
    final success = await _insertAgentToSupabase(agent);
    debugPrint('Agent insert to Supabase success: $success');
    
    // Update other agents' active states
    await _updateAgentActiveStates();
    
    notifyListeners();
    
    return agent;
  }
  
  Future<void> updateAgent({
    required String agentId,
    String? name,
    FaceColor? faceColor,
    EyeShape? eyeShape,
    String? aiServiceId,
    String? voice,
    String? personalityId,
    String? introMessage,
  }) async {
    final index = _agents.indexWhere((a) => a.id == agentId);
    if (index == -1) return;
    
    final updated = _agents[index].copyWith(
      name: name,
      faceColor: faceColor,
      eyeShape: eyeShape,
      aiServiceId: aiServiceId,
      voice: voice,
      personalityId: personalityId,
      introMessage: introMessage,
      updatedAt: DateTime.now(),
    );
    
    _agents[index] = updated;
    
    if (_activeAgent?.id == agentId) {
      _activeAgent = updated;
    }
    
    await _saveAgentsLocal();
    
    // Update in Supabase
    await _updateAgentInSupabase(updated);
    
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
    
    // Delete from Supabase
    await _deleteAgentFromSupabase(agentId);
    
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
  
  Future<void> _updateAgentActiveStates() async {
    if (_userId == null) return;
    
    for (final agent in _agents) {
      try {
        await SupabaseConfig.client
            .from('agents')
            .update({
              'is_active': agent.isActive,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', agent.id)
            .eq('user_id', _userId!);
      } catch (e) {
        debugPrint('Error updating agent active state for ${agent.id}: $e');
      }
    }
  }
  
  Future<bool> _insertAgentToSupabase(Agent agent) async {
    final userId = _userId;
    debugPrint('_insertAgentToSupabase - Checking user...');
    debugPrint('  SupabaseConfig.currentUser: ${SupabaseConfig.currentUser}');
    debugPrint('  SupabaseConfig.isAuthenticated: ${SupabaseConfig.isAuthenticated}');
    debugPrint('  userId: $userId');
    
    if (userId == null) {
      debugPrint('Cannot insert agent: no user ID');
      return false;
    }
    
    try {
      debugPrint('Inserting agent to Supabase: ${agent.id}');
      debugPrint('User ID: $userId');
      debugPrint('Agent data: name=${agent.name}, faceColor=${agent.faceColor.index}');
      
      final response = await SupabaseConfig.client.from('agents').insert({
        'id': agent.id,
        'user_id': userId,
        'name': agent.name,
        'face_color': agent.faceColor.index,
        'eye_shape': agent.eyeShape.index,
        'ai_service_id': agent.aiServiceId,
        'voice': agent.voice,
        'personality_id': agent.personalityId,
        'intro_message': agent.introMessage,
        'is_active': agent.isActive,
        'created_at': agent.createdAt.toIso8601String(),
        'updated_at': agent.updatedAt.toIso8601String(),
      }).select();
      
      debugPrint('Insert response: $response');
      return true;
    } catch (e) {
      debugPrint('Error inserting agent to Supabase: $e');
      return false;
    }
  }
  
  Future<void> _updateAgentInSupabase(Agent agent) async {
    if (_userId == null) return;
    
    try {
      await SupabaseConfig.client
          .from('agents')
          .update({
            'name': agent.name,
            'face_color': agent.faceColor.index,
            'eye_shape': agent.eyeShape.index,
            'ai_service_id': agent.aiServiceId,
            'voice': agent.voice,
            'personality_id': agent.personalityId,
            'intro_message': agent.introMessage,
            'is_active': agent.isActive,
            'updated_at': agent.updatedAt.toIso8601String(),
          })
          .eq('id', agent.id)
          .eq('user_id', _userId!);
      
      debugPrint('Agent updated in Supabase: ${agent.id}');
    } catch (e) {
      debugPrint('Error updating agent in Supabase: $e');
    }
  }
  
  Future<void> _deleteAgentFromSupabase(String agentId) async {
    if (_userId == null) return;
    
    try {
      await SupabaseConfig.client
          .from('agents')
          .delete()
          .eq('id', agentId)
          .eq('user_id', _userId!);
      
      debugPrint('Agent deleted from Supabase: $agentId');
    } catch (e) {
      debugPrint('Error deleting agent from Supabase: $e');
    }
  }
  
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
