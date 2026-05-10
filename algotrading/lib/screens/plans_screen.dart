import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../theme/vt_color_scheme.dart';
import '../widgets/vt_tour.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  // Tour keys
  final _tourUsageKey = GlobalKey();
  final _tourPromoKey = GlobalKey();
  final _tourPlansKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _startTour();
    });
  }

  void _load() {
    final auth = context.read<AuthProvider>();
    final vtId = auth.vtUserId ?? '';
    final vtToken = auth.vtAccessToken ?? '';
    context.read<SubscriptionProvider>().loadStatus(vtId, vtAccessToken: vtToken);
  }

  Future<void> _startTour() async {
    if (!mounted) return;
    await VtTour.showIfNew(
      context: context,
      screenId: 'plans',
      steps: [
        VtTourStep(
          targetKey: _tourUsageKey,
          title: 'Your Current Plan & Usage',
          body: 'See which plan you\'re on, how many AI analyses you\'ve used this month, and how many executions remain. The usage resets at the start of every month.',
        ),
        VtTourStep(
          targetKey: _tourPromoKey,
          title: 'Beta Launch — Everything is FREE!',
          body: 'During our beta, all paid plans are activated at ₹0/month. Upgrade to Pro or Elite for free to unlock more monthly analyses and executions.',
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        VtTourStep(
          targetKey: _tourPlansKey,
          title: 'Choose the Right Plan for You',
          body: 'Free: 10 analyses/month.\nPro: 30 analyses + 50 executions.\nElite: Unlimited analyses & executions.\n\nAll plans are currently 100% FREE — tap any plan card to activate it instantly!',
          padding: EdgeInsets.symmetric(vertical: 6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();
    final vt = context.vt;

    return Scaffold(
      appBar: AppBar(
        title: Text('Plans & Usage', style: AppTextStyles.h2),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: sub.isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: EdgeInsets.all(Sp.base),
                children: [
                  KeyedSubtree(
                    key: _tourUsageKey,
                    child: _UsageSummaryCard(status: sub.status),
                  ),
                  SizedBox(height: Sp.xl),

                  // ── Limited-time promo banner ───────────────────────────
                  Container(
                    key: _tourPromoKey,
                    padding: EdgeInsets.symmetric(
                        horizontal: Sp.base, vertical: Sp.md),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          vt.accentGreen.withValues(alpha: 0.15),
                          vt.accentPurple.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(Rad.lg),
                      border: Border.all(
                          color: vt.accentGreen.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Text('🎉', style: TextStyle(fontSize: 22.sp)),
                        SizedBox(width: Sp.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Early Access — 100% OFF',
                                  style: AppTextStyles.body.copyWith(
                                      color: vt.accentGreen,
                                      fontWeight: FontWeight.w800)),
                              Text(
                                'All paid plans are free during our beta launch. Upgrade now!',
                                style: AppTextStyles.caption
                                    .copyWith(color: vt.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: Sp.base),

                  Text('Available Plans', key: _tourPlansKey, style: AppTextStyles.h3),
                  SizedBox(height: Sp.sm),

                  if (sub.status.allPlans.isEmpty) ...[
                    _PlanCard(
                      plan: PlanInfo(
                        planId: 'free',
                        name: 'Free',
                        priceMonthly: 0,
                        analysesPerMonth: 10,
                        executionsPerMonth: 5,
                        features: [
                          '10 analyses/month',
                          '5 executions/month',
                          'Basic support',
                        ],
                      ),
                      isCurrent: true,
                    ),
                    _PlanCard(
                      plan: PlanInfo(
                        planId: 'pro',
                        name: 'Pro',
                        priceMonthly: 99,
                        analysesPerMonth: 30,
                        executionsPerMonth: 50,
                        features: [
                          '30 analyses/month',
                          '50 executions/month',
                          'Priority support',
                          'Advanced indicators',
                        ],
                      ),
                      isCurrent: false,
                    ),
                    _PlanCard(
                      plan: PlanInfo(
                        planId: 'elite',
                        name: 'Elite',
                        priceMonthly: 499,
                        features: [
                          'Unlimited analyses',
                          'Unlimited executions',
                          'Dedicated support',
                          'All features',
                        ],
                      ),
                      isCurrent: false,
                    ),
                  ] else
                    ...sub.status.allPlans.map((plan) => _PlanCard(
                          plan: plan,
                          isCurrent: plan.planId == sub.status.plan.planId,
                        )),

                  SizedBox(height: Sp.xl),
                  const _PaymentNote(),
                  SizedBox(height: Sp.xxl),
                ],
              ),
            ),
    );
  }
}

// ── Usage summary ─────────────────────────────────────────────────────────────

class _UsageSummaryCard extends StatelessWidget {
  final UsageStatus status;
  const _UsageSummaryCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;

    return Container(
      padding: EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: vt.accentGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bar_chart_rounded, color: vt.accentGreen, size: 22),
            SizedBox(width: Sp.sm),
            Text('This Month — ${status.period}',
                style: AppTextStyles.caption.copyWith(
                    color: vt.textSecondary)),
            Spacer(),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: 4),
              decoration: BoxDecoration(
                color: vt.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Rad.pill),
              ),
              child: Text(status.plan.name,
                  style: AppTextStyles.caption.copyWith(
                      color: vt.accentGreen,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          SizedBox(height: Sp.lg),
          Row(children: [
            Expanded(
              child: _UsageMeter(
                label: 'Analyses',
                used: status.analysesCount,
                limit: status.plan.analysesPerMonth,
                isOver: status.isOverAnalysisLimit,
              ),
            ),
            SizedBox(width: Sp.base),
            Expanded(
              child: _UsageMeter(
                label: 'Executions',
                used: status.executionsCount,
                limit: status.plan.executionsPerMonth,
                isOver: status.isOverExecutionLimit,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  final String label;
  final int used;
  final int? limit;
  final bool isOver;

  const _UsageMeter({
    required this.label,
    required this.used,
    this.limit,
    required this.isOver,
  });

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final isUnlimited = limit == null;
    final fraction = isUnlimited ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    final barColor = isOver
        ? Colors.redAccent
        : fraction > 0.75
            ? Colors.orangeAccent
            : vt.accentGreen;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: AppTextStyles.caption.copyWith(
                color: vt.textSecondary)),
            Spacer(),
            Text(
              isUnlimited ? '$used / ∞' : '$used / $limit',
              style: AppTextStyles.caption.copyWith(
                  color: isOver ? Colors.redAccent : vt.textPrimary,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isUnlimited ? 0.1 : fraction,
              backgroundColor: vt.divider,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6,
            ),
          ),
        ]);
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final PlanInfo plan;
  final bool isCurrent;
  const _PlanCard({required this.plan, required this.isCurrent});

  Color _accentFor(BuildContext context) {
    final vt = context.vt;
    if (plan.planId == 'elite') return Color(0xFFFFD700);
    if (plan.planId == 'pro') return vt.accentGreen;
    return vt.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final accentColor = _accentFor(context);
    final isPaid = plan.planId != 'free';

    return Container(
      margin: EdgeInsets.only(bottom: Sp.sm),
      padding: EdgeInsets.all(Sp.base),
      decoration: BoxDecoration(
        color: vt.surface1,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(
          color: isCurrent
              ? accentColor
              : accentColor.withValues(alpha: 0.25),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(children: [
            Text(plan.name,
                style: AppTextStyles.h3.copyWith(color: accentColor)),
            Spacer(),
            if (isCurrent)
              _badge('Current', accentColor)
            else if (isPaid) ...[
              // Strike-through original price
              Text(
                '₹${plan.priceMonthly.toStringAsFixed(0)}',
                style: AppTextStyles.caption.copyWith(
                  color: vt.textTertiary,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              SizedBox(width: 6),
              // Effective price: 100% off = ₹0
              Text(
                '₹0/mo',
                style: AppTextStyles.body.copyWith(
                    color: accentColor, fontWeight: FontWeight.w800),
              ),
            ],
          ]),

          // ── Discount badge for paid plans ────────────────────────────
          if (isPaid && !isCurrent) ...[
            SizedBox(height: 6),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: 2),
              decoration: BoxDecoration(
                color: vt.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Rad.sm),
                border: Border.all(
                    color: vt.accentGreen.withValues(alpha: 0.3)),
              ),
              child: Text(
                '🎉 100% OFF — Beta launch offer',
                style: AppTextStyles.label.copyWith(
                    color: vt.accentGreen,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],

          SizedBox(height: Sp.sm),

          // ── Features ────────────────────────────────────────────────
          ...plan.features.map((f) => Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.check_circle_outline,
                      size: 14,
                      color: accentColor.withValues(alpha: 0.8)),
                  SizedBox(width: 6),
                  Text(f,
                      style: AppTextStyles.caption.copyWith(
                          color: vt.textSecondary)),
                ]),
              )),

          // ── CTA ─────────────────────────────────────────────────────
          if (!isCurrent && isPaid) ...[
            SizedBox(height: Sp.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Rad.md)),
                ),
                onPressed: () => _showActivateSheet(context),
                child: Text('Claim Free ${plan.name} Access'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(
              color: color, fontWeight: FontWeight.w600)),
    );
  }

  void _showActivateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivateSheet(plan: plan),
    );
  }
}

// ── Activate / upgrade bottom sheet ──────────────────────────────────────────

class _ActivateSheet extends StatelessWidget {
  final PlanInfo plan;
  const _ActivateSheet({required this.plan});

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    final isElite = plan.planId == 'elite';
    final accentColor =
        isElite ? Color(0xFFFFD700) : vt.accentGreen;

    return Container(
      decoration: BoxDecoration(
        color: vt.surface0,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: vt.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: Sp.base),

          // Title row
          Row(children: [
            Text('Activate ${plan.name}',
                style: AppTextStyles.h2.copyWith(color: accentColor)),
            Spacer(),
            _Chip('100% OFF', accentColor),
          ]),
          SizedBox(height: 4),
          Text(
            'Beta launch — limited time free access.',
            style: AppTextStyles.caption.copyWith(color: vt.textSecondary),
          ),
          SizedBox(height: Sp.base),

          // Price row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('₹0',
                  style: AppTextStyles.h1.copyWith(
                      color: accentColor, fontWeight: FontWeight.w900)),
              SizedBox(width: 6),
              Text('/ month',
                  style: AppTextStyles.caption.copyWith(
                      color: vt.textSecondary)),
              SizedBox(width: 12),
              Text(
                '(was ₹${plan.priceMonthly.toStringAsFixed(0)}/mo)',
                style: AppTextStyles.caption.copyWith(
                  color: vt.textTertiary,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
          SizedBox(height: Sp.base),

          // Features
          ...plan.features.map((f) => Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.check_circle,
                      size: 16, color: accentColor),
                  SizedBox(width: 8),
                  Text(f,
                      style: AppTextStyles.body.copyWith(
                          color: vt.textPrimary)),
                ]),
              )),

          SizedBox(height: Sp.xl),

          // CTA button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor:
                    isElite ? Colors.black : Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Rad.md)),
              ),
              onPressed: () => _activate(context),
              child: Text('Activate ${plan.name} for Free',
                  style: TextStyle(
                      fontSize: 16.sp, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activate(BuildContext context) async {
    Navigator.pop(context); // close sheet
    final sub = context.read<SubscriptionProvider>();
    final auth = context.read<AuthProvider>();
    final vtId = auth.vtUserId ?? '';
    final vtToken = auth.vtAccessToken ?? '';
    if (vtId.isEmpty) return;

    // Activate with ₹0 payment (100% discount)
    try {
      await sub.activate(
        vtUserId: vtId,
        planId: plan.planId,
        paymentProvider: 'promo',
        paymentId: 'beta_100pct_off_${DateTime.now().millisecondsSinceEpoch}',
        amountPaid: 0.0,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🎉 ${plan.name} activated successfully!'),
          backgroundColor: Colors.green,
        ));
        sub.loadStatus(vtId, vtAccessToken: vtToken);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Activation failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: AppTextStyles.label.copyWith(
              color: color, fontWeight: FontWeight.w800, fontSize: 11.sp)),
    );
  }
}

// ── Footer note ───────────────────────────────────────────────────────────────

class _PaymentNote extends StatelessWidget {
  const _PaymentNote();

  @override
  Widget build(BuildContext context) {
    final vt = context.vt;
    return Container(
      padding: EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: vt.surface1,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: vt.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: vt.textTertiary),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'During our beta, all plans are available at 100% discount. '
            'Paid billing will start after the official launch.',
            style: AppTextStyles.caption.copyWith(color: vt.textSecondary),
          ),
        ),
      ]),
    );
  }
}
