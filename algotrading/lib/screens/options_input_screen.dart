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
  double _leverageMultiplier = 1.0;
  bool _isLoading = false;

  // Live ATM premium (fetched after expiry selected). null = not yet fetched.
  double? _livePremiumCE;
  double? _livePremiumPE;
  bool _premiumLoading = false;

  // Fallback estimates used only when live premium hasn't loaded yet
  static const _estPremium = {'NIFTY': 100.0, 'BANKNIFTY': 150.0};

  /// Max lots user can afford: floor(capital / (actual_or_est_premium × lot_size))
  int get _maxLots {
    final capital = double.tryParse(_capitalController.text.trim()) ?? 0;
    if (capital <= 0) return 10;
    final lotSize = _selectedIndex == 'NIFTY' ? 75 : 30;
    // Use real live premium if available, otherwise fallback estimate
    final livePremium = _livePremiumCE != null && _livePremiumPE != null
        ? (_livePremiumCE! + _livePremiumPE!) / 2  // average of CE+PE
        : (_estPremium[_selectedIndex] ?? 100.0);
    final max = (capital / (livePremium * lotSize)).floor();
    return max.clamp(1, 50);
  }

  /// Max leverage: risk% × leverage must not exceed 20% of capital
  /// i.e., leverage ≤ 20 / risk_percent  (capped at 5)
  double get _maxLeverage {
    final maxRiskPct = 20.0; // never risk more than 20% of capital in one trade
    return (maxRiskPct / _riskPercent).clamp(1.0, 5.0);
  }
  String? _error;
  bool _isMarketDataError = false;  // true when error is "not enough candles"

  double _availableBalance = 0;

  final _purple = const Color(0xFF7C3AED);
  final _indigo = const Color(0xFF4F46E5);

  @override
  void initState() {
    super.initState();
    _capitalController.addListener(_onCapitalChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final balance =
          context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
      setState(() => _availableBalance = balance);
      _capitalController.text = balance > 0 ? balance.floor().toString() : '50000';
      _fetchExpiries();
    });
  }

  /// Whenever capital changes, clamp lots and leverage so they stay affordable.
  void _onCapitalChanged() {
    final maxL = _maxLots;
    final maxLev = _maxLeverage;
    if (_lots > maxL || _leverageMultiplier > maxLev) {
      setState(() {
        if (_lots > maxL) _lots = maxL.clamp(1, 50);
        if (_leverageMultiplier > maxLev) {
          // round down to nearest 0.5 step
          _leverageMultiplier = (maxLev * 2).floor() / 2.0;
          if (_leverageMultiplier < 1.0) _leverageMultiplier = 1.0;
        }
      });
    } else {
      setState(() {}); // refresh UI to update max labels
    }
  }

  @override
  void dispose() {
    _capitalController.removeListener(_onCapitalChanged);
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
          _livePremiumCE = null;
          _livePremiumPE = null;
        });
        _fetchPremiumQuote();
      } else {
        setState(() => _expiriesError = 'Could not load expiries');
      }
    } catch (e) {
      if (mounted) setState(() => _expiriesError = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _expiriesLoading = false);
    }
  }

  // ── Fetch live ATM premiums ─────────────────────────────────────────────
  Future<void> _fetchPremiumQuote() async {
    if (!mounted || _selectedExpiry == null) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _premiumLoading = true; });

    try {
      final uri = Uri.parse(ApiConfig.optionsPremiumQuoteUrl).replace(
        queryParameters: {
          'index': _selectedIndex,
          'expiry_date': _selectedExpiry!,
          'api_key': auth.user!.apiKey,
          'access_token': auth.user!.accessToken,
        },
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final ce = (data['premium_ce'] as num?)?.toDouble();
        final pe = (data['premium_pe'] as num?)?.toDouble();
        setState(() {
          _livePremiumCE = ce;
          _livePremiumPE = pe;
          // Clamp lots/leverage now that we have real premiums
          _onCapitalChanged();
        });
      }
      // If it fails, keep using fallback estimates — no error shown to user
    } catch (_) {
      // Silently ignore — fallback estimates remain in use
    } finally {
      if (mounted) setState(() => _premiumLoading = false);
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

    setState(() { _isLoading = true; _error = null; _isMarketDataError = false; });

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
        'leverage_multiplier': _leverageMultiplier.clamp(1.0, _maxLeverage),
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
        bool isDataError = false;
        try {
          final body = jsonDecode(resp.body);
          msg = body['detail'] ?? msg;
          if (msg.toLowerCase().contains('candle') ||
              msg.toLowerCase().contains('historical data')) {
            isDataError = true;
          }
        } catch (_) {}
        setState(() {
          _error = msg;
          _isMarketDataError = isDataError;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isMarketDataError = false;
        });
      }
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
                  const SizedBox(height: 16),
                  _buildLeverageCard(),
                  const SizedBox(height: 16),
                  _buildRiskPreviewCard(),
                  const SizedBox(height: 24),
                  _buildAnalyzeButton(),
                  if (_error != null)
                    _isMarketDataError
                        ? _buildMarketDataErrorBox()
                        : _buildErrorBox(_error!),
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
                    _livePremiumCE = null;
                    _livePremiumPE = null;
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
                          onTap: () {
                            setState(() {
                              _selectedExpiry = exp;
                              _livePremiumCE = null;
                              _livePremiumPE = null;
                            });
                            _fetchPremiumQuote();
                          },
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
    final maxLots = _maxLots;
    final lotSize = _selectedIndex == 'NIFTY' ? 75 : 30;
    final hasLive = _livePremiumCE != null && _livePremiumPE != null;
    final avgPremium = hasLive
        ? (_livePremiumCE! + _livePremiumPE!) / 2
        : (_estPremium[_selectedIndex] ?? 100.0);
    final estCost = _lots * lotSize * avgPremium;

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
                '$_lots lot${_lots > 1 ? 's' : ''} · ${_lots * lotSize} units',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _purple,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_lots / $maxLots max',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          Slider(
            value: _lots.clamp(1, maxLots).toDouble(),
            min: 1,
            max: maxLots.toDouble(),
            divisions: (maxLots - 1).clamp(1, 49),
            activeColor: _purple,
            onChanged: (v) => setState(() => _lots = v.round()),
          ),
          if (_premiumLoading)
            Row(
              children: [
                SizedBox(
                  width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: _purple),
                ),
                const SizedBox(width: 6),
                Text('Fetching live ATM premiums…',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            )
          else if (hasLive)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CE ₹${_livePremiumCE!.toStringAsFixed(2)}  ·  '
                  'PE ₹${_livePremiumPE!.toStringAsFixed(2)}  '
                  '(live ATM premiums)',
                  style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Est. cost for $_lots lot${_lots > 1 ? 's' : ''}: '
                  '~₹${estCost.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            )
          else
            Text(
              'Est. cost: ~₹${estCost.toStringAsFixed(0)} '
              '(using ~₹${avgPremium.toStringAsFixed(0)} fallback premium)',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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

  Widget _buildLeverageCard() {
    final maxLev = _maxLeverage;
    final clampedLev = _leverageMultiplier.clamp(1.0, maxLev);
    final leverageLabel = clampedLev == 1.0
        ? '1× (No leverage)'
        : '${clampedLev.toStringAsFixed(1)}×';
    final capital = double.tryParse(_capitalController.text.trim()) ?? 0;
    final baseRisk = capital * _riskPercent / 100;
    final effectiveRisk = baseRisk * clampedLev;
    final effectiveRiskPct = capital > 0 ? (effectiveRisk / capital * 100) : 0.0;
    final color = clampedLev <= 1.0
        ? Colors.green[700]!
        : clampedLev <= 2.0
            ? Colors.orange[700]!
            : Colors.red[700]!;

    // Number of slider steps within allowed range
    final maxSteps = ((maxLev - 1.0) / 0.5).floor();

    return _card(
      icon: Icons.speed_outlined,
      title: 'Leverage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Multiplies risk budget · max ${maxLev.toStringAsFixed(1)}×',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  leverageLabel,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          Slider(
            value: clampedLev,
            min: 1.0,
            max: maxLev,
            divisions: maxSteps.clamp(1, 8),
            activeColor: color,
            onChanged: (v) => setState(
                () => _leverageMultiplier = double.parse(v.toStringAsFixed(1))),
          ),
          if (capital > 0)
            Text(
              'Base risk ₹${baseRisk.toStringAsFixed(0)}  →  '
              'Effective risk ₹${effectiveRisk.toStringAsFixed(0)} '
              '(${effectiveRiskPct.toStringAsFixed(1)}% of capital)',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          if (clampedLev > 2.0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '⚠ High leverage — loss can exceed ${effectiveRiskPct.toStringAsFixed(0)}% of capital.',
                style: TextStyle(fontSize: 11, color: Colors.red[700]),
              ),
            ),
          if (maxLev < 5.0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Max leverage limited to ${maxLev.toStringAsFixed(1)}× '
                'to keep total risk ≤ 20% of your capital.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRiskPreviewCard() {
    final capital = double.tryParse(_capitalController.text.trim()) ?? 0;
    final maxLoss = capital * _riskPercent / 100 * _leverageMultiplier;
    final lotSize = _selectedIndex == 'NIFTY' ? 75 : 30;
    final totalUnits = _lots * lotSize;
    final maxSlPerUnit = totalUnits > 0 ? maxLoss / totalUnits : 0.0;

    final isViable = maxSlPerUnit >= 10;
    final color = isViable ? Colors.green[700]! : Colors.red[700]!;
    final bgColor = isViable ? Colors.green[50]! : Colors.red[50]!;
    final borderColor = isViable ? Colors.green[200]! : Colors.red[200]!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isViable ? Icons.shield_outlined : Icons.warning_amber_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Risk Budget',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _riskStat('Max Loss', '₹${maxLoss.toStringAsFixed(0)}', color)),
              Expanded(child: _riskStat('Units', '$totalUnits', color)),
              Expanded(child: _riskStat('SL room/unit', '₹${maxSlPerUnit.toStringAsFixed(1)}', color)),
            ],
          ),
          if (!isViable) ...[
            const SizedBox(height: 8),
            Text(
              'SL room too tight (< ₹10/unit). Increase capital, raise risk %, or reduce lots.',
              style: TextStyle(fontSize: 11, color: Colors.red[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _riskStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ],
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

  Widget _buildMarketDataErrorBox() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_outlined, color: Colors.orange[800], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Market Data Unavailable',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Not enough 5-minute candle data from Zerodha. This usually happens when:',
              style: TextStyle(color: Colors.orange[900], fontSize: 13),
            ),
            const SizedBox(height: 6),
            ...const [
              '• Market is not yet open (before 9:15 AM IST)',
              '• It\'s a weekend or public holiday',
              '• Zerodha historical data API is temporarily slow',
            ].map((t) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(t,
                      style: TextStyle(
                          color: Colors.orange[900], fontSize: 12)),
                )),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _handleAnalyze,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Analysis'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange[800],
                  side: BorderSide(color: Colors.orange[400]!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
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
