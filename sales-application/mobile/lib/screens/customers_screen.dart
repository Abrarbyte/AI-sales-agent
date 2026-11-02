import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/offline_banner.dart';
import '../theme.dart';
import '../widgets/chips.dart';
import '../widgets/motion.dart';
import 'customer_detail_screen.dart';

/// Everyone who has bought, and whether what they bought has reached them.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  List<dynamic> _customers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final q = _search.text.trim();
    final path =
        '/api/crm/customers/?active=true${q.isEmpty ? '' : '&search=$q'}';
    // This search's last saved list straight away, then the server (#90).
    final saved = await Api.instance.cached(path);
    if (!mounted) return;
    setState(() {
      if (saved is List) _customers = saved;
      _loading = _customers.isEmpty;
      _error = null;
    });
    try {
      final data = await Api.instance.get(path);
      setState(() => _customers = data as List<dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(customerId: c['id'] as int)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: Column(
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search name, company or phone',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          _load();
                        }),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorView(scheme)
                    : _customers.isEmpty
                        ? _empty(scheme)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 4, 20, 32),
                              itemCount: _customers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => Reveal(
                                index: i < 6 ? i : 0,
                                child: _card(scheme,
                                    (_customers[i] as Map)
                                        .cast<String, dynamic>()),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _card(ColorScheme scheme, Map<String, dynamic> c) {
    final company = c['company_name']?.toString() ?? '';
    final products =
        (c['product_names'] as List<dynamic>? ?? const []).join(', ');
    final (dLabel, dColor) = Statuses.delivery(c['delivery_status']?.toString());
    final (sLabel, sColor) = Statuses.support(c['support_status']?.toString());
    final support = c['support_status']?.toString() ?? 'none';

    return SurfaceCard(
      onTap: () => _open(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(company.isEmpty ? c['name'].toString() : company,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface)),
              ),
              Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
          if (company.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(c['name'].toString(),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(products,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurface)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(label: dLabel, color: dColor),
              if (support != 'none') StatusPill(label: sLabel, color: sColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined,
              size: 32, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('No customers yet',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text('Convert a lead and they will appear here.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _errorView(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMd.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
