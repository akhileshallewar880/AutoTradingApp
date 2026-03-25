import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../providers/dashboard_provider.dart';
import '../utils/api_config.dart';
import '../widgets/animated_loading_overlay.dart';
import 'analysis_results_screen.dart';

class AnalysisInputScreen extends StatefulWidget {
  const AnalysisInputScreen({super.key});

  @override
  State<AnalysisInputScreen> createState() => _AnalysisInputScreenState();
}

class _AnalysisInputScreenState extends State<AnalysisInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _capitalController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  int _numStocks = 5;
  int _holdDurationDays = 0; // 0 = Intraday
  int _leverage = 1; // 1–5x MIS leverage (intraday only)
  Set<String> _selectedSectors = {'ALL'};
  double _availableBalance = 0;

  // ── Live NSE sector data ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _liveSectors = [];
  bool _sectorsLoading = false;
  String? _sectorsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final balance =
          context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
      setState(() => _availableBalance = balance);
      // Use floor() so we never suggest more capital than actually available
      _capitalController.text = balance > 0 ? balance.floor().toString() : '';
      _fetchSectors();
    });
  }

  @override
  void dispose() {
    _capitalController.dispose();
    super.dispose();
  }

  Future<void> _fetchSectors() async {
    if (!mounted) return;
    setState(() { _sectorsLoading = true; _sectorsError = null; });
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.sectorsUrl))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (data['sectors'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        setState(() => _liveSectors = list);
      } else {
        setState(() => _sectorsError = 'Could not load sectors');
      }
    } catch (_) {
      if (mounted) setState(() => _sectorsError = 'Offline — using defaults');
    } finally {
      if (mounted) setState(() => _sectorsLoading = false);
    }
  }

  static const _holdOptions = [
    (label: 'Intraday', days: 0),
    (label: '1 Day', days: 1),
    (label: '3 Days', days: 3),
    (label: '1 Week', days: 7),
    (label: '2 Weeks', days: 14),
    (label: '1 Month', days: 30),
  ];

  @override
  Widget build(BuildContext context) {
    final analysisProvider = context.watch<AnalysisProvider>();

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Generate Analysis'),
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Parameters Card ──────────────────────────────────
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader(
                                Icons.tune, 'Analysis Parameters'),
                            const SizedBox(height: 20),
                            _buildDatePicker(),
                            const SizedBox(height: 20),
                            _buildNumStocksSlider(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Sector Heatmap Card ──────────────────────────────
                    _buildSectorCard(),
                    const SizedBox(height: 16),

                    // ── Hold Duration Card ───────────────────────────────
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader(
                                Icons.timer_outlined, 'Hold Duration'),
                            const SizedBox(height: 4),
                            Text(
                              'Auto-sell all positions after this period regardless of P&L',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 14),
                            _buildHoldDurationPicker(),
                            // Leverage picker — only for intraday MIS trades
                            if (_holdDurationDays == 0) ...[
                              const SizedBox(height: 20),
                              _buildLeveragePicker(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Capital Card ─────────────────────────────────────
                    _buildCapitalCard(),
                    const SizedBox(height: 24),

                    // ── Generate Button ──────────────────────────────────
                    ElevatedButton.icon(
                      onPressed:
                          analysisProvider.isLoading ? null : _handleGenerate,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text(
                        'Generate AI Analysis',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green[200],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    if (analysisProvider.error != null)
                      Padding(
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
                              Icon(Icons.error_outline,
                                  color: Colors.red[700], size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  analysisProvider.error!,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Animated Loading Overlay ─────────────────────────────────────
        if (analysisProvider.isLoading)
          const AnimatedLoadingOverlay(message: 'Analyzing markets…'),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: Colors.green[700], size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Analysis Date',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEE, dd MMM yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 15),
                ),
                Icon(Icons.calendar_today, color: Colors.green[700], size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNumStocksSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Number of Stocks',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[700],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_numStocks',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        Slider(
          value: _numStocks.toDouble(),
          min: 1,
          max: 20,
          divisions: 19,
          label: _numStocks.toString(),
          activeColor: Colors.green[700],
          inactiveColor: Colors.green[100],
          onChanged: (value) {
            setState(() => _numStocks = value.toInt());
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text('20',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }


  // ── NSE Sector Heatmap Card ───────────────────────────────────────────────

  Widget _buildSectorCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with refresh button
            Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                const Text('NSE Sector Heatmap',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_sectorsLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  GestureDetector(
                    onTap: _fetchSectors,
                    child: Icon(Icons.refresh, size: 18, color: Colors.grey[500]),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _sectorsError != null
                  ? _sectorsError!
                  : 'Tap a sector to filter stocks. Most active sectors shown first.',
              style: TextStyle(
                  fontSize: 12,
                  color: _sectorsError != null
                      ? Colors.orange[700]
                      : Colors.grey[600]),
            ),
            const SizedBox(height: 14),

            // "All NSE" chip always first
            _buildAllChip(),
            const SizedBox(height: 10),

            // Live sector tiles (or skeleton if loading with empty cache)
            if (_sectorsLoading && _liveSectors.isEmpty)
              _buildSectorSkeleton()
            else if (_liveSectors.isEmpty)
              _buildStaticSectorChips()
            else
              _buildLiveSectorGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildAllChip() {
    final selected = _selectedSectors.contains('ALL');
    return FilterChip(
      label: const Text('All NSE'),
      avatar: Icon(Icons.public, size: 14,
          color: selected ? Colors.green[800] : Colors.grey[600]),
      selected: selected,
      onSelected: (_) => setState(() => _selectedSectors = {'ALL'}),
      selectedColor: Colors.green[100],
      checkmarkColor: Colors.green[700],
      labelStyle: TextStyle(
        color: selected ? Colors.green[800] : Colors.grey[700],
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
          color: selected ? Colors.green[400]! : Colors.grey[300]!),
      backgroundColor: Colors.grey[50],
    );
  }

  Widget _buildLiveSectorGrid() {
    return Column(
      children: _liveSectors.map((s) {
        final sectorKey   = s['sector'] as String;
        final displayName = s['display_name'] as String? ?? sectorKey;
        final changePct   = (s['change_pct'] as num?)?.toDouble() ?? 0.0;
        final last        = (s['last'] as num?)?.toDouble() ?? 0.0;
        final selected    = _selectedSectors.contains(sectorKey);

        // Gradient color based on magnitude, not just direction
        final changeColor = _sectorColor(changePct);
        final bgColor     = selected
            ? changeColor.withAlpha(18)
            : changeColor.withAlpha(8);
        final borderColor = selected
            ? changeColor.withAlpha(160)
            : changeColor.withAlpha(40);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (selected) {
                _selectedSectors.remove(sectorKey);
                if (_selectedSectors.isEmpty) _selectedSectors = {'ALL'};
              } else {
                _selectedSectors.remove('ALL');
                _selectedSectors.add(sectorKey);
              }
            });
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: Row(
              children: [
                // Momentum dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: changeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),

                // Sector name
                Expanded(
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: Colors.grey[900],
                    ),
                  ),
                ),

                // Index level (e.g. "34,521")
                if (last > 0) ...[
                  Text(
                    last >= 1000
                        ? last.toStringAsFixed(0)
                        : last.toStringAsFixed(1),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 10),
                ],

                // Change % badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: changeColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: changeColor,
                    ),
                  ),
                ),

                // Selected checkmark
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Returns a gradient color based on % change magnitude.
  /// Dark green = strongly up, light green = mildly up,
  /// grey = flat, light red = mildly down, dark red = strongly down.
  Color _sectorColor(double pct) {
    if (pct >= 2.0)  return const Color(0xFF1B5E20); // deep green
    if (pct >= 1.0)  return const Color(0xFF2E7D32); // dark green
    if (pct >= 0.5)  return const Color(0xFF388E3C); // medium green
    if (pct >= 0.2)  return const Color(0xFF66BB6A); // light green
    if (pct > -0.2)  return const Color(0xFF757575); // neutral grey
    if (pct > -0.5)  return const Color(0xFFEF9A9A); // light red
    if (pct > -1.0)  return const Color(0xFFE53935); // medium red
    if (pct > -2.0)  return const Color(0xFFC62828); // dark red
    return            const Color(0xFF7F0000);        // deep red
  }

  Widget _buildSectorSkeleton() {
    return Column(
      children: List.generate(
        5,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 42,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticSectorChips() {
    // Fallback when live data unavailable — static name-only chips
    const fallback = [
      'NIFTY IT', 'NIFTY BANK', 'NIFTY AUTO', 'NIFTY PHARMA',
      'NIFTY FMCG', 'NIFTY METAL', 'NIFTY ENERGY', 'NIFTY REALTY',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: fallback.map((s) {
        final selected = _selectedSectors.contains(s);
        return FilterChip(
          label: Text(s.replaceFirst('NIFTY ', '')),
          selected: selected,
          onSelected: (val) {
            setState(() {
              if (val) {
                _selectedSectors.remove('ALL');
                _selectedSectors.add(s);
              } else {
                _selectedSectors.remove(s);
                if (_selectedSectors.isEmpty) _selectedSectors = {'ALL'};
              }
            });
          },
          selectedColor: Colors.green[100],
          checkmarkColor: Colors.green[700],
          labelStyle: TextStyle(
            color: selected ? Colors.green[800] : Colors.grey[700],
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
              color: selected ? Colors.green[400]! : Colors.grey[300]!),
          backgroundColor: Colors.grey[50],
        );
      }).toList(),
    );
  }

  Widget _buildHoldDurationPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _holdOptions.map((opt) {
        final selected = _holdDurationDays == opt.days;
        return ChoiceChip(
          label: Text(opt.label),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _holdDurationDays = opt.days;
              // Reset leverage to 1x when switching to swing (non-intraday)
              if (opt.days != 0) _leverage = 1;
            });
          },
          selectedColor: Colors.green[700],
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.grey[700],
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
          side: BorderSide(
            color: selected ? Colors.green[700]! : Colors.grey[300]!,
          ),
          backgroundColor: Colors.grey[50],
        );
      }).toList(),
    );
  }

  Widget _buildLeveragePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, color: Colors.orange[700], size: 16),
            const SizedBox(width: 6),
            const Text(
              'MIS Leverage',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Text(
                '${_leverage}x',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Multiplies effective capital for intraday MIS orders. Higher leverage = higher risk.',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [1, 2, 3, 4, 5].map((lev) {
            final selected = _leverage == lev;
            return ChoiceChip(
              label: Text('${lev}x'),
              selected: selected,
              onSelected: (_) => setState(() => _leverage = lev),
              selectedColor: Colors.orange[700],
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.grey[700],
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: selected ? Colors.orange[700]! : Colors.grey[300]!,
              ),
              backgroundColor: Colors.grey[50],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCapitalCard() {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final pcts = [25, 50, 75, 100];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.account_balance_wallet, 'Capital to Deploy'),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Available: ',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  _availableBalance > 0
                      ? currency.format(_availableBalance)
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Amount text field
            TextFormField(
              controller: _capitalController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700]),
                hintText: 'Enter amount',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.green[700]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter a capital amount';
                }
                final amount = double.tryParse(val.trim());
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount greater than 0';
                }
                if (_availableBalance > 0 && amount > _availableBalance) {
                  return 'Cannot exceed available balance '
                      '(${currency.format(_availableBalance)})';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Quick-percentage chips
            if (_availableBalance > 0)
              Wrap(
                spacing: 8,
                children: pcts.map((pct) {
                  final amount = (_availableBalance * pct / 100)
                      .roundToDouble();
                  return ActionChip(
                    label: Text('$pct%'),
                    backgroundColor: Colors.green[50],
                    side: BorderSide(color: Colors.green[300]!),
                    labelStyle: TextStyle(
                      color: Colors.green[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onPressed: () => setState(() {
                      _capitalController.text = amount.floor().toString();
                    }),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green[700]!,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _handleGenerate() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final analysisProvider = context.read<AnalysisProvider>();
      final capitalToUse =
          double.tryParse(_capitalController.text.trim()) ?? _availableBalance;

      // Persist hold duration and sectors to provider
      analysisProvider.setHoldDuration(_holdDurationDays);
      analysisProvider.setSelectedSectors(_selectedSectors.toList());

      try {
        // Parse userId safely - handle both numeric (VanTrade ID) and string (Zerodha ID) formats
        int userId;
        try {
          userId = int.parse(authProvider.user!.userId);
        } catch (e) {
          // If userId is not numeric (e.g., "RI2021"), use fallback hash
          // This means backend hasn't been updated yet to return numeric user_id
          userId = authProvider.user!.userId.hashCode.abs();
        }

        await analysisProvider.generateAnalysis(
          analysisDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
          numStocks: _numStocks,
          riskPercent: 1.0,
          accessToken: authProvider.user!.accessToken,
          apiKey: authProvider.user!.apiKey,
          userId: userId,
          sectors: _selectedSectors.toList(),
          capitalToUse: capitalToUse,
          leverage: _holdDurationDays == 0 ? _leverage : 1,
        );

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AnalysisResultsScreen(),
            ),
          );
        }
      } catch (e) {
        // Error is already stored in analysisProvider.error — no popup needed.
        // The inline error box below the Generate button will show it.
        if (mounted) {
          // Force a rebuild so the provider error box becomes visible.
          setState(() {});
        }
      }
    }
  }
}
