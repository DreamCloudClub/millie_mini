import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/constants.dart';

class InventoryPage extends StatefulWidget {
  final VoidCallback onBack;

  const InventoryPage({super.key, required this.onBack});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _department;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openEditor({InventoryItem? item}) async {
    final provider = context.read<InventoryProvider>();
    await showDialog<void>(
      context: context,
      builder: (_) => _InventoryItemDialog(
        item: item,
        departments: provider.departments,
        onSave: (updated) => provider.saveItem(updated, originalSku: item?.sku),
        onDelete: item == null ? null : () => provider.deleteItem(item.sku),
      ),
    );
  }

  Future<void> _uploadData() async {
    final provider = context.read<InventoryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final count = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UploadDialog(onImport: provider.importDemoData),
    );
    if (count != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Imported $count products')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text('Inventory', style: AppTextStyles.heading2),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: kToolbarHeight + (AppSpacing.md * 2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        actions: [
          _PillButton(
            icon: Icons.upload_file,
            label: 'Upload Data',
            onPressed: _uploadData,
          ),
          const SizedBox(width: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _PillButton(
              icon: Icons.add,
              label: 'Add Product',
              onPressed: () => _openEditor(),
            ),
          ),
        ],
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          final results =
              provider.search(_searchController.text, department: _department);

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search name, brand, SKU, or aisle',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(
                                      () => _searchController.clear()),
                                ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppBorderRadius.small),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    DropdownButton<String?>(
                      value: _department,
                      hint: const Text('All departments'),
                      underline: const SizedBox(),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All departments'),
                        ),
                        ...provider.departments.map(
                          (d) => DropdownMenuItem<String?>(
                            value: d,
                            child: Text(d),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _department = value),
                    ),
                  ],
                ),
              ),
              _SummaryBar(
                shown: results.length,
                total: provider.items.length,
                lowStock: provider.lowStockCount,
                outOfStock: provider.outOfStockCount,
              ),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          provider.items.isEmpty
                              ? 'No products yet. Upload data or add a product.'
                              : 'No products match your search.',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textLight),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return _InventoryRow(
                            item: item,
                            onEdit: () => _openEditor(item: item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: AppColors.dreamCloudBlue),
      label: Text(
        label,
        style: const TextStyle(
          color: AppColors.dreamCloudBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.dreamCloudBlue,
        side: const BorderSide(color: AppColors.dreamCloudBlue, width: 1.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final int shown;
  final int total;
  final int lowStock;
  final int outOfStock;

  const _SummaryBar({
    required this.shown,
    required this.total,
    required this.lowStock,
    required this.outOfStock,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Row(
        children: [
          Text(
            shown == total ? '$total products' : '$shown of $total products',
            style: AppTextStyles.heading3,
          ),
          const Spacer(),
          if (lowStock > 0)
            _StockBadge(label: '$lowStock low stock', color: AppColors.primaryOrange),
          if (outOfStock > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _StockBadge(label: '$outOfStock out of stock', color: AppColors.error),
          ],
        ],
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StockBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onEdit;

  const _InventoryRow({required this.item, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final Color stockColor = item.isOutOfStock
        ? AppColors.error
        : item.isLowStock
            ? AppColors.primaryOrange
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Location block - the thing a customer is asking for
              Container(
                width: 92,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.dreamCloudBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppBorderRadius.small),
                ),
                child: Column(
                  children: [
                    Text(
                      'AISLE',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '${item.aisle}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dreamCloudBlue,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Shelf ${item.shelf} · ${item.bin}',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.brand} · SKU ${item.sku}',
                      style: AppTextStyles.bodySmall,
                    ),
                    Text(
                      item.department,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${item.price.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isOutOfStock ? 'Out of stock' : '${item.quantity} in stock',
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right, color: AppColors.textLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryItemDialog extends StatefulWidget {
  final InventoryItem? item;
  final List<String> departments;
  final Future<void> Function(InventoryItem item) onSave;
  final Future<void> Function()? onDelete;

  const _InventoryItemDialog({
    required this.item,
    required this.departments,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_InventoryItemDialog> createState() => _InventoryItemDialogState();
}

class _InventoryItemDialogState extends State<_InventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _brand;
  late final TextEditingController _sku;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _aisle;
  late final TextEditingController _shelf;
  late final TextEditingController _bin;
  late final TextEditingController _description;
  String? _department;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item?.name ?? '');
    _brand = TextEditingController(text: item?.brand ?? '');
    _sku = TextEditingController(text: item?.sku ?? '');
    _price = TextEditingController(text: item?.price.toStringAsFixed(2) ?? '');
    _quantity = TextEditingController(text: item?.quantity.toString() ?? '');
    _aisle = TextEditingController(text: item?.aisle.toString() ?? '');
    _shelf = TextEditingController(text: item?.shelf.toString() ?? '');
    _bin = TextEditingController(text: item?.bin ?? '');
    _description = TextEditingController(text: item?.description ?? '');
    _department = item?.department ??
        (widget.departments.isNotEmpty ? widget.departments.first : null);
  }

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _sku, _price, _quantity, _aisle, _shelf, _bin, _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  String? _wholeNumber(String? value) {
    if (_required(value) != null) return 'Required';
    return int.tryParse(value!.trim()) == null ? 'Whole number' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    await widget.onSave(InventoryItem(
      sku: _sku.text.trim(),
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      department: _department ?? '',
      price: double.parse(_price.text.trim()),
      quantity: int.parse(_quantity.text.trim()),
      aisle: int.parse(_aisle.text.trim()),
      shelf: int.parse(_shelf.text.trim()),
      bin: _bin.text.trim().toUpperCase(),
      description: _description.text.trim(),
    ));
    navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${widget.item!.name}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onDelete!();
    navigator.pop();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.small),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
    const gap = SizedBox(height: AppSpacing.md);
    const hGap = SizedBox(width: AppSpacing.md);

    // Keep the current department selectable even if it was typed in elsewhere.
    final departments = {
      ...widget.departments,
      if (_department != null) _department!,
    }.toList()
      ..sort();

    return AlertDialog(
      title: Text(widget.item == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Store Location', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _field('Aisle', _aisle,
                          validator: _wholeNumber,
                          keyboardType: TextInputType.number,
                          inputFormatters: digitsOnly),
                    ),
                    hGap,
                    Expanded(
                      child: _field('Shelf', _shelf,
                          validator: _wholeNumber,
                          keyboardType: TextInputType.number,
                          inputFormatters: digitsOnly),
                    ),
                    hGap,
                    Expanded(child: _field('Bin', _bin, validator: _required)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Product', style: AppTextStyles.label),
                const SizedBox(height: AppSpacing.sm),
                _field('Name', _name, validator: _required),
                gap,
                Row(
                  children: [
                    Expanded(child: _field('Brand', _brand, validator: _required)),
                    hGap,
                    Expanded(
                      child: _field('SKU', _sku,
                          validator: _required,
                          keyboardType: TextInputType.number,
                          inputFormatters: digitsOnly),
                    ),
                  ],
                ),
                gap,
                DropdownButtonFormField<String>(
                  initialValue: _department,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Department',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.small),
                    ),
                  ),
                  items: departments
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (value) => setState(() => _department = value),
                  validator: (value) => value == null ? 'Required' : null,
                ),
                gap,
                Row(
                  children: [
                    Expanded(
                      child: _field('Price', _price,
                          validator: (v) => _required(v) ??
                              (double.tryParse(v!.trim()) == null
                                  ? 'Enter a price'
                                  : null),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true)),
                    ),
                    hGap,
                    Expanded(
                      child: _field('Quantity', _quantity,
                          validator: _wholeNumber,
                          keyboardType: TextInputType.number,
                          inputFormatters: digitsOnly),
                    ),
                  ],
                ),
                gap,
                _field('Description', _description, maxLines: 2),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.dreamCloudBlue),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Demo-only upload flow: pick a (pretend) file, show progress, then load the
/// bundled catalog. Nothing is read from disk.
class _UploadDialog extends StatefulWidget {
  final Future<int> Function() onImport;

  const _UploadDialog({required this.onImport});

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

enum _UploadStage { choose, uploading, done }

class _UploadDialogState extends State<_UploadDialog> {
  static const _fileName = 'store_inventory_export.csv';

  _UploadStage _stage = _UploadStage.choose;
  double _progress = 0;
  int _count = 0;

  Future<void> _start() async {
    setState(() => _stage = _UploadStage.uploading);
    for (var step = 1; step <= 20; step++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() => _progress = step / 20);
    }
    final count = await widget.onImport();
    if (!mounted) return;
    setState(() {
      _count = count;
      _stage = _UploadStage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Inventory Data'),
      content: SizedBox(
        width: 420,
        child: switch (_stage) {
          _UploadStage.choose => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.dreamCloudBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppBorderRadius.medium),
                    border: Border.all(
                      color: AppColors.dreamCloudBlue.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 40, color: AppColors.dreamCloudBlue),
                      SizedBox(height: AppSpacing.sm),
                      Text(_fileName, style: AppTextStyles.bodyLarge),
                      Text('CSV · 100 rows · 18 KB', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'This replaces the current inventory, including any edits.',
                  style: AppTextStyles.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          _UploadStage.uploading => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _progress < 0.6 ? 'Uploading $_fileName...' : 'Processing records...',
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                LinearProgressIndicator(
                  value: _progress,
                  color: AppColors.dreamCloudBlue,
                  backgroundColor: AppColors.divider,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          _UploadStage.done => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 48),
                const SizedBox(height: AppSpacing.sm),
                Text('$_count products imported', style: AppTextStyles.heading3),
              ],
            ),
        },
      ),
      actions: switch (_stage) {
        _UploadStage.choose => [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dreamCloudBlue),
              child: const Text('Upload'),
            ),
          ],
        _UploadStage.uploading => const <Widget>[],
        _UploadStage.done => [
            FilledButton(
              onPressed: () => Navigator.pop(context, _count),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dreamCloudBlue),
              child: const Text('Done'),
            ),
          ],
      },
    );
  }
}
