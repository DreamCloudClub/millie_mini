import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../inventory/inventory_seed.dart';
import '../models/inventory_item.dart';
import '../services/storage_service.dart';

class InventoryProvider extends ChangeNotifier {
  static const String _storageKey = 'inventory_items';

  final StorageService _storage;

  List<InventoryItem> _items = [];
  bool _isLoading = false;
  String? _error;

  InventoryProvider(this._storage);

  // Getters
  List<InventoryItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get lowStockCount => _items.where((i) => i.isLowStock).length;
  int get outOfStockCount => _items.where((i) => i.isOutOfStock).length;

  List<String> get departments {
    final names = _items.map((i) => i.department).toSet().toList();
    names.sort();
    return names;
  }

  // Initialize - first launch starts with the demo catalog
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _storage.getString(_storageKey);
      if (data != null) {
        final List<dynamic> decoded = jsonDecode(data);
        _items = decoded
            .map((d) => InventoryItem.fromJson(d as Map<String, dynamic>))
            .toList();
      } else {
        _items = List.of(inventorySeed);
        await _save();
      }
    } catch (e) {
      debugPrint('Error loading inventory: $e');
      _error = 'Failed to load inventory';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final data = _items.map((i) => i.toJson()).toList();
    await _storage.saveString(_storageKey, jsonEncode(data));
  }

  InventoryItem? getBySku(String sku) {
    for (final item in _items) {
      if (item.sku == sku) return item;
    }
    return null;
  }

  /// Matches name, brand, SKU, department, or aisle number.
  List<InventoryItem> search(String query, {String? department}) {
    final q = query.trim().toLowerCase();
    return _items.where((item) {
      if (department != null && item.department != department) return false;
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          item.brand.toLowerCase().contains(q) ||
          item.sku.contains(q) ||
          item.department.toLowerCase().contains(q) ||
          'aisle ${item.aisle}' == q ||
          item.aisle.toString() == q;
    }).toList();
  }

  static const Set<String> _stopWords = {
    'a', 'an', 'the', 'and', 'or', 'for', 'of', 'to', 'in', 'on', 'with',
    'my', 'me', 'i', 'you', 'your', 'do', 'does', 'have', 'has', 'need',
    'some', 'any', 'where', 'find', 'is', 'are', 'can', 'get', 'looking',
    'want', 'buy', 'carry', 'sell', 'it', 'that', 'this', 'what', 'which',
    'how', 'much', 'price', 'cost', 'stock', 'store', 'there', 'here',
    'please', 'could', 'would', 'like', 'aisle', 'shelf', 'bin', 'one',
  };

  /// Normalizes text into comparable words: lowercase, no stop words, and a
  /// trailing plural "s" removed so "screws" matches "screw".
  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 2 && !_stopWords.contains(w))
        .map((w) => w.length > 3 && w.endsWith('s') ? w.substring(0, w.length - 1) : w)
        .toList();
  }

  /// Ranked product lookup for natural requests ("screws for my deck").
  ///
  /// Unlike [search], words don't have to appear together or in order. Each
  /// word found in the name, brand, department, or description scores, with
  /// whole-word matches ranked above partial ones.
  List<InventoryItem> findProducts(String query, {String? department, int limit = 5}) {
    final trimmed = query.trim();
    final exactSku = getBySku(trimmed);
    if (exactSku != null) return [exactSku];

    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) return [];

    final scored = <(InventoryItem, int)>[];
    for (final item in _items) {
      if (department != null &&
          !item.department.toLowerCase().contains(department.toLowerCase())) {
        continue;
      }
      final words = _tokenize(
              '${item.name} ${item.brand} ${item.department} ${item.description}')
          .toSet();
      var score = 0;
      for (final token in tokens) {
        if (words.contains(token)) {
          score += 2;
        } else if (token.length >= 3 && words.any((w) => w.startsWith(token))) {
          score += 1;
        }
      }
      if (score > 0) scored.add((item, score));
    }

    if (scored.isEmpty) return [];
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // Drop incidental matches (one shared word like "deck" or "white") that
    // would otherwise sit under a strong match and get offered to a customer.
    final cutoff = scored.first.$2 / 2;
    return scored
        .where((e) => e.$2 > cutoff)
        .take(limit)
        .map((e) => e.$1)
        .toList();
  }

  /// Everything stocked in one aisle, ordered by shelf then bin.
  List<InventoryItem> itemsInAisle(int aisle) {
    final inAisle = _items.where((i) => i.aisle == aisle).toList();
    inAisle.sort((a, b) {
      final byShelf = a.shelf.compareTo(b.shelf);
      return byShelf != 0 ? byShelf : a.bin.compareTo(b.bin);
    });
    return inAisle;
  }

  /// Insert or replace by SKU. [originalSku] handles an edit that changed it.
  Future<void> saveItem(InventoryItem item, {String? originalSku}) async {
    final lookup = originalSku ?? item.sku;
    final index = _items.indexWhere((i) => i.sku == lookup);
    if (index >= 0) {
      _items[index] = item;
    } else {
      _items.insert(0, item);
    }
    await _save();
    notifyListeners();
  }

  Future<void> deleteItem(String sku) async {
    _items.removeWhere((i) => i.sku == sku);
    await _save();
    notifyListeners();
  }

  /// Demo "upload": replaces the catalog with the bundled seed data.
  Future<int> importDemoData() async {
    _items = List.of(inventorySeed);
    await _save();
    notifyListeners();
    return _items.length;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
