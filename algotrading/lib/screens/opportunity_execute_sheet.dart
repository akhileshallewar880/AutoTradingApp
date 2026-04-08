import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/options_model.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../services/api_service.dart';
import '../utils/api_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for one editable trade row
// ─────────────────────────────────────────────────────────────────────────────

class _TradeRow {
  bool selected;
  final String symbol;
  String action; // BUY | SELL
  final TextEditingController entry;
  final TextEditingController sl;
  final TextEditingController target;
  final TextEditingController qty;
  double confidenceScore;
  String aiReasoning;

  _TradeRow({
    required this.selected,
    required this.symbol,
    required this.action,
    required double entryVal,
    required double slVal,
    required double targetVal,
    required int qtyVal,
    required this.confidenceScore,
    required this.aiReasoning,
  })  : entry  = TextEditingController(text: entryVal.toStringAsFixed(2)),
        sl     = TextEditingController(text: slVal.toStringAsFixed(2)),
        target = TextEditingController(text: targetVal.toStringAsFixed(2)),
        qty    = TextEditingController(text: qtyVal.toString());

  void dispose() {
    entry.dispose();
    sl.dispose();
    target.dispose();
    qty.dispose();
  }

  double get entryVal  => double.tryParse(entry.text)  ?? 0;
  double get slVal     => double.tryParse(sl.text)     ?? 0;
  double get targetVal => double.tryParse(target.text) ?? 0;
  int    get qtyVal    => int.tryParse(qty.text)       ?? 1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet
// ─────────────────────────────────────────────────────────────────────────────

class OpportunityExecuteSheet extends StatefulWidget {
  final String mode; // 'STOCKS' | 'NIFTY' | 'BANKNIFTY'
  final List<Map<String, dynamic>> stocks;
  final Map<String, dynamic>? optionsTrade;
  final String expiryDate;   // pre-filled from scanner (options)
  final String analysisId;   // pre-filled from scanner (options)

  const OpportunityExecuteSheet({
    super.key,
    required this.mode,
    required this.stocks,
    this.optionsTrade,
    this.expiryDate  = '',
    this.analysisId  = '',
  });

  @override
  State<OpportunityExecuteSheet> createState() => _OpportunityExecuteSheetState();
}

class _OpportunityExecuteSheetState extends State<OpportunityExecuteSheet> {
  final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
  final _capitalCtrl = TextEditingController();

  bool get _isOptions => widget.mode == 'NIFTY' || widget.mode == 'BANKNIFTY';

  // ── Stocks parameters ───────────────────────────────────────────────────
  double _riskPercent = 1.0;
  int    _leverage    = 1;
  String _orderType   = 'LIMIT';

  // ── Options parameters ──────────────────────────────────────────────────
  List<String> _expiries       = [];
  String?      _selectedExpiry;
  bool         _expiriesLoading = false;
  int          _lots            = 1;
  double       _optRisk         = 1.0;
  double       _leverageMult    = 1.0;

  // After re-running analyze
  OptionsAnalysis? _freshAnalysis;
  bool             _analyzing    = false;
  String?          _analyzeError;

  // After confirm
  bool    _isConfirming  = false;
  String? _confirmError;
  String? _confirmSuccess;

  // Per-stock rows (STOCKS mode)
  late List<_TradeRow> _rows;

  bool _isExecuting = false;
  String? _execError;
  List<String> _execResults = [];

  @override
  void initState() {
    super.initState();
    _rows = widget.stocks.map((s) => _TradeRow(
      selected:        true,
      symbol:          s['stock_symbol'] as String? ?? '',
      action:          s['action']       as String? ?? 'BUY',
      entryVal:        (s['entry_price']  as num?)?.toDouble() ?? 0,
      slVal:           (s['stop_loss']    as num?)?.toDouble() ?? 0,
      targetVal:       (s['target_price'] as num?)?.toDouble() ?? 0,
      qtyVal:          (s['quantity']     as num?)?.toInt()    ?? 1,
      confidenceScore: (s['confidence_score'] as num?)?.toDouble() ?? 0,
      aiReasoning:     s['ai_reasoning'] as String? ?? '',
    )).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final balance = context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
      _capitalCtrl.text = balance > 0 ? balance.floor().toString() : '';
      if (_isOptions) _fetchExpiries();
    });
  }

  @override
  void dispose() {
    _capitalCtrl.dispose();
    for (final r in _rows) { r.dispose(); }
    super.dispose();
  }

  int get _selectedCount => _rows.where((r) => r.selected).length;

  // ── Execution ──────────────────────────────────────────────────────────────

  Future<void> _execute() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (user == null) return;

    final capital = double.tryParse(_capitalCtrl.text.trim()) ?? 0;
    if (capital <= 0) {
      setState(() => _execError = 'Enter a valid capital amount.');
      return;
    }

    final selected = _rows.where((r) => r.selected).toList();
    if (selected.isEmpty) {
      setState(() => _execError = 'Select at least one stock to execute.');
      return;
    }

    setState(() { _isExecuting = true; _execError = null; _execResults = []; });

    final results = <String>[];
    for (final row in selected) {
      try {
        final resp = await ApiService.placeLimitOrder(
          userId:      user.userId,
          accessToken: user.accessToken,
          apiKey:      user.apiKey,
          symbol:      row.symbol,
          action:      row.action,
          limitPrice:  row.entryVal,
          stopLoss:    row.slVal,
          target:      row.targetVal,
          capitalToUse: capital / selected.length,
          riskPercent:  _riskPercent,
          leverage:     _leverage,
          orderType:    _orderType,
        );
        final orderId = resp['order_id']?.toString() ?? '—';
        final qty     = resp['quantity']?.toString() ?? row.qty.text;
        results.add('✅ ${row.symbol} — Order $orderId (qty $qty)');
      } catch (e) {
        results.add('❌ ${row.symbol} — ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }

    setState(() { _isExecuting = false; _execResults = results; });
  }

  // ── Options: fetch expiries ────────────────────────────────────────────────

  Future<void> _fetchExpiries() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() { _expiriesLoading = true; });
    try {
      final uri = Uri.parse(ApiConfig.optionsExpiriesUrl).replace(
        queryParameters: {
          'index': widget.mode,
          'api_key': auth.user!.apiKey,
          'access_token': auth.user!.accessToken,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['expiries'] as List<dynamic>).cast<String>();
        setState(() {
          _expiries = list;
          // Pre-select the expiry the scanner used; fall back to first
          _selectedExpiry = list.contains(widget.expiryDate) && widget.expiryDate.isNotEmpty
              ? widget.expiryDate
              : list.isNotEmpty ? list.first : null;
        });
      }
    } catch (_) {
      // Silent — user can still pick expiry manually
    } finally {
      if (mounted) setState(() => _expiriesLoading = false);
    }
  }

  // ── Options: re-run analysis with current params ───────────────────────────

  Future<void> _runOptionsAnalysis() async {
    if (_selectedExpiry == null) {
      setState(() => _analyzeError = 'Select an expiry date first.');
      return;
    }
    final capital = double.tryParse(_capitalCtrl.text.trim()) ?? 0;
    if (capital <= 0) {
      setState(() => _analyzeError = 'Enter a valid capital amount.');
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _analyzing = true; _analyzeError = null; _freshAnalysis = null; _confirmError = null; _confirmSuccess = null; });

    try {
      int userId;
      try { userId = int.parse(auth.user!.userId); }
      catch (_) { userId = auth.user!.userId.hashCode.abs(); }

      final resp = await http.post(
        Uri.parse(ApiConfig.optionsAnalyzeUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'index': widget.mode,
          'expiry_date': _selectedExpiry,
          'risk_percent': _optRisk,
          'capital_to_use': capital,
          'lots': _lots,
          'leverage_multiplier': _leverageMult,
          'access_token': auth.user!.accessToken,
          'api_key': auth.user!.apiKey,
          'user_id': userId,
        }),
      ).timeout(const Duration(seconds: 90));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _freshAnalysis = OptionsAnalysis.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>));
      } else {
        String msg = 'Analysis failed';
        try { msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg; } catch (_) {}
        setState(() => _analyzeError = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _analyzeError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ── Options: confirm & execute ─────────────────────────────────────────────

  Future<void> _confirmOptions() async {
    final analysis = _freshAnalysis;
    if (analysis == null) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _isConfirming = true; _confirmError = null; _confirmSuccess = null; });

    try {
      final resp = await http.post(
        Uri.parse(ApiConfig.optionsConfirmUrl(analysis.analysisId)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'confirmed': true,
          'api_key': auth.user!.apiKey,
          'access_token': auth.user!.accessToken,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _confirmSuccess = 'Trade placed! Check the Options screen for live status.');
      } else {
        String msg = 'Execution failed';
        try { msg = (jsonDecode(resp.body) as Map)['detail'] ?? msg; } catch (_) {}
        setState(() => _confirmError = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _confirmError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.97,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.mode,
                      style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Trade Opportunity',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable body
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad + 16),
                children: [
                  if (_execResults.isNotEmpty) ...[
                    _buildResultsCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_execError != null) ...[
                    _buildErrorBanner(_execError!),
                    const SizedBox(height: 12),
                  ],
                  // ── Global parameters ───────────────────────────────────
                  _buildGlobalParamsCard(),
                  const SizedBox(height: 16),
                  // ── Per-stock cards ─────────────────────────────────────
                  if (widget.mode == 'STOCKS') ...[
                    Row(
                      children: [
                        Text(
                          '$_selectedCount of ${_rows.length} selected',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {
                            final allOn = _selectedCount == _rows.length;
                            for (final r in _rows) { r.selected = !allOn; }
                          }),
                          child: Text(
                            _selectedCount == _rows.length ? 'Deselect All' : 'Select All',
                            style: TextStyle(color: Colors.green[700], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._rows.asMap().entries.map((e) =>
                        _buildStockCard(e.key, e.value)),
                  ],
                  if (widget.mode != 'STOCKS') ...[
                    _buildOptionsParamsCard(),
                    const SizedBox(height: 16),
                    if (_freshAnalysis?.trade != null) ...[
                      _buildOptionsTradeCard(_freshAnalysis!.trade!),
                      const SizedBox(height: 16),
                    ],
                  ],
                  const SizedBox(height: 8),
                  // ── Action buttons (mode-aware) ─────────────────────────
                  if (widget.mode == 'STOCKS') ...[
                    // STOCKS: direct execute
                    if (_execResults.isEmpty)
                      _isExecuting
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _execute,
                                icon: const Icon(Icons.flash_on),
                                label: Text(
                                  'Execute ${_selectedCount > 0 ? _selectedCount : ''} Trade${_selectedCount != 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[700],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                    if (_execResults.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green[700],
                            side: BorderSide(color: Colors.green[700]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Done', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                  ] else ...[
                    // OPTIONS: analyze first, then confirm
                    if (_confirmSuccess == null) ...[
                      _analyzing
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: _runOptionsAnalysis,
                                icon: const Icon(Icons.search),
                                label: const Text('Get Live Quote & Analyze',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF7C3AED),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                      if (_analyzeError != null) ...[
                        const SizedBox(height: 8),
                        _buildErrorBanner(_analyzeError!),
                      ],
                      if (_freshAnalysis?.trade != null) ...[
                        const SizedBox(height: 10),
                        _isConfirming
                            ? const Center(child: CircularProgressIndicator())
                            : SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: _confirmOptions,
                                  icon: const Icon(Icons.flash_on),
                                  label: const Text('Confirm & Execute Trade',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[700],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                        if (_confirmError != null) ...[
                          const SizedBox(height: 8),
                          _buildErrorBanner(_confirmError!),
                        ],
                      ],
                    ],
                    if (_confirmSuccess != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[700]),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_confirmSuccess!,
                                  style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green[700],
                            side: BorderSide(color: Colors.green[700]!),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Done', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Global parameters card ─────────────────────────────────────────────────

  Widget _buildGlobalParamsCard() {
    final balance =
        context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.tune, 'Trade Parameters'),
            const SizedBox(height: 16),

            // ── Capital ─────────────────────────────────────────────────
            _label('Capital to Deploy'),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Available: ',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  balance > 0 ? _currency.format(balance) : '—',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _capitalCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco(prefixText: '₹ ', hint: 'Enter amount'),
            ),
            if (balance > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [25, 50, 75, 100].map((pct) {
                  final amt = (balance * pct / 100).floor();
                  return ActionChip(
                    label: Text('$pct%'),
                    backgroundColor: Colors.green[50],
                    side: BorderSide(color: Colors.green[300]!),
                    labelStyle: TextStyle(
                        color: Colors.green[800],
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                    onPressed: () =>
                        setState(() => _capitalCtrl.text = amt.toString()),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 16),

            // ── Risk % ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Risk per Trade'),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '${_riskPercent.toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            Slider(
              value: _riskPercent,
              min: 0.5,
              max: 5.0,
              divisions: 9,
              label: '${_riskPercent.toStringAsFixed(1)}%',
              activeColor: Colors.orange[700],
              inactiveColor: Colors.orange[100],
              onChanged: (v) => setState(() => _riskPercent = v),
            ),

            const SizedBox(height: 8),

            // ── Leverage ────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.bolt, color: Colors.purple[700], size: 16),
                const SizedBox(width: 6),
                _label('MIS Leverage'),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  child: Text(
                    '${_leverage}x',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[800],
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 4, 5].map((lev) {
                final sel = _leverage == lev;
                return ChoiceChip(
                  label: Text('${lev}x'),
                  selected: sel,
                  onSelected: (_) => setState(() => _leverage = lev),
                  selectedColor: Colors.purple[700],
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.grey[700],
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal),
                  side: BorderSide(
                      color: sel ? Colors.purple[700]! : Colors.grey[300]!),
                  backgroundColor: Colors.grey[50],
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── Order type ──────────────────────────────────────────────
            _label('Order Type'),
            const SizedBox(height: 8),
            Row(
              children: ['LIMIT', 'MARKET'].map((type) {
                final sel = _orderType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text(type),
                    selected: sel,
                    onSelected: (_) => setState(() => _orderType = type),
                    selectedColor: Colors.green[700],
                    labelStyle: TextStyle(
                        color: sel ? Colors.white : Colors.grey[700],
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal),
                    side: BorderSide(
                        color: sel ? Colors.green[700]! : Colors.grey[300]!),
                    backgroundColor: Colors.grey[50],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text(
              _orderType == 'LIMIT'
                  ? 'Order placed at your entry price — may not fill if price moves away.'
                  : 'Order placed immediately at best available price.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Per-stock editable card ────────────────────────────────────────────────

  Widget _buildStockCard(int idx, _TradeRow row) {
    final isBuy = row.action == 'BUY';
    final accentColor = isBuy ? Colors.green[700]! : Colors.red[700]!;

    // Confidence badge color
    final conf = row.confidenceScore;
    final confColor = conf >= 0.80
        ? Colors.green[700]!
        : conf >= 0.68
            ? Colors.orange[700]!
            : Colors.red[700]!;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: row.selected ? accentColor.withValues(alpha: 0.4) : Colors.grey[200]!,
          width: row.selected ? 1.5 : 1,
        ),
      ),
      child: Opacity(
        opacity: row.selected ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ───────────────────────────────────────────
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: row.selected,
                      onChanged: (v) => setState(() => row.selected = v ?? false),
                      activeColor: Colors.green[700],
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      isBuy ? 'BUY' : 'SHORT',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: accentColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.symbol,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: confColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${(conf * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: confColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Editable fields grid ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _priceField(
                      label: 'Entry Price',
                      ctrl: row.entry,
                      color: Colors.grey[700]!,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _priceField(
                      label: 'Stop Loss',
                      ctrl: row.sl,
                      color: Colors.red[700]!,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _priceField(
                      label: 'Target',
                      ctrl: row.target,
                      color: Colors.green[700]!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Quantity row ─────────────────────────────────────────
              Row(
                children: [
                  Text('Quantity',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                  _qtyButton(Icons.remove, () {
                    final v = (int.tryParse(row.qty.text) ?? 1) - 1;
                    if (v >= 1) setState(() => row.qty.text = v.toString());
                  }),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    height: 32,
                    child: TextField(
                      controller: row.qty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              BorderSide(color: Colors.green[700]!, width: 2),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _qtyButton(Icons.add, () {
                    final v = (int.tryParse(row.qty.text) ?? 1) + 1;
                    setState(() => row.qty.text = v.toString());
                  }),
                ],
              ),

              // ── AI reasoning (collapsed) ─────────────────────────────
              if (row.aiReasoning.isNotEmpty) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: Text('AI Reasoning',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  iconColor: Colors.grey[500],
                  collapsedIconColor: Colors.grey[400],
                  children: [
                    Text(row.aiReasoning,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Options parameters card (editable before analyze) ─────────────────────

  Widget _buildOptionsParamsCard() {
    final balance = context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.tune, '${widget.mode} Trade Parameters'),
            const SizedBox(height: 16),

            // Capital
            _label('Capital to Deploy'),
            const SizedBox(height: 4),
            Row(children: [
              Text('Available: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(balance > 0 ? _currency.format(balance) : '—',
                  style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              controller: _capitalCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco(prefixText: '₹ ', hint: 'Enter amount'),
              onChanged: (_) => setState(() {}),
            ),
            if (balance > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [25, 50, 75, 100].map((pct) {
                  final amt = (balance * pct / 100).floor();
                  return ActionChip(
                    label: Text('$pct%'),
                    backgroundColor: Colors.purple[50],
                    side: BorderSide(color: Colors.purple[200]!),
                    labelStyle: TextStyle(color: Colors.purple[800], fontWeight: FontWeight.w600, fontSize: 12),
                    onPressed: () => setState(() => _capitalCtrl.text = amt.toString()),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),

            // Expiry
            _label('Expiry Date'),
            const SizedBox(height: 8),
            _expiriesLoading
                ? const SizedBox(height: 36, child: Center(child: LinearProgressIndicator()))
                : _expiries.isEmpty
                    ? TextButton.icon(
                        onPressed: _fetchExpiries,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Load expiries'),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedExpiry,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: _expiries
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedExpiry = v;
                            _freshAnalysis = null;
                          }),
                        ),
                      ),
            const SizedBox(height: 16),

            // Lots
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _label('Lots'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple[200]!),
                ),
                child: Text('$_lots', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple[800])),
              ),
            ]),
            Slider(
              value: _lots.toDouble(),
              min: 1, max: 20, divisions: 19,
              label: '$_lots',
              activeColor: Colors.purple[700],
              inactiveColor: Colors.purple[100],
              onChanged: (v) => setState(() => _lots = v.toInt()),
            ),
            const SizedBox(height: 8),

            // Risk %
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _label('Risk per Trade'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Text('${_optRisk.toStringAsFixed(1)}%',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
              ),
            ]),
            Slider(
              value: _optRisk,
              min: 0.5, max: 5.0, divisions: 9,
              label: '${_optRisk.toStringAsFixed(1)}%',
              activeColor: Colors.orange[700],
              inactiveColor: Colors.orange[100],
              onChanged: (v) => setState(() => _optRisk = v),
            ),
            const SizedBox(height: 8),

            // Leverage multiplier
            _label('Leverage Multiplier'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [1.0, 1.5, 2.0, 2.5, 3.0].map((lev) {
                final sel = _leverageMult == lev;
                return ChoiceChip(
                  label: Text('${lev}x'),
                  selected: sel,
                  onSelected: (_) => setState(() => _leverageMult = lev),
                  selectedColor: Colors.purple[700],
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.grey[700],
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                  side: BorderSide(color: sel ? Colors.purple[700]! : Colors.grey[300]!),
                  backgroundColor: Colors.grey[50],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Options trade result card (typed OptionsTrade) ─────────────────────────

  Widget _buildOptionsTradeCard(OptionsTrade trade) {
    final f = _currency.format;
    final isCE = trade.optionType == 'CE';
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.purple[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _sectionHeader(Icons.candlestick_chart, 'Analyzed Trade'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCE ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCE ? Colors.green[300]! : Colors.red[300]!),
                ),
                child: Text(
                  isCE ? 'BUY CALL (CE)' : 'BUY PUT (PE)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCE ? Colors.green[700] : Colors.red[700]),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _detailRow('Symbol',        trade.optionSymbol),
            _detailRow('Strike',        '₹${trade.strikePrice.toStringAsFixed(0)}'),
            _detailRow('Expiry',        trade.expiryDate),
            _detailRow('Lots × Size',   '${trade.lots} × ${trade.lotSize} = ${trade.quantity} units'),
            _detailRow('Entry Premium', f(trade.entryPremium)),
            _detailRow('Stop Loss',     f(trade.stopLossPremium)),
            _detailRow('Target',        f(trade.targetPremium)),
            _detailRow('Max Loss',      f(trade.maxLoss)),
            _detailRow('Max Profit',    f(trade.maxProfit)),
            _detailRow('Hold',          '~${trade.suggestedHoldMinutes} min'),
            _detailRow('R:R',           '1:${trade.riskRewardRatio.toStringAsFixed(2)}'),
            _detailRow('Confidence',    '${(trade.confidenceScore * 100).toStringAsFixed(0)}%'),
            const Divider(height: 20),
            Text('AI Reasoning', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(trade.aiReasoning, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            if (trade.holdReasoning.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Text(
                  '⏱ ${trade.holdReasoning}\n\nAuto square-off at 3:15 PM. Cancel unfilled GTT orders after exit.',
                  style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Results card ───────────────────────────────────────────────────────────

  Widget _buildResultsCard() {
    return Card(
      elevation: 1,
      color: Colors.green[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.green[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Text('Execution Summary',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                        fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            ..._execResults.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(r,
                      style: TextStyle(
                          fontSize: 13,
                          color: r.startsWith('✅')
                              ? Colors.green[800]
                              : Colors.red[700])),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: TextStyle(color: Colors.red[700], fontSize: 13))),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.green[700], size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
      );

  Widget _priceField({
    required String label,
    required TextEditingController ctrl,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            prefixText: '₹',
            prefixStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: color, width: 2),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.green[700]),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({String? prefixText, String? hint}) {
    return InputDecoration(
      prefixText: prefixText,
      prefixStyle: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey[700]),
      hintText: hint,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.green[700]!, width: 2),
      ),
    );
  }
}
