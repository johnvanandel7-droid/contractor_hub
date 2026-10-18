import 'dart:convert';
 
import 'package:cloud_functions/cloud_functions.dart';
import 'package:contractor_hub/components/app_bar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
 
/// Boss-only screen: connect QuickBooks Online, choose accounts, push
/// hours / expenses / mileage. All QuickBooks calls run in Cloud Functions;
/// no secret or token ever reaches the app.
class QuickbooksConnection extends StatefulWidget {
  const QuickbooksConnection({super.key});
 
  @override
  State<QuickbooksConnection> createState() => _QuickbooksConnectionState();
}
 
class _QuickbooksConnectionState extends State<QuickbooksConnection>
    with WidgetsBindingObserver {
  final _fn = FirebaseFunctions.instance;
 
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _status = {'connected': false};
 
  List<Map<String, dynamic>> _payment = [];
  List<Map<String, dynamic>> _expense = [];
 
  String? _paymentId;
  String? _expenseId;
  String? _mileageId;
  final _rate = TextEditingController(text: '0');
  final _tz = TextEditingController(text: 'America/New_York');
  DateTime _syncFrom = DateTime.now().subtract(const Duration(days: 30));
 
  final _types = {'hours': true, 'expenses': true, 'mileage': true};
  bool _busy = false;
  Map<String, dynamic>? _result;
 
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }
 
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rate.dispose();
    _tz.dispose();
    super.dispose();
  }
 
  // Coming back from the browser after approving access in QuickBooks.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }
 
  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    try {
      final res = await _fn.httpsCallable(name).call(data ?? {});
      // Callable results come back as Map<Object?, Object?>; normalize deeply.
      return Map<String, dynamic>.from(jsonDecode(jsonEncode(res.data)) as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }
 
  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _call('quickbooksStatus');
      Map<String, dynamic>? accounts;
      if (status['connected'] == true) {
        accounts = await _call('quickbooksAccounts');
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        if (accounts != null) {
          _payment = List<Map<String, dynamic>>.from(accounts['payment'] as List);
          _expense = List<Map<String, dynamic>>.from(accounts['expense'] as List);
          final s = Map<String, dynamic>.from(status['settings'] as Map? ?? {});
          // A dropdown asserts if its value isn't in its items, so only
          // restore ids that still exist in QuickBooks.
          _paymentId = _payment.any((a) => a['id'] == s['paymentAccountId'])
              ? s['paymentAccountId'] as String?
              : null;
          _expenseId = _expense.any((a) => a['id'] == s['expenseAccountId'])
              ? s['expenseAccountId'] as String?
              : null;
          _mileageId = _expense.any((a) => a['id'] == s['mileageAccountId'])
              ? s['mileageAccountId'] as String?
              : null;
          _rate.text = '${s['mileageRatePerKm'] ?? 0}';
          if (s['timeZone'] != null) _tz.text = s['timeZone'] as String;
          if (s['syncFrom'] != null) {
            _syncFrom = DateTime.fromMillisecondsSinceEpoch((s['syncFrom'] as num).toInt());
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }
 
  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
 
  Future<void> _connect() async {
    try {
      final r = await _call('quickbooksConnect');
      final ok = await launchUrl(
        Uri.parse(r['url'] as String),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _snack('Could not open the browser.');
    } catch (e) {
      _snack('Could not start connection: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }
 
  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Disconnect QuickBooks?'),
        content: const Text(
          'Nothing is deleted in QuickBooks. Items already synced stay there '
          'and won\'t be sent again if you reconnect to the same company.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _call('quickbooksDisconnect');
      _snack('Disconnected');
      await _refresh();
    } catch (e) {
      _snack('Could not disconnect: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }
 
  Future<bool> _saveSettings({bool quiet = false}) async {
    String? type;
    for (final a in _payment) {
      if (a['id'] == _paymentId) type = a['type'] as String?;
    }
    try {
      await _call('quickbooksSaveSettings', {
        'paymentAccountId': _paymentId,
        'paymentAccountType': type,
        'expenseAccountId': _expenseId,
        'mileageAccountId': _mileageId,
        'mileageRatePerKm': double.tryParse(_rate.text.trim()) ?? 0,
        'timeZone': _tz.text.trim(),
        'syncFrom': _syncFrom.millisecondsSinceEpoch,
      });
      if (!quiet) _snack('Settings saved');
      return true;
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }
 
  Future<void> _sync() async {
    final types = _types.entries.where((e) => e.value).map((e) => e.key).toList();
    if (types.isEmpty) {
      _snack('Pick at least one thing to sync');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      if (!await _saveSettings(quiet: true)) return;
      final r = await _call('quickbooksSync', {'types': types});
      if (!mounted) return;
      setState(() => _result = r);
      await _refresh();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
 
  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _syncFrom,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _syncFrom = d);
  }
 
  // ───────────────────────── UI ─────────────────────────
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWidget(title: 'QuickBooks'),
      backgroundColor: Colors.grey[100],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _status['connected'] == true
                        ? [_statusCard(), _settingsCard(), _syncCard()]
                        : [_connectCard()],
                  ),
                ),
    );
  }
 
  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _refresh, child: const Text('Try again')),
            ],
          ),
        ),
      );
 
  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
 
  Widget _connectCard() => _card('Connect to QuickBooks', [
        const Text(
          'Send employee hours, PO expenses and mileage to QuickBooks Online. '
          'You\'ll sign in to Intuit in your browser and approve access, then '
          'come back here.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _connect,
          icon: const Icon(Icons.link),
          label: const Text('Connect QuickBooks'),
        ),
      ]);
 
  Widget _statusCard() {
    final env = _status['env'] as String? ?? 'sandbox';
    final last = _status['lastSyncAt'] as num?;
    return _card('Connected', [
      Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              (_status['qbCompanyName'] as String?)?.isNotEmpty == true
                  ? _status['qbCompanyName'] as String
                  : 'QuickBooks company',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Chip(
            label: Text(env == 'production' ? 'Live' : 'Sandbox'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      if (last != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Last sync: ${DateTime.fromMillisecondsSinceEpoch(last.toInt()).toLocal()}'.split('.').first,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _disconnect,
        icon: const Icon(Icons.link_off, color: Colors.red),
        label: const Text('Disconnect', style: TextStyle(color: Colors.red)),
      ),
    ]);
  }
 
  Widget _accountDropdown(
    String label,
    List<Map<String, dynamic>> items,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final a in items)
            DropdownMenuItem(
              value: a['id'] as String,
              child: Text(a['name'] as String, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
 
  Widget _settingsCard() => _card('Settings', [
        _accountDropdown('Paid from (bank or credit card)', _payment, _paymentId,
            (v) => setState(() => _paymentId = v)),
        _accountDropdown('Expense account for PO logs', _expense, _expenseId,
            (v) => setState(() => _expenseId = v)),
        _accountDropdown('Expense account for mileage', _expense, _mileageId,
            (v) => setState(() => _mileageId = v)),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Mileage rate per km',
            helperText: 'Dollar amount per km. Use your tax authority\'s current rate.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tz,
          decoration: const InputDecoration(
            labelText: 'Time zone',
            helperText: 'Used to pick the date on each entry, e.g. America/New_York',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Only sync entries from'),
          subtitle: Text(_syncFrom.toString().split(' ').first),
          trailing: const Icon(Icons.calendar_today),
          onTap: _pickDate,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(onPressed: _saveSettings, child: const Text('Save settings')),
        ),
      ]);
 
  Widget _syncCard() => _card('Send to QuickBooks', [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Employee hours (time activities)'),
          value: _types['hours'],
          onChanged: (v) => setState(() => _types['hours'] = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('PO expenses'),
          value: _types['expenses'],
          onChanged: (v) => setState(() => _types['expenses'] = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mileage (excludes personal trips)'),
          value: _types['mileage'],
          onChanged: (v) => setState(() => _types['mileage'] = v ?? false),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _sync,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.sync),
          label: Text(_busy ? 'Syncing…' : 'Sync now'),
        ),
        const SizedBox(height: 4),
        Text(
          'Each entry is sent once. Editing or deleting it in the app afterwards '
          'does not change QuickBooks.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        if (_result != null) ..._resultView(_result!),
      ]);
 
  List<Widget> _resultView(Map<String, dynamic> r) {
    String line(String label, String key) {
      final m = Map<String, dynamic>.from(r[key] as Map);
      return '$label: ${m['synced']} sent${(m['failed'] as num) > 0 ? ', ${m['failed']} failed' : ''}';
    }
 
    final errors = List<String>.from(r['errors'] as List? ?? []);
    return [
      const Divider(height: 24),
      Text(line('Hours', 'hours')),
      Text(line('Expenses', 'expenses')),
      Text(line('Mileage', 'mileage')),
      if (r['truncated'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('More entries are waiting. Tap Sync now again.',
              style: TextStyle(color: Colors.orange)),
        ),
      if (errors.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Problems', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final e in errors)
          Text('• $e', style: const TextStyle(color: Colors.red, fontSize: 12)),
      ],
    ];
  }
}