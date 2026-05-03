import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/analysis_model.dart';
import '../providers/analysis_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

class StockCard extends StatefulWidget {
  final StockAnalysisModel stock;
  final int stockIndex;
  final bool isSelected;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onSelectionChanged;

  const StockCard({
    super.key,
    required this.stock,
    required this.stockIndex,
    this.isSelected = true,
    this.initiallyExpanded = false,
    this.onSelectionChanged,
  });

  @override
  State<StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<StockCard>
    with SingleTickerProviderStateMixin {
  late TextEditingController _qtyController;
  bool _isEditingQty = false;
  bool _expanded = false;
  late final AnimationController _expandAnim;
  late final Animation<double> _expandFade;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _qtyController =
        TextEditingController(text: widget.stock.quantity.toString());
    _expandAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandFade =
        CurvedAnimation(parent: _expandAnim, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(StockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditingQty && oldWidget.stock.quantity != widget.stock.quantity) {
      _qtyController.text = widget.stock.quantity.toString();
    }
    // Sync expand state when parent toggles all
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      if (widget.initiallyExpanded) {
        _expandAnim.forward();
      } else {
        _expandAnim.reverse();
      }
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _expandAnim.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandAnim.forward();
    } else {
      _expandAnim.reverse();
    }
  }

  void _increment() {
    context
        .read<AnalysisProvider>()
        .updateStockQuantity(widget.stockIndex, widget.stock.quantity + 1);
  }

  void _decrement() {
    if (widget.stock.quantity <= 1) return;
    context
        .read<AnalysisProvider>()
        .updateStockQuantity(widget.stockIndex, widget.stock.quantity - 1);
  }

  void _commitTextEdit() {
    final parsed = int.tryParse(_qtyController.text);
    if (parsed != null && parsed >= 1) {
      context
          .read<AnalysisProvider>()
          .updateStockQuantity(widget.stockIndex, parsed);
    } else {
      _qtyController.text = widget.stock.quantity.toString();
    }
    setState(() => _isEditingQty = false);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
    final currencyInt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final isBuy = widget.stock.action == 'BUY';
    final accentColor = isBuy ? context.vt.accentGreen : context.vt.danger;
    final confPct = (widget.stock.confidenceScore * 100).round();

    // Potential gain % toward target
    final gainPct = widget.stock.entryPrice > 0
        ? ((widget.stock.targetPrice - widget.stock.entryPrice).abs() /
                widget.stock.entryPrice *
                100)
            .toStringAsFixed(1)
        : '0.0';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.isSelected ? 1.0 : 0.55,
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          margin: const EdgeInsets.only(bottom: Sp.sm),
          decoration: BoxDecoration(
            color: context.vt.surface1,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(
              color: widget.isSelected
                  ? accentColor.withValues(alpha: 0.35)
                  : context.vt.divider,
            ),
            boxShadow: widget.isSelected
                ? [BoxShadow(
                    color: accentColor.withValues(alpha: 0.06),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  )]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Rad.lg),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left accent bar ──────────────────────────────────────
                  Container(width: 4, color: accentColor),

                  // ── Card content ─────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Collapsed header ─────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Sp.md, Sp.md, Sp.md, Sp.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1 — Checkbox · Symbol · BUY/SHORT · days  |  Entry
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: widget.isSelected,
                                      onChanged: (val) => widget
                                          .onSelectionChanged
                                          ?.call(val ?? false),
                                      activeColor: accentColor,
                                      side: BorderSide(
                                          color: context.vt.textTertiary,
                                          width: 1.5),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: Sp.xs),
                                  Text(widget.stock.stockSymbol,
                                      style: AppTextStyles.h3),
                                  const SizedBox(width: Sp.xs),
                                  _ActionBadge(
                                      isBuy: isBuy, accentColor: accentColor),
                                  if (widget.stock.daysToTarget != null) ...[
                                    const SizedBox(width: Sp.xs),
                                    _DaysChip(days: widget.stock.daysToTarget!),
                                  ],
                                  const Spacer(),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('Entry',
                                          style: AppTextStyles.caption.copyWith(
                                              color: context.vt.textTertiary)),
                                      Text(
                                        currency.format(widget.stock.entryPrice),
                                        style: AppTextStyles.mono.copyWith(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: Sp.xs),

                              // Row 2 — Company name  |  Target + gain pill
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (widget.stock.companyName != null)
                                    Expanded(
                                      child: Text(
                                        widget.stock.companyName!,
                                        style: AppTextStyles.caption.copyWith(
                                            color: context.vt.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isBuy
                                            ? Icons.trending_up_rounded
                                            : Icons.trending_down_rounded,
                                        size: 12,
                                        color: accentColor,
                                      ),
                                      const SizedBox(width: Sp.xs),
                                      Text(
                                        currency.format(widget.stock.targetPrice),
                                        style: AppTextStyles.monoSm.copyWith(
                                            color: accentColor,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: Sp.xs),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: Sp.xs, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(Rad.pill),
                                        ),
                                        child: Text(
                                          '+$gainPct%',
                                          style: AppTextStyles.caption.copyWith(
                                              color: accentColor,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: Sp.xs),

                              // Row 3 — SL pill  |  Confidence bar + %  |  Expand
                              Row(
                                children: [
                                  // SL pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: Sp.xs, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: context.vt.danger
                                          .withValues(alpha: 0.08),
                                      borderRadius:
                                          BorderRadius.circular(Rad.pill),
                                      border: Border.all(
                                          color: context.vt.danger
                                              .withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('SL',
                                            style: AppTextStyles.caption.copyWith(
                                                color: context.vt.danger,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(width: Sp.xs),
                                        Text(
                                          currencyInt.format(widget.stock.stopLoss),
                                          style: AppTextStyles.monoSm.copyWith(
                                              color: context.vt.danger,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: Sp.sm),
                                  // Confidence: filled pill bar with % label
                                  SizedBox(
                                    width: 64,
                                    height: 20,
                                    child: Stack(
                                      children: [
                                        // Track
                                        Container(
                                          decoration: BoxDecoration(
                                            color: context.vt.surface3,
                                            borderRadius: BorderRadius.circular(Rad.pill),
                                          ),
                                        ),
                                        // Fill
                                        FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: widget.stock.confidenceScore
                                              .clamp(0.0, 1.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _confColor(confPct)
                                                  .withValues(alpha: 0.85),
                                              borderRadius:
                                                  BorderRadius.circular(Rad.pill),
                                            ),
                                          ),
                                        ),
                                        // Label centred over bar
                                        Center(
                                          child: Text(
                                            '$confPct%',
                                            style: AppTextStyles.caption.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  // Expand arrow
                                  RotationTransition(
                                    turns: Tween<double>(begin: 0, end: 0.5)
                                        .animate(_expandFade),
                                    child: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: context.vt.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Expanded detail ───────────────────────────────
                        SizeTransition(
                          sizeFactor: _expandFade,
                          child: FadeTransition(
                            opacity: _expandFade,
                            child:
                                _buildExpandedBody(currency, isBuy, accentColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedBody(
    NumberFormat currency,
    bool isBuy,
    Color accentColor,
  ) {
    final totalInvest = widget.stock.entryPrice * widget.stock.quantity;
    final rrRatio = widget.stock.riskRewardRatio;
    // Reward fraction for the RR bar: reward/(reward+risk)
    final rrBarFraction = rrRatio > 0 ? rrRatio / (rrRatio + 1) : 0.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, color: context.vt.divider),

        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Price levels: SL ← Entry → Target ──────────────────────
              _buildPriceLevels(currency, isBuy),
              const SizedBox(height: Sp.sm),

              // ── R:R bar ─────────────────────────────────────────────────
              _buildRRBar(rrBarFraction, rrRatio),
              SizedBox(height: Sp.sm),

              // ── Quantity editor ─────────────────────────────────────────
              _buildQtyRow(),
              SizedBox(height: Sp.xs),

              // ── P&L metrics ─────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _PnLTile(
                      label: 'Max Profit',
                      value: currency.format(widget.stock.potentialProfit),
                      pct: totalInvest > 0
                          ? widget.stock.potentialProfit / totalInvest * 100
                          : null,
                      color: context.vt.accentGreen,
                    ),
                  ),
                  SizedBox(width: Sp.xs),
                  Expanded(
                    child: _PnLTile(
                      label: 'Max Loss',
                      value: currency.format(widget.stock.potentialLoss),
                      pct: totalInvest > 0
                          ? widget.stock.potentialLoss / totalInvest * 100
                          : null,
                      color: context.vt.danger,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Sp.sm),

              // ── AI Reasoning ─────────────────────────────────────────────
              Container(
                padding: EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  color: context.vt.surface2,
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(
                      color: context.vt.accentPurple.withValues(alpha: 0.2)),
                  // Left purple border
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 3,
                      height: null,
                      margin: EdgeInsets.only(right: Sp.sm),
                      decoration: BoxDecoration(
                        color: context.vt.accentPurple,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  size: 12, color: context.vt.accentPurple),
                              SizedBox(width: Sp.xs),
                              Text(
                                'AI Reasoning',
                                style: AppTextStyles.label.copyWith(
                                    color: context.vt.accentPurple,
                                    fontSize: 11),
                              ),
                            ],
                          ),
                          SizedBox(height: Sp.xs),
                          Text(
                            widget.stock.aiReasoning,
                            style: AppTextStyles.caption.copyWith(
                              color: context.vt.textSecondary,
                              height: 1.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceLevels(NumberFormat currency, bool isBuy) {
    return Row(
      children: [
        // Stop Loss box
        Expanded(
          child: _priceLevelBox(
            label: isBuy ? 'Stop Loss' : 'SL (Cover)',
            value: currency.format(widget.stock.stopLoss),
            color: context.vt.danger,
            bgAlpha: 0.07,
          ),
        ),
        // Arrow SL → Entry
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
          child: Icon(
            isBuy ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            size: 14,
            color: context.vt.textTertiary,
          ),
        ),
        // Entry box (neutral, centre)
        Expanded(
          child: _priceLevelBox(
            label: 'Entry',
            value: currency.format(widget.stock.entryPrice),
            color: context.vt.textPrimary,
            bgAlpha: 0.04,
            isEntry: true,
          ),
        ),
        // Arrow Entry → Target
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
          child: Icon(
            isBuy ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            size: 14,
            color: isBuy ? context.vt.accentGreen : context.vt.danger,
          ),
        ),
        // Target box
        Expanded(
          child: _priceLevelBox(
            label: isBuy ? 'Target' : 'Target (Cover)',
            value: currency.format(widget.stock.targetPrice),
            color: context.vt.accentGreen,
            bgAlpha: 0.07,
          ),
        ),
      ],
    );
  }

  Widget _priceLevelBox({
    required String label,
    required String value,
    required Color color,
    required double bgAlpha,
    bool isEntry = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: color.withValues(alpha: isEntry ? 0.1 : 0.18)),
      ),
      child: Column(
        children: [
          Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: color, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(value,
              style: AppTextStyles.monoSm
                  .copyWith(color: color, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildRRBar(double rewardFraction, double rrRatio) {
    final riskPct = ((1 - rewardFraction) * 100).round().clamp(1, 99);
    final rewardPct = (rewardFraction * 100).round().clamp(1, 99);
    final isGoodRR = rrRatio >= 2.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text('R:R Ratio',
                  style: AppTextStyles.caption
                      .copyWith(color: context.vt.textSecondary)),
              const SizedBox(width: Sp.xs),
              if (isGoodRR)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.xs, vertical: 1),
                  decoration: BoxDecoration(
                    color: context.vt.accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Rad.pill),
                  ),
                  child: Text('GOOD',
                      style: AppTextStyles.caption.copyWith(
                          color: context.vt.accentGreen,
                          fontWeight: FontWeight.w700)),
                ),
            ]),
            Text(
              '1 : ${rrRatio.toStringAsFixed(2)}',
              style: AppTextStyles.monoSm.copyWith(
                  color: isGoodRR
                      ? context.vt.accentGreen
                      : context.vt.textPrimary,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: Sp.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Rad.pill),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                Expanded(
                  flex: riskPct,
                  child: Container(color: context.vt.danger.withValues(alpha: 0.75)),
                ),
                Expanded(
                  flex: rewardPct,
                  child: Container(
                      color: context.vt.accentGreen.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Risk',
                style: AppTextStyles.caption
                    .copyWith(color: context.vt.danger)),
            Text('Reward',
                style: AppTextStyles.caption
                    .copyWith(color: context.vt.accentGreen)),
          ],
        ),
      ],
    );
  }

  Widget _buildQtyRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Quantity', style: AppTextStyles.bodySecondary),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _QtyButton(icon: Icons.remove_rounded, onTap: _decrement,
                enabled: widget.stock.quantity > 1),
            SizedBox(width: Sp.sm),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isEditingQty = true;
                  _qtyController.text = widget.stock.quantity.toString();
                  _qtyController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _qtyController.text.length);
                });
              },
              child: _isEditingQty
                  ? SizedBox(
                      width: 52,
                      height: 32,
                      child: TextField(
                        controller: _qtyController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textAlign: TextAlign.center,
                        style: AppTextStyles.mono
                            .copyWith(fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: Sp.sm, vertical: Sp.sm),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(Rad.sm)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Rad.sm),
                            borderSide: BorderSide(
                                color: context.vt.accentGreen, width: 1.5),
                          ),
                        ),
                        onSubmitted: (_) => _commitTextEdit(),
                        onTapOutside: (_) => _commitTextEdit(),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.md, vertical: Sp.xs),
                      decoration: BoxDecoration(
                        color: context.vt.surface2,
                        borderRadius: BorderRadius.circular(Rad.sm),
                        border: Border.all(color: context.vt.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.stock.quantity.toString(),
                              style: AppTextStyles.mono.copyWith(
                                  fontWeight: FontWeight.w700)),
                          SizedBox(width: Sp.xs),
                          Icon(Icons.edit_rounded,
                              size: 10,
                              color: context.vt.textTertiary),
                        ],
                      ),
                    ),
            ),
            const SizedBox(width: Sp.sm),
            _QtyButton(icon: Icons.add_rounded, onTap: _increment, enabled: true),
          ],
        ),
      ],
    );
  }

  Color _confColor(int pct) {
    if (pct >= 80) return context.vt.accentGreen;
    if (pct >= 70) return context.vt.warning;
    return context.vt.danger;
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _ActionBadge extends StatelessWidget {
  const _ActionBadge({required this.isBuy, required this.accentColor});
  final bool isBuy;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        isBuy ? 'BUY' : 'SHORT',
        style: AppTextStyles.label.copyWith(
          color: accentColor,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DaysChip extends StatelessWidget {
  const _DaysChip({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    final color = days > 5
        ? context.vt.accentGreen
        : days > 2
            ? context.vt.warning
            : context.vt.danger;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 10, color: color),
          const SizedBox(width: 3),
          Text('~${days}d to target',
              style: AppTextStyles.caption
                  .copyWith(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PnLTile extends StatelessWidget {
  const _PnLTile(
      {required this.label,
      required this.value,
      required this.color,
      this.pct});
  final String label;
  final String value;
  final Color color;
  final double? pct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: color, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: AppTextStyles.monoSm
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
          if (pct != null)
            Text('${pct!.toStringAsFixed(1)}%',
                style: AppTextStyles.caption
                    .copyWith(color: color.withValues(alpha: 0.7), fontSize: 10)),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton(
      {required this.icon, required this.onTap, required this.enabled});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: enabled
              ? context.vt.accentGreen.withValues(alpha: 0.15)
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
          size: 14,
          color: enabled ? context.vt.accentGreen : context.vt.textTertiary,
        ),
      ),
    );
  }
}
