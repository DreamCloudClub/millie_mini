import 'package:flutter/foundation.dart';

/// A product stocked in the store, with where to find it on the floor.
@immutable
class InventoryItem {
  final String sku;
  final String name;
  final String brand;
  final String department;
  final double price;
  final int quantity;
  final int aisle;
  final int shelf;
  final String bin;
  final String description;

  const InventoryItem({
    required this.sku,
    required this.name,
    required this.brand,
    required this.department,
    required this.price,
    required this.quantity,
    required this.aisle,
    required this.shelf,
    required this.bin,
    this.description = '',
  });

  /// Stock at or below this is flagged as low.
  static const int lowStockThreshold = 4;

  bool get isOutOfStock => quantity <= 0;
  bool get isLowStock => quantity > 0 && quantity <= lowStockThreshold;

  /// Location as a customer would hear it: "Aisle 12, Shelf 3, Bin B2".
  String get locationLabel => 'Aisle $aisle, Shelf $shelf, Bin $bin';

  // Pure numbers, fractions, and gauges ("2-1/2", "#8", "5,000") plus unit
  // words. Anything with letters mixed in ("20V", "2x6", "10-in-1") is part
  // of what the product is called and stays.
  static final RegExp _measurementWord = RegExp(
    r'^(#?\d[\d\-/.,]*|x|in\.|ft\.|yd\.|sq\.|cu\.|gal\.|lb\.|oz\.|amp|hp)$',
    caseSensitive: false,
  );

  /// The product as a person would say it, without catalog sizing:
  /// "#8 x 2-1/2 in. Exterior Deck Screws (1 lb.)" -> "Exterior Deck Screws".
  ///
  /// Falls back to the full name if stripping would leave nothing.
  String get spokenName {
    final words = name
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    while (words.isNotEmpty && _measurementWord.hasMatch(words.first)) {
      words.removeAt(0);
    }
    while (words.isNotEmpty && _measurementWord.hasMatch(words.last)) {
      words.removeLast();
    }

    final spoken = words.join(' ').replaceAll(RegExp(r'[,\s]+$'), '');
    return spoken.isEmpty ? name : spoken;
  }

  InventoryItem copyWith({
    String? sku,
    String? name,
    String? brand,
    String? department,
    double? price,
    int? quantity,
    int? aisle,
    int? shelf,
    String? bin,
    String? description,
  }) {
    return InventoryItem(
      sku: sku ?? this.sku,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      department: department ?? this.department,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      aisle: aisle ?? this.aisle,
      shelf: shelf ?? this.shelf,
      bin: bin ?? this.bin,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sku': sku,
      'name': name,
      'brand': brand,
      'department': department,
      'price': price,
      'quantity': quantity,
      'aisle': aisle,
      'shelf': shelf,
      'bin': bin,
      'description': description,
    };
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      sku: json['sku'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String? ?? '',
      department: json['department'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      quantity: json['quantity'] as int? ?? 0,
      aisle: json['aisle'] as int? ?? 0,
      shelf: json['shelf'] as int? ?? 0,
      bin: json['bin'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}
