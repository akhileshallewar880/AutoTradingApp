import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../utils/api_config.dart';
import '../models/options_model.dart';
import '../widgets/animated_loading_overlay.dart';
import 'options_results_screen.dart';

class OptionsInputScreen extends StatefulWidget {
  const OptionsInputScreen({super.key});

  @override
  State<OptionsInputScreen> createState() => _OptionsInputScreenState();
}

class _OptionsInputScreenState extends State<OptionsInputScreen> {
  final _capitalController = TextEditingController();

  String _selectedIndex = 'NIFTY';
  String? _selectedExpiry;
  List<String> _expiries = [];
  bool _expiriesLoading = false;
  String? _expiriesError;

  int _lots = 1;
  double _riskPercent = 1.0;
  bool _isLoading = false;
  String? _error;

  double _availableBalance = 0;

  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final balance =
          context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
      setState(() => _availableBalance = balance);
      _capitalController.text = balance > 0 ? balance.floor().toString() : '50000';
      _fetchExpiries();
    });
  }

  @override
  void dispose() {
    _capitalController.dispose();
    super.dispose();
  }

  // ── Fetch expiries ──────────────────────────────────────────────────────
  Future<void> _fetchExpiries() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _expiriesLoading = true; _expiriesError = null; _selectedExpiry = null; });

    try {
      final uri = Uri.parse(ApiConfig.optionsExpiriesUrl).replace(
        queryParameters: {
          'index': _selectedIndex,
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
          _selectedExpiry = list.isNotEmpty ? list.first : null;
        });
      } else {
        setState(() => _expiriesError = 'Could not load expiries');
      }
    } catch (e) {
      if (mounted) setState(() => _expiriesError = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _expiriesLoading = false);
    }
  }

  // ── Run analysis ────────────────────────────────────────────────────────
  Future<void> _handleAnalyze() async {
    if (_selectedExpiry == null) {
      setState(() => _error = 'Please select an expiry date');
      return;
    }
    final capitalText = _capitalController.text.trim();
    final capital = double.tryParse(capitalText);
    if (capital == null || capital <= 0) {
      setState(() => _error = 'Please enter a valid capital amount');
      return;
    }

    final auth = context.read<AuthProvider>();
    if (auth.user == null) {
      setState(() => _error = 'Not logged in');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      // user_id can be Zerodha string (e.g. "AB1234") or numeric VanTrade ID
      int? parsedUserId;
      try { parsedUserId = int.parse(auth.user!.userId); } catch (_) {
        parsedUserId = auth.user!.userId.hashCode.abs();
      }

      final body = jsonEncode({
        'index': _selectedIndex,
        'expiry_date': _selectedExpiry,
        'risk_percent': _riskPercent,
        'capital_to_use': capital,
        'lots': _lots,
        'access_token': auth.user!.accessToken,
        'api_key': auth.user!.apiKey,
        'user_id': parsedUserId,
      });

      final resp = await http
          .post(
            Uri.parse(ApiConfig.optionsAnalyzeUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 90));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final analysis = OptionsAnalysis.fromJson(data);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OptionsResultsScreen(analysis: analysis),
          ),
        );
      } else {
        String msg = 'Analysis failed';
        try {
          final body = jsonDecode(resp.body);
          msg = body['detail'] ?? msg;
        } catch (_) {}
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Options Trading'),
            backgroundColor: _purple,
            foregroundColor: Colors.white,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInfoBanner(),
                  const SizedBox(height: 16),
                  _buildIndexCard(),
                  const SizedBox(height: 16),
                  _buildExpiryCard(),
                  const SizedBox(height: 16),
                  _buildLotsCard(),
                  const SizedBox(height: 16),
                  _buildCapitalCard(),
                  const SizedBox(height: 24),
                  _buildAnalyzeButton(),
                  if (_error != null) _buildErrorBox(_error!),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading)
          AnimatedLoadingOverlay(
            message: 'AI analyzing $_selectedIndex options…',
          ),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_purple.withValues(alpha: 0.1), _indigo.withValues(alpha: 0.08)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: _purple, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Intraday options on NIFTY & BANKNIFTY. '
              'AI recommends ATM CE or PE with entry, SL, and target premiums. '
              'Auto square-off at 3:15 PM.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexCard() {
    return _card(
      icon: Icons.stacked_line_chart,
      title: 'Select Index',
      child: Row(
        children: ['NIFTY', 'BANKNIFTY'].map((idx) {
          final selected = _selectedIndex == idx;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = idx;
                    _selectedExpiry = null;
                    _expiries = [];
                  });
                  _fetchExpiries();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(colors: [_purple, _indigo])
                        : null,
                    color: selected ? null : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: selected
                        ? null
                        : Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        idx,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: selected ? Colors.white : Colors.grey[700],
                        ),
                      ),
                      Text(
                        idx == 'NIFTY' ? 'Lot: 75' : 'Lot: 30',
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? Colors.white70
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpiryCard() {
    return _card(
      icon: Icons.event,
      title: 'Expiry Date',
      child: _expiriesLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _expiriesError != null
              ? Text(
                  _expiriesError!,
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                )
              : _expiries.isEmpty
                  ? Text(
                      'No upcoming expiries found',
                      style: TextStyle(color: Colors.grey[600]),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _expiries.take(8).map((exp) {
                        final selected = _selectedExpiry == exp;
                        final label = _formatExpiry(exp);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedExpiry = exp),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? LinearGradient(colors: [_purple, _indigo])
                                  : null,
                              color: selected ? null : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: selected
                                  ? null
                                  : Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : Colors.grey[700],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
    );
  }

  Widget _buildLotsCard() {
    return _card(
      icon: Icons.layers_outlined,
      title: 'Number of Lots',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_lots lot${_lots > 1 ? 's' : ''} '
                '(${_lots * (_selectedIndex == 'NIFTY' ? 75 : 30)} units)',
                style:
                    TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_lots',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ],
          ),
          Slider(
            value: _lots.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: _purple,
            onChanged: (v) => setState(() => _lots = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildCapitalCard() {
    return _card(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Capital to Deploy',
      child: Column(
        children: [
          TextFormField(
            controller: _capitalController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: 'e.g. 50000',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _purple),
              ),
            ),
          ),
          if (_availableBalance > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Available balance: ₹${NumberFormat('#,##0.00').format(_availableBalance)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Risk %',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700])),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_riskPercent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Slider(
            value: _riskPercent,
            min: 0.5,
            max: 3.0,
            divisions: 5,
            activeColor: _purple,
            onChanged: (v) =>
                setState(() => _riskPercent = double.parse(v.toStringAsFixed(1))),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _handleAnalyze,
      icon: const Icon(Icons.auto_awesome),
      label: const Text(
        'Analyze with AI',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _purple.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
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
              child: Text(
                msg,
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _purple, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  String _formatExpiry(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      return DateFormat('dd MMM yy').format(d);
    } catch (_) {
      return isoDate;
    }
  }
}
