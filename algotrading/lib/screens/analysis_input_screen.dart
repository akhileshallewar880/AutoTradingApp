import '../theme/vt_color_scheme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../providers/dashboard_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/api_config.dart';
import '../widgets/animated_loading_overlay.dart';
import '../widgets/section_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/vt_button.dart';
import '../widgets/vt_card.dart';
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
  int _holdDurationDays = 0;
  int _leverage = 1;
  Set<String> _selectedSectors = {'ALL'};
  double _availableBalance = 0;

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
    setState(() {
      _sectorsLoading = true;
      _sectorsError = null;
    });
    try {
      final resp = await http
          .get(Uri.parse(ApiConfig.sectorsUrl))
          .timeout(Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list =
            (data['sectors'] as List<dynamic>).cast<Map<String, dynamic>>();
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
    (label: '1D', days: 1),
    (label: '3D', days: 3),
    (label: '1W', days: 7),
    (label: '2W', days: 14),
    (label: '1M', days: 30),
  ];

  @override
  Widget build(BuildContext context) {
    final analysisProvider = context.watch<AnalysisProvider>();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            title: Row(
              children: [
                Text('AI Analysis', style: AppTextStyles.h2),
                const SizedBox(width: Sp.sm),
                const StatusBadge(label: 'GPT-4o', type: BadgeType.ai),
              ],
            ),
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(Sp.base),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Market Pulse (hero) ──────────────────────────
                          _buildSectorCard(),
                          const SizedBox(height: Sp.base),

                          // ── Hold Duration ────────────────────────────────
                          VtCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionHeader(
                                  title: 'Hold Duration',
                                  paddingTop: 0,
                                  paddingBottom: Sp.sm,
                                ),
                                Text(
                                  'Auto-sell all positions after this period',
                                  style: AppTextStyles.caption,
                                ),
                                const SizedBox(height: Sp.md),
                                _buildHoldDurationPicker(),
                                if (_holdDurationDays == 0) ...[
                                  const SizedBox(height: Sp.base),
                                  _buildLeveragePicker(),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: Sp.base),

                          // ── Capital ──────────────────────────────────────
                          _buildCapitalCard(),
                          SizedBox(height: Sp.base),

                          // ── Parameters ───────────────────────────────────
                          VtCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionHeader(
                                  title: 'Parameters',
                                  paddingTop: 0,
                                  paddingBottom: Sp.sm,
                                ),
                                _buildStockCountStepper(),
                                const SizedBox(height: Sp.base),
                                _buildDatePicker(),
                              ],
                            ),
                          ),
                          SizedBox(height: Sp.base),

                          // ── Error ────────────────────────────────────────
                          if (analysisProvider.error != null)
                            Container(
                              padding: EdgeInsets.all(Sp.md),
                              decoration: BoxDecoration(
                                color: context.vt.dangerDim,
                                borderRadius:
                                    BorderRadius.circular(Rad.md),
                                border: Border.all(
                                    color: context.vt.danger
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline,
                                      color: context.vt.danger, size: 16),
                                  SizedBox(width: Sp.sm),
                                  Expanded(
                                    child: Text(
                                      analysisProvider.error!,
                                      style: AppTextStyles.caption.copyWith(
                                          color: context.vt.danger),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: Sp.xxl),
                        ],
                      ),
                    ),
                  ),

                  // ── Fixed CTA ────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                        Sp.base, Sp.sm, Sp.base, Sp.xl),
                    decoration: BoxDecoration(
                      color: context.vt.surface1,
                      border:
                          Border(top: BorderSide(color: context.vt.divider)),
                    ),
                    child: VtButton(
                      label: 'Generate AI Analysis',
                      icon: const Icon(Icons.auto_awesome_rounded,
                          size: 18, color: Colors.white),
                      onPressed: analysisProvider.isLoading
                          ? null
                          : _handleGenerate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        if (analysisProvider.isLoading)
          const AnimatedLoadingOverlay(message: 'Analyzing markets…'),
      ],
    );
  }

  // ── Market Pulse card ─────────────────────────────────────────────────────

  Widget _buildSectorCard() {
    return VtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  title: 'Market Pulse',
                  paddingTop: 0,
                  paddingBottom: 0,
                ),
              ),
              if (_sectorsLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.vt.accentGreen,
                  ),
                )
              else
                GestureDetector(
                  onTap: _fetchSectors,
                  child: Icon(Icons.refresh_rounded,
                      size: 18, color: context.vt.textTertiary),
                ),
            ],
          ),
          SizedBox(height: Sp.xs),
          Text(
            _sectorsError != null
                ? _sectorsError!
                : 'Tap sectors to filter stocks · Most active first',
            style: AppTextStyles.caption.copyWith(
              color: _sectorsError != null
                  ? context.vt.warning
                  : context.vt.textTertiary,
            ),
          ),
          const SizedBox(height: Sp.md),

          // "All NSE" pill
          _buildAllChip(),
          const SizedBox(height: Sp.sm),

          if (_sectorsLoading && _liveSectors.isEmpty)
            _buildSectorSkeleton()
          else if (_liveSectors.isEmpty)
            _buildStaticSectorChips()
          else
            _buildLiveSectorGrid(),
        ],
      ),
    );
  }

  Widget _buildAllChip() {
    final selected = _selectedSectors.contains('ALL');
    return GestureDetector(
      onTap: () => setState(() => _selectedSectors = {'ALL'}),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding:
            EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
        decoration: BoxDecoration(
          color: selected ? context.vt.accentGreenDim : context.vt.surface2,
          borderRadius: BorderRadius.circular(Rad.pill),
          border: Border.all(
            color: selected
                ? context.vt.accentGreen.withValues(alpha: 0.5)
                : context.vt.divider,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? AppColors.greenGlow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded,
                size: 13,
                color: selected
                    ? context.vt.accentGreen
                    : context.vt.textSecondary),
            SizedBox(width: Sp.xs),
            Text(
              'All NSE',
              style: AppTextStyles.label.copyWith(
                color: selected
                    ? context.vt.accentGreen
                    : context.vt.textSecondary,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (selected) ...[
              SizedBox(width: Sp.xs),
              Icon(Icons.check_circle_rounded,
                  size: 12, color: context.vt.accentGreen),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSectorGrid() {
    return Column(
      children: _liveSectors.map((s) {
        final sectorKey = s['sector'] as String;
        final displayName = s['display_name'] as String? ?? sectorKey;
        final changePct = (s['change_pct'] as num?)?.toDouble() ?? 0.0;
        final last = (s['last'] as num?)?.toDouble() ?? 0.0;
        final selected = _selectedSectors.contains(sectorKey);
        final changeColor = _sectorColor(changePct);

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
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            margin: EdgeInsets.only(bottom: Sp.sm),
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.md, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? changeColor.withValues(alpha: 0.08)
                  : context.vt.surface2,
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(
                color: selected
                    ? changeColor.withValues(alpha: 0.6)
                    : context.vt.divider,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: changeColor.withValues(alpha: 0.15),
                        blurRadius: 8,
                        spreadRadius: -2,
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: changeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: changeColor.withValues(alpha: 0.4),
                          blurRadius: 4)
                    ],
                  ),
                ),
                SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    displayName,
                    style: AppTextStyles.body.copyWith(
                      color: selected
                          ? context.vt.textPrimary
                          : context.vt.textSecondary,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (last > 0) ...[
                  Text(
                    last >= 1000
                        ? last.toStringAsFixed(0)
                        : last.toStringAsFixed(1),
                    style: AppTextStyles.monoSm
                        .copyWith(color: context.vt.textTertiary),
                  ),
                  const SizedBox(width: Sp.sm),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: changeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rad.sm),
                  ),
                  child: Text(
                    '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                    style: AppTextStyles.monoSm.copyWith(
                      color: changeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selected) ...[
                  SizedBox(width: Sp.sm),
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: context.vt.accentGreen),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _sectorColor(double pct) {
    if (pct >= 2.0) return context.vt.accentGreen;
    if (pct >= 1.0) return Color(0xFF1DB87E);
    if (pct >= 0.5) return Color(0xFF4EC99A);
    if (pct >= 0.2) return Color(0xFF86D9B8);
    if (pct > -0.2) return context.vt.textTertiary;
    if (pct > -0.5) return Color(0xFFE9909A);
    if (pct > -1.0) return Color(0xFFD9535F);
    if (pct > -2.0) return context.vt.danger;
    return Color(0xFFB02030);
  }

  Widget _buildSectorSkeleton() {
    return Column(
      children: List.generate(
        5,
        (_) => Container(
          margin: EdgeInsets.only(bottom: Sp.sm),
          height: 44,
          decoration: BoxDecoration(
            color: context.vt.surface2,
            borderRadius: BorderRadius.circular(Rad.md),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticSectorChips() {
    const fallback = [
      'NIFTY IT',
      'NIFTY BANK',
      'NIFTY AUTO',
      'NIFTY PHARMA',
      'NIFTY FMCG',
      'NIFTY METAL',
      'NIFTY ENERGY',
      'NIFTY REALTY',
    ];
    return Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: fallback.map((s) {
        final selected = _selectedSectors.contains(s);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (selected) {
                _selectedSectors.remove(s);
                if (_selectedSectors.isEmpty) _selectedSectors = {'ALL'};
              } else {
                _selectedSectors.remove('ALL');
                _selectedSectors.add(s);
              }
            });
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              color: selected ? context.vt.accentGreenDim : context.vt.surface2,
              borderRadius: BorderRadius.circular(Rad.pill),
              border: Border.all(
                color: selected
                    ? context.vt.accentGreen.withValues(alpha: 0.5)
                    : context.vt.divider,
              ),
            ),
            child: Text(
              s.replaceFirst('NIFTY ', ''),
              style: AppTextStyles.label.copyWith(
                color: selected
                    ? context.vt.accentGreen
                    : context.vt.textSecondary,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Hold Duration segmented control ─────────────────────────────────────────

  Widget _buildHoldDurationPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _holdOptions.map((opt) {
          final selected = _holdDurationDays == opt.days;
          return GestureDetector(
            onTap: () {
              setState(() {
                _holdDurationDays = opt.days;
                if (opt.days != 0) _leverage = 1;
              });
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: Sp.sm),
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: selected ? context.vt.accentGreen : context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.pill),
                border: Border.all(
                  color: selected
                      ? context.vt.accentGreen
                      : context.vt.divider,
                ),
                boxShadow: selected ? AppColors.greenGlow : null,
              ),
              child: Text(
                opt.label,
                style: AppTextStyles.label.copyWith(
                  color: selected
                      ? context.vt.surface0
                      : context.vt.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLeveragePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded,
                color: context.vt.warning, size: 15),
            SizedBox(width: Sp.xs),
            Text('MIS Leverage',
                style: AppTextStyles.label
                    .copyWith(color: context.vt.textSecondary)),
            SizedBox(width: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: 2),
              decoration: BoxDecoration(
                color: context.vt.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Rad.pill),
                border: Border.all(
                    color: context.vt.warning.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${_leverage}x',
                style: AppTextStyles.monoSm.copyWith(
                    color: context.vt.warning, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        SizedBox(height: Sp.xs),
        Text(
          'Higher leverage = higher risk. Effective capital is multiplied.',
          style: AppTextStyles.caption,
        ),
        SizedBox(height: Sp.sm),
        Row(
          children: [1, 2, 3, 4, 5].map((lev) {
            final selected = _leverage == lev;
            return GestureDetector(
              onTap: () => setState(() => _leverage = lev),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 150),
                margin: EdgeInsets.only(right: Sp.sm),
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.md, vertical: Sp.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? context.vt.warning.withValues(alpha: 0.15)
                      : context.vt.surface2,
                  borderRadius: BorderRadius.circular(Rad.pill),
                  border: Border.all(
                    color: selected
                        ? context.vt.warning.withValues(alpha: 0.6)
                        : context.vt.divider,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  '${lev}x',
                  style: AppTextStyles.label.copyWith(
                    color: selected
                        ? context.vt.warning
                        : context.vt.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Capital card ─────────────────────────────────────────────────────────────

  Widget _buildCapitalCard() {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final pcts = [25, 50, 75, 100];

    return VtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Capital to Deploy',
            paddingTop: 0,
            paddingBottom: Sp.sm,
          ),

          // Available balance display
          if (_availableBalance > 0) ...[
            Text(
              currency.format(_availableBalance),
              style: AppTextStyles.mono.copyWith(
                  color: context.vt.accentGreen, fontSize: 22),
            ),
            Text('available balance',
                style: AppTextStyles.caption),
            SizedBox(height: Sp.md),
          ],

          // Amount input
          TextFormField(
            controller: _capitalController,
            keyboardType: TextInputType.number,
            style: AppTextStyles.mono.copyWith(fontSize: 18),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle:
                  AppTextStyles.mono.copyWith(color: context.vt.textSecondary),
              hintText: 'Enter amount',
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

          // % quick buttons
          if (_availableBalance > 0) ...[
            SizedBox(height: Sp.md),
            Row(
              children: pcts.map((pct) {
                final amount =
                    (_availableBalance * pct / 100).floorToDouble();
                final label = pct == 100 ? 'MAX' : '$pct%';
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _capitalController.text = amount.toInt().toString();
                    }),
                    child: Container(
                      margin: EdgeInsets.only(
                          right: pct == 100 ? 0 : Sp.sm),
                      padding: EdgeInsets.symmetric(vertical: Sp.sm),
                      decoration: BoxDecoration(
                        color: context.vt.surface2,
                        borderRadius: BorderRadius.circular(Rad.sm),
                        border: Border.all(color: context.vt.divider),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: AppTextStyles.label.copyWith(
                              color: context.vt.accentGreen,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Stock count stepper ───────────────────────────────────────────────────────

  Widget _buildStockCountStepper() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Number of Stocks', style: AppTextStyles.bodySecondary),
              Text('How many AI picks to generate',
                  style: AppTextStyles.caption),
            ],
          ),
        ),
        _StepperButton(
          icon: Icons.remove_rounded,
          onTap: _numStocks > 1
              ? () => setState(() => _numStocks--)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          child: Text(
            '$_numStocks',
            style: AppTextStyles.mono.copyWith(
                fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        _StepperButton(
          icon: Icons.add_rounded,
          onTap: _numStocks < 20
              ? () => setState(() => _numStocks++)
              : null,
        ),
      ],
    );
  }

  // ── Date picker ───────────────────────────────────────────────────────────────

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Analysis Date', style: AppTextStyles.bodySecondary),
        SizedBox(height: Sp.sm),
        GestureDetector(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Sp.md, vertical: Sp.md),
            decoration: BoxDecoration(
              color: context.vt.surface2,
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(color: context.vt.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEE, dd MMM yyyy').format(_selectedDate),
                  style: AppTextStyles.body,
                ),
                Icon(Icons.calendar_today_rounded,
                    color: context.vt.accentGreen, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _handleGenerate() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final analysisProvider = context.read<AnalysisProvider>();
      final capitalToUse =
          double.tryParse(_capitalController.text.trim()) ?? _availableBalance;

      analysisProvider.setHoldDuration(_holdDurationDays);
      analysisProvider.setSelectedSectors(_selectedSectors.toList());

      try {
        int userId;
        try {
          userId = int.parse(authProvider.user!.userId);
        } catch (_) {
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
      } catch (_) {
        if (mounted) setState(() {});
      }
    }
  }
}

// ── Stepper button ────────────────────────────────────────────────────────────

class _StepperButton extends StatelessWidget {
  _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? context.vt.surface2 : context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(
            color: enabled
                ? context.vt.accentGreen.withValues(alpha: 0.4)
                : context.vt.divider,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? context.vt.accentGreen : context.vt.textTertiary,
        ),
      ),
    );
  }
}
