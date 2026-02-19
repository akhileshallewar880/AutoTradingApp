import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../widgets/animated_loading_overlay.dart';
import 'analysis_results_screen.dart';

class AnalysisInputScreen extends StatefulWidget {
  const AnalysisInputScreen({super.key});

  @override
  State<AnalysisInputScreen> createState() => _AnalysisInputScreenState();
}

class _AnalysisInputScreenState extends State<AnalysisInputScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  int _numStocks = 5;
  double _riskPercent = 1.0;
  int _holdDurationDays = 0; // 0 = Intraday
  Set<String> _selectedSectors = {'ALL'};

  static const _sectors = [
    'ALL',
    'NIFTY 50',
    'NIFTY Bank',
    'IT',
    'Pharma',
    'Auto',
    'FMCG',
    'Energy',
    'Metal',
  ];

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
                            const SizedBox(height: 20),
                            _buildRiskPercentSlider(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Sector Selection Card ────────────────────────────
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
                                Icons.category_outlined, 'Stock Universe'),
                            const SizedBox(height: 4),
                            Text(
                              'ALL = entire NSE market (~1800 stocks). Select specific sectors to narrow focus.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 14),
                            _buildSectorSelector(),
                          ],
                        ),
                      ),
                    ),
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
                          ],
                        ),
                      ),
                    ),
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

  Widget _buildRiskPercentSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Risk Per Trade',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700])),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _riskPercent > 3.0
                    ? Colors.orange[700]
                    : Colors.green[700],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_riskPercent.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        Slider(
          value: _riskPercent,
          min: 0.5,
          max: 5.0,
          divisions: 45,
          label: '${_riskPercent.toStringAsFixed(1)}%',
          activeColor:
              _riskPercent > 3.0 ? Colors.orange[700] : Colors.green[700],
          inactiveColor: Colors.green[100],
          onChanged: (value) {
            setState(() => _riskPercent = value);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0.5% (Low)',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text('5.0% (High)',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }

  Widget _buildSectorSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _sectors.map((sector) {
        final selected = _selectedSectors.contains(sector);
        return FilterChip(
          label: Text(
            sector == 'ALL' ? '🌐 All NSE' : sector,
          ),
          selected: selected,
          onSelected: (val) {
            setState(() {
              if (sector == 'ALL') {
                // ALL is exclusive — deselect everything else
                _selectedSectors = {'ALL'};
              } else {
                if (val) {
                  // Selecting a specific sector removes ALL
                  _selectedSectors.remove('ALL');
                  _selectedSectors.add(sector);
                } else {
                  _selectedSectors.remove(sector);
                  // Fall back to ALL if nothing selected
                  if (_selectedSectors.isEmpty) {
                    _selectedSectors = {'ALL'};
                  }
                }
              }
            });
          },
          selectedColor: Colors.green[100],
          checkmarkColor: Colors.green[700],
          labelStyle: TextStyle(
            color: selected ? Colors.green[800] : Colors.grey[700],
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
            color: selected ? Colors.green[400]! : Colors.grey[300]!,
          ),
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
            setState(() => _holdDurationDays = opt.days);
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

      // Persist hold duration and sectors to provider
      analysisProvider.setHoldDuration(_holdDurationDays);
      analysisProvider.setSelectedSectors(_selectedSectors.toList());

      try {
        await analysisProvider.generateAnalysis(
          analysisDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
          numStocks: _numStocks,
          riskPercent: _riskPercent,
          accessToken: authProvider.user!.accessToken,
          sectors: _selectedSectors.toList(),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red[700],
            ),
          );
        }
      }
    }
  }
}
