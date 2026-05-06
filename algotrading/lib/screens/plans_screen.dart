import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart';
import '../theme/vt_color_scheme.dart';
import '../theme/app_text_styles.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final vtId = context.read<AuthProvider>().vtUserId ?? '';
    context.read<SubscriptionProvider>().loadStatus(vtId);
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans & Usage'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: sub.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _UsageSummaryCard(status: sub.status),
                  const SizedBox(height: 24),
                  Text('Available Plans',
                      style: AppTextStyles.h3
                          .copyWith(color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 12),
                  if (sub.status.allPlans.isEmpty)
                    ...[
                      _PlanCard(
                        plan: const PlanInfo(
                          planId: 'free', name: 'Free', priceMonthly: 0,
                          analysesPerMonth: 10, executionsPerMonth: 5,
                          features: ['10 analyses/month', '5 executions/month', 'Basic support'],
                        ),
                        isCurrent: true,
                      ),
                      _PlanCard(
                        plan: const PlanInfo(
                          planId: 'pro', name: 'Pro', priceMonthly: 499,
                          analysesPerMonth: 30, executionsPerMonth: 50,
                          features: ['30 analyses/month', '50 executions/month',
                            'Priority support', 'Advanced indicators'],
                        ),
                        isCurrent: false,
                      ),
                      _PlanCard(
                        plan: const PlanInfo(
                          planId: 'elite', name: 'Elite', priceMonthly: 999,
                          features: ['Unlimited analyses', 'Unlimited executions',
                            'Dedicated support', 'All features'],
                        ),
                        isCurrent: false,
                      ),
                    ]
                  else
                    ...sub.status.allPlans.map((plan) => _PlanCard(
                          plan: plan,
                          isCurrent: plan.planId == sub.status.plan.planId,
                        )),
                  const SizedBox(height: 24),
                  const _PaymentNote(),
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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: context.vt.accentGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bar_chart_rounded,
                color: context.vt.accentGreen, size: 22),
            const SizedBox(width: 8),
            Text('This Month — ${status.period}',
                style: AppTextStyles.caption.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.6))),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.vt.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(status.plan.name,
                  style: AppTextStyles.caption.copyWith(
                      color: context.vt.accentGreen,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: _UsageMeter(
                label: 'Analyses',
                used: status.analysesCount,
                limit: status.plan.analysesPerMonth,
                isOver: status.isOverAnalysisLimit,
              ),
            ),
            const SizedBox(width: 16),
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
    final theme = Theme.of(context);
    final isUnlimited = limit == null;
    final fraction =
        isUnlimited ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    final barColor = isOver
        ? Colors.redAccent
        : fraction > 0.75
            ? Colors.orangeAccent
            : context.vt.accentGreen;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: AppTextStyles.caption.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.7))),
            const Spacer(),
            Text(
              isUnlimited ? '$used / ∞' : '$used / $limit',
              style: AppTextStyles.caption.copyWith(
                  color: isOver
                      ? Colors.redAccent
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isUnlimited ? 0.1 : fraction,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.08),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isElite = plan.planId == 'elite';
    final accentColor = isElite
        ? const Color(0xFFFFD700)
        : plan.planId == 'pro'
            ? context.vt.accentGreen
            : theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
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
            Row(children: [
              Text(plan.name,
                  style: AppTextStyles.h3.copyWith(color: accentColor)),
              const Spacer(),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Current',
                      style: AppTextStyles.caption.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w600)),
                ),
              if (!isCurrent && plan.planId != 'free')
                Text(
                  '₹${plan.priceMonthly.toStringAsFixed(0)}/mo',
                  style: AppTextStyles.body.copyWith(
                      color: accentColor, fontWeight: FontWeight.w700),
                ),
            ]),
            const SizedBox(height: 10),
            ...plan.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 14,
                        color: accentColor.withValues(alpha: 0.8)),
                    const SizedBox(width: 6),
                    Text(f,
                        style: AppTextStyles.caption.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.8))),
                  ]),
                )),
            if (!isCurrent && plan.planId != 'free') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showUpgradeDialog(context, plan),
                  child: Text('Upgrade to ${plan.name}'),
                ),
              ),
            ],
          ]),
    );
  }

  void _showUpgradeDialog(BuildContext context, PlanInfo plan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Upgrade to ${plan.name}'),
        content: Text(
          'Payment integration coming soon.\n\n'
          'Plan: ${plan.name}\n'
          'Price: ₹${plan.priceMonthly.toStringAsFixed(0)}/month\n\n'
          'You will be notified when Razorpay integration is live.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Footer note ───────────────────────────────────────────────────────────────

class _PaymentNote extends StatelessWidget {
  const _PaymentNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline,
            size: 16,
            color:
                theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Razorpay payment integration coming soon. '
            'Upgrade options will be enabled in the next release.',
            style: AppTextStyles.caption.copyWith(
                color: theme.colorScheme.onSurface
                    .withValues(alpha: 0.6)),
          ),
        ),
      ]),
    );
  }
}
