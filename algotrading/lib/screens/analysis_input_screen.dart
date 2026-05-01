import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../providers/dashboard_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/animated_loading_overlay.dart';
import '../widgets/section_header.dart';
import '../widgets/vt_button.dart';
import '../widgets/vt_card.dart';
import 'analysis_results_screen.dart';

// ── NSE stock catalogue used by the search feature ───────────────────────────
const _kNseStocks = <(String, String)>[
  ('RELIANCE', 'Reliance Industries'),
  ('TCS', 'Tata Consultancy Services'),
  ('HDFCBANK', 'HDFC Bank'),
  ('BHARTIARTL', 'Bharti Airtel'),
  ('ICICIBANK', 'ICICI Bank'),
  ('INFY', 'Infosys'),
  ('SBIN', 'State Bank of India'),
  ('HINDUNILVR', 'Hindustan Unilever'),
  ('ITC', 'ITC Limited'),
  ('KOTAKBANK', 'Kotak Mahindra Bank'),
  ('LT', 'Larsen & Toubro'),
  ('HCLTECH', 'HCL Technologies'),
  ('BAJFINANCE', 'Bajaj Finance'),
  ('AXISBANK', 'Axis Bank'),
  ('ASIANPAINT', 'Asian Paints'),
  ('MARUTI', 'Maruti Suzuki India'),
  ('SUNPHARMA', 'Sun Pharmaceutical'),
  ('TITAN', 'Titan Company'),
  ('ULTRACEMCO', 'UltraTech Cement'),
  ('WIPRO', 'Wipro'),
  ('NTPC', 'NTPC'),
  ('POWERGRID', 'Power Grid Corporation'),
  ('M&M', 'Mahindra & Mahindra'),
  ('NESTLEIND', 'Nestle India'),
  ('TECHM', 'Tech Mahindra'),
  ('TATAMOTORS', 'Tata Motors'),
  ('TATACONSUM', 'Tata Consumer Products'),
  ('TATASTEEL', 'Tata Steel'),
  ('ADANIENT', 'Adani Enterprises'),
  ('ADANIPORTS', 'Adani Ports & SEZ'),
  ('COALINDIA', 'Coal India'),
  ('DRREDDY', "Dr. Reddy's Laboratories"),
  ('EICHERMOT', 'Eicher Motors'),
  ('GRASIM', 'Grasim Industries'),
  ('HEROMOTOCO', 'Hero MotoCorp'),
  ('HINDALCO', 'Hindalco Industries'),
  ('INDUSINDBK', 'IndusInd Bank'),
  ('JSWSTEEL', 'JSW Steel'),
  ('ONGC', 'Oil & Natural Gas Corp'),
  ('BAJAJFINSV', 'Bajaj Finserv'),
  ('BPCL', 'Bharat Petroleum'),
  ('BRITANNIA', 'Britannia Industries'),
  ('CIPLA', 'Cipla'),
  ('DIVISLAB', "Divi's Laboratories"),
  ('SBILIFE', 'SBI Life Insurance'),
  ('HDFCLIFE', 'HDFC Life Insurance'),
  ('APOLLOHOSP', 'Apollo Hospitals'),
  ('BAJAJ-AUTO', 'Bajaj Auto'),
  ('TATAPOWER', 'Tata Power'),
  ('SIEMENS', 'Siemens India'),
  ('HAVELLS', 'Havells India'),
  ('PIDILITIND', 'Pidilite Industries'),
  ('DABUR', 'Dabur India'),
  ('MARICO', 'Marico'),
  ('COLPAL', 'Colgate-Palmolive India'),
  ('GODREJCP', 'Godrej Consumer Products'),
  ('TRENT', 'Trent'),
  ('DMART', 'Avenue Supermarts (DMart)'),
  ('IRCTC', 'Indian Railway Catering'),
  ('DLF', 'DLF'),
  ('ZOMATO', 'Zomato'),
  ('PNB', 'Punjab National Bank'),
  ('BANKBARODA', 'Bank of Baroda'),
  ('FEDERALBNK', 'Federal Bank'),
  ('IDFCFIRSTB', 'IDFC First Bank'),
  ('BANDHANBNK', 'Bandhan Bank'),
  ('MUTHOOTFIN', 'Muthoot Finance'),
  ('RECLTD', 'REC'),
  ('PFC', 'Power Finance Corporation'),
  ('CONCOR', 'Container Corporation'),
  ('SHRIRAMFIN', 'Shriram Finance'),
  ('CHOLAFIN', 'Cholamandalam Investment'),
  ('MANAPPURAM', 'Manappuram Finance'),
  ('LTIM', 'LTIMindtree'),
  ('MPHASIS', 'Mphasis'),
  ('COFORGE', 'Coforge'),
  ('PERSISTENT', 'Persistent Systems'),
  ('KPIT', 'KPIT Technologies'),
  ('OFSS', 'Oracle Financial Services'),
  ('TATAELXSI', 'Tata Elxsi'),
  ('DIXON', 'Dixon Technologies'),
  ('POLYCAB', 'Polycab India'),
  ('VOLTAS', 'Voltas'),
  ('GODREJPROP', 'Godrej Properties'),
  ('OBEROIRLTY', 'Oberoi Realty'),
  ('GAIL', 'GAIL India'),
  ('PETRONET', 'Petronet LNG'),
  ('IGL', 'Indraprastha Gas'),
  ('VEDL', 'Vedanta'),
  ('NMDC', 'NMDC'),
  ('SAIL', 'Steel Authority of India'),
  ('JINDALSTEL', 'Jindal Steel & Power'),
  ('INTERGLOBE', 'IndiGo (InterGlobe Aviation)'),
  ('ACC', 'ACC'),
  ('AMBUJACEM', 'Ambuja Cements'),
  ('SHREECEM', 'Shree Cement'),
  ('UPL', 'UPL'),
  ('TORNTPHARM', 'Torrent Pharmaceuticals'),
  ('BIOCON', 'Biocon'),
  ('ALKEM', 'Alkem Laboratories'),
  ('LUPIN', 'Lupin'),
  ('HAL', 'Hindustan Aeronautics'),
  ('BEL', 'Bharat Electronics'),
  ('BHEL', 'BHEL'),
  ('ADANIGREEN', 'Adani Green Energy'),
  ('ADANIPOWER', 'Adani Power'),
  ('TORNTPOWER', 'Torrent Power'),
  ('SUZLON', 'Suzlon Energy'),
  ('NAUKRI', 'Info Edge (Naukri)'),
  ('INDIAMART', 'IndiaMART InterMESH'),
  ('PIIND', 'PI Industries'),
  ('ABBOTINDIA', 'Abbott India'),
  ('MAXHEALTH', 'Max Healthcare Institute'),
  ('FORTIS', 'Fortis Healthcare'),
  ('TATACOMM', 'Tata Communications'),
  ('RAILTEL', 'RailTel Corporation'),
  ('BEML', 'BEML'),
  ('ASTRAL', 'Astral'),
  ('PAGEIND', 'Page Industries'),
  ('ABB', 'ABB India'),
  ('CUMMINSIND', 'Cummins India'),
  ('THERMAX', 'Thermax'),
  ('SBICARD', 'SBI Cards'),
  ('ICICIPRULI', 'ICICI Prudential Life'),
  ('LICI', 'Life Insurance Corporation'),
];

class AnalysisInputScreen extends StatefulWidget {
  const AnalysisInputScreen({super.key});

  @override
  State<AnalysisInputScreen> createState() => _AnalysisInputScreenState();
}

class _AnalysisInputScreenState extends State<AnalysisInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _capitalController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  DateTime _selectedDate = DateTime.now();
  int _numStocks = 5;
  int _holdDurationDays = 3;
  int _leverage = 1;
  double _availableBalance = 0;

  // Manual stock selection
  final Set<String> _selectedSymbols = {};
  String _searchQuery = '';
  bool _searchFocused = false;

  static const int _maxSymbols = 10;

  static const _holdOptions = [
    (label: 'Intraday', days: 0),
    (label: '1D', days: 1),
    (label: '3D', days: 3),
    (label: '1W', days: 7),
    (label: '2W', days: 14),
    (label: '1M', days: 30),
  ];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final balance =
          context.read<DashboardProvider>().dashboard?.availableBalance ?? 0;
      setState(() => _availableBalance = balance);
      _capitalController.text = balance > 0 ? balance.floor().toString() : '';
    });
  }

  @override
  void dispose() {
    _capitalController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<(String, String)> get _filteredStocks {
    if (_searchQuery.isEmpty) return const [];
    final q = _searchQuery.toUpperCase();
    return _kNseStocks
        .where((s) =>
            (s.$1.contains(q) || s.$2.toUpperCase().contains(q)) &&
            !_selectedSymbols.contains(s.$1))
        .take(8)
        .toList();
  }

  void _addSymbol(String symbol) {
    if (_selectedSymbols.length >= _maxSymbols) return;
    setState(() {
      _selectedSymbols.add(symbol);
      _searchController.clear();
      _searchQuery = '';
    });
    _searchFocus.unfocus();
  }

  void _removeSymbol(String symbol) {
    setState(() => _selectedSymbols.remove(symbol));
  }

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
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.vt.accentPurpleDim,
                    borderRadius: BorderRadius.circular(Rad.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 11, color: context.vt.accentPurple),
                      const SizedBox(width: 4),
                      Text('GPT-4o',
                          style: AppTextStyles.caption.copyWith(
                              color: context.vt.accentPurple,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: GestureDetector(
            onTap: () => _searchFocus.unfocus(),
            child: SafeArea(
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
                            // ── Stock Search ──────────────────────────────
                            _buildStockSearchCard(),
                            const SizedBox(height: Sp.base),

                            // ── Hold Duration ─────────────────────────────
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
                                    style: AppTextStyles.caption.copyWith(
                                        color: context.vt.textSecondary),
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

                            // ── Capital ───────────────────────────────────
                            _buildCapitalCard(),
                            const SizedBox(height: Sp.base),

                            // ── Parameters ────────────────────────────────
                            VtCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SectionHeader(
                                    title: 'Parameters',
                                    paddingTop: 0,
                                    paddingBottom: Sp.sm,
                                  ),
                                  if (_selectedSymbols.isEmpty)
                                    _buildStockCountStepper(),
                                  if (_selectedSymbols.isEmpty)
                                    const SizedBox(height: Sp.base),
                                  _buildDatePicker(),
                                ],
                              ),
                            ),
                            const SizedBox(height: Sp.base),

                            // ── Error ─────────────────────────────────────
                            if (analysisProvider.error != null)
                              Container(
                                padding: const EdgeInsets.all(Sp.md),
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
                                    const SizedBox(width: Sp.sm),
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

                    // ── Fixed CTA ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                          Sp.base, Sp.sm, Sp.base, Sp.xl),
                      decoration: BoxDecoration(
                        color: context.vt.surface1,
                        border: Border(
                            top: BorderSide(color: context.vt.divider)),
                      ),
                      child: VtButton(
                        label: _selectedSymbols.isNotEmpty
                            ? 'Analyse ${_selectedSymbols.length} Stock${_selectedSymbols.length == 1 ? '' : 's'}'
                            : 'Generate AI Analysis',
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
        ),

        if (analysisProvider.isLoading)
          const AnimatedLoadingOverlay(message: 'Analyzing markets…'),
      ],
    );
  }

  // ── Stock Search card ─────────────────────────────────────────────────────

  Widget _buildStockSearchCard() {
    return VtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Select Stocks',
            paddingTop: 0,
            paddingBottom: Sp.xs,
          ),
          Text(
            _selectedSymbols.isEmpty
                ? 'Search NSE symbols to target specific stocks, or leave empty for AI auto-pick'
                : '${_selectedSymbols.length}/$_maxSymbols selected · AI analyses only these',
            style: AppTextStyles.caption
                .copyWith(color: context.vt.textSecondary),
          ),
          const SizedBox(height: Sp.md),

          // Search field
          Container(
            decoration: BoxDecoration(
              color: context.vt.surface2,
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(
                color: _searchFocused
                    ? context.vt.accentGreen.withValues(alpha: 0.6)
                    : context.vt.divider,
                width: _searchFocused ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: Sp.md),
                  child: Icon(Icons.search_rounded,
                      size: 18,
                      color: _searchFocused
                          ? context.vt.accentGreen
                          : context.vt.textTertiary),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'Search symbol or company name…',
                      hintStyle: AppTextStyles.body
                          .copyWith(color: context.vt.textTertiary),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: Sp.sm, vertical: Sp.md),
                      filled: false,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    enabled: _selectedSymbols.length < _maxSymbols,
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: Sp.sm),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: context.vt.textTertiary),
                    ),
                  ),
              ],
            ),
          ),

          // Search results dropdown
          if (_filteredStocks.isNotEmpty) ...[
            const SizedBox(height: Sp.xs),
            Container(
              decoration: BoxDecoration(
                color: context.vt.surface1,
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(color: context.vt.divider),
              ),
              child: Column(
                children: _filteredStocks.asMap().entries.map((e) {
                  final idx = e.key;
                  final stock = e.value;
                  final isLast = idx == _filteredStocks.length - 1;
                  return InkWell(
                    onTap: () => _addSymbol(stock.$1),
                    borderRadius: BorderRadius.circular(Rad.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.md, vertical: Sp.sm),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                                bottom:
                                    BorderSide(color: context.vt.divider)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sp.sm, vertical: 3),
                            decoration: BoxDecoration(
                              color: context.vt.surface2,
                              borderRadius: BorderRadius.circular(Rad.sm),
                            ),
                            child: Text(
                              stock.$1,
                              style: AppTextStyles.monoSm.copyWith(
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: Sp.sm),
                          Expanded(
                            child: Text(
                              stock.$2,
                              style: AppTextStyles.caption.copyWith(
                                  color: context.vt.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.add_circle_outline_rounded,
                              size: 18, color: context.vt.accentGreen),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Selected chips
          if (_selectedSymbols.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: _selectedSymbols.map((sym) {
                return Container(
                  padding: const EdgeInsets.only(
                      left: Sp.sm, top: 5, bottom: 5, right: 4),
                  decoration: BoxDecoration(
                    color: context.vt.accentGreenDim,
                    borderRadius: BorderRadius.circular(Rad.pill),
                    border: Border.all(
                        color:
                            context.vt.accentGreen.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sym,
                        style: AppTextStyles.label.copyWith(
                            color: context.vt.accentGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _removeSymbol(sym),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: context.vt.accentGreen),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Hold Duration segmented control ──────────────────────────────────────

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
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: Sp.sm),
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: selected
                    ? context.vt.accentGreen
                    : context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.pill),
                border: Border.all(
                  color: selected
                      ? context.vt.accentGreen
                      : context.vt.divider,
                ),
              ),
              child: Text(
                opt.label,
                style: AppTextStyles.label.copyWith(
                  color: selected
                      ? context.vt.surface0
                      : context.vt.textSecondary,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
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
            Icon(Icons.bolt_rounded, color: context.vt.warning, size: 15),
            const SizedBox(width: Sp.xs),
            Text('MIS Leverage',
                style: AppTextStyles.label
                    .copyWith(color: context.vt.textSecondary)),
            const SizedBox(width: Sp.sm),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
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
        const SizedBox(height: Sp.xs),
        Text(
          'Higher leverage = higher risk. Effective capital is multiplied.',
          style:
              AppTextStyles.caption.copyWith(color: context.vt.textSecondary),
        ),
        const SizedBox(height: Sp.sm),
        Row(
          children: [1, 2, 3, 4, 5].map((lev) {
            final selected = _leverage == lev;
            return GestureDetector(
              onTap: () => setState(() => _leverage = lev),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: Sp.sm),
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

  // ── Capital card ──────────────────────────────────────────────────────────

  Widget _buildCapitalCard() {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    const pcts = [25, 50, 75, 100];

    return VtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Capital to Deploy',
            paddingTop: 0,
            paddingBottom: Sp.sm,
          ),
          if (_availableBalance > 0) ...[
            Text(
              currency.format(_availableBalance),
              style: AppTextStyles.mono.copyWith(
                  color: context.vt.accentGreen, fontSize: 22),
            ),
            Text('available balance',
                style: AppTextStyles.caption
                    .copyWith(color: context.vt.textSecondary)),
            const SizedBox(height: Sp.md),
          ],
          TextFormField(
            controller: _capitalController,
            keyboardType: TextInputType.number,
            style: AppTextStyles.mono.copyWith(fontSize: 18),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: AppTextStyles.mono
                  .copyWith(color: context.vt.textSecondary),
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
          if (_availableBalance > 0) ...[
            const SizedBox(height: Sp.md),
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
                      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
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

  // ── Stock count stepper ───────────────────────────────────────────────────

  Widget _buildStockCountStepper() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Number of Stocks',
                  style: AppTextStyles.body
                      .copyWith(color: context.vt.textPrimary)),
              Text('How many AI picks to generate',
                  style: AppTextStyles.caption
                      .copyWith(color: context.vt.textSecondary)),
            ],
          ),
        ),
        _StepperButton(
          icon: Icons.remove_rounded,
          onTap: _numStocks > 1 ? () => setState(() => _numStocks--) : null,
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
          onTap: _numStocks < 20 ? () => setState(() => _numStocks++) : null,
        ),
      ],
    );
  }

  // ── Date picker ───────────────────────────────────────────────────────────

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Analysis Date',
            style: AppTextStyles.body
                .copyWith(color: context.vt.textPrimary)),
        const SizedBox(height: Sp.sm),
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
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
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

      try {
        int userId;
        try {
          userId = int.parse(authProvider.user!.userId);
        } catch (_) {
          userId = authProvider.user!.userId.hashCode.abs();
        }

        final symbols =
            _selectedSymbols.isNotEmpty ? _selectedSymbols.toList() : null;
        final numStocks = symbols != null ? symbols.length : _numStocks;

        await analysisProvider.generateAnalysis(
          analysisDate: DateFormat('yyyy-MM-dd').format(_selectedDate),
          numStocks: numStocks,
          riskPercent: 1.0,
          accessToken: authProvider.user!.accessToken,
          apiKey: authProvider.user!.apiKey,
          userId: userId,
          capitalToUse: capitalToUse,
          leverage: _holdDurationDays == 0 ? _leverage : 1,
          symbols: symbols,
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
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? context.vt.accentGreen.withValues(alpha: 0.12)
              : context.vt.surface2,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(
            color: enabled
                ? context.vt.accentGreen.withValues(alpha: 0.4)
                : context.vt.divider,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? context.vt.accentGreen : context.vt.textTertiary,
        ),
      ),
    );
  }
}
