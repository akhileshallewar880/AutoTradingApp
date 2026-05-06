import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PlanInfo {
  final String planId;
  final String name;
  final double priceMonthly;
  final int? analysesPerMonth;   // null = unlimited
  final int? executionsPerMonth;
  final List<String> features;

  const PlanInfo({
    required this.planId,
    required this.name,
    required this.priceMonthly,
    this.analysesPerMonth,
    this.executionsPerMonth,
    required this.features,
  });

  bool get isUnlimited => analysesPerMonth == null;

  factory PlanInfo.fromJson(Map<String, dynamic> j) {
    List<String> feats = [];
    final raw = j['features'];
    if (raw is String && raw.isNotEmpty) {
      try {
        feats = (raw.replaceAll('[', '').replaceAll(']', '')
            .split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .toList());
      } catch (_) {}
    }
    return PlanInfo(
      planId: j['plan_id'] as String? ?? 'free',
      name: j['name'] as String? ?? 'Free',
      priceMonthly: (j['price_monthly'] as num?)?.toDouble() ?? 0.0,
      analysesPerMonth: j['analyses_per_month'] as int?,
      executionsPerMonth: j['executions_per_month'] as int?,
      features: feats,
    );
  }
}

class UsageStatus {
  final PlanInfo plan;
  final int analysesCount;
  final int executionsCount;
  final int? analysesRemaining;
  final int? executionsRemaining;
  final bool isOverAnalysisLimit;
  final bool isOverExecutionLimit;
  final String period;
  final List<PlanInfo> allPlans;

  const UsageStatus({
    required this.plan,
    required this.analysesCount,
    required this.executionsCount,
    this.analysesRemaining,
    this.executionsRemaining,
    required this.isOverAnalysisLimit,
    required this.isOverExecutionLimit,
    required this.period,
    required this.allPlans,
  });

  factory UsageStatus.fromJson(Map<String, dynamic> j) {
    final planMap = j['plan'] as Map<String, dynamic>? ?? {};
    final limitsMap = j['limits'] as Map<String, dynamic>? ?? {};
    final usageMap = j['usage'] as Map<String, dynamic>? ?? {};

    // Merge limits into plan map for PlanInfo.fromJson
    final mergedPlan = {
      ...planMap,
      'analyses_per_month': limitsMap['analyses_per_month'],
      'executions_per_month': limitsMap['executions_per_month'],
    };

    return UsageStatus(
      plan: PlanInfo.fromJson(mergedPlan),
      analysesCount:    (usageMap['analyses_count'] as int?) ?? 0,
      executionsCount:  (usageMap['executions_count'] as int?) ?? 0,
      analysesRemaining:   j['analyses_remaining'] as int?,
      executionsRemaining: j['executions_remaining'] as int?,
      isOverAnalysisLimit:  (j['is_over_analysis_limit'] as bool?) ?? false,
      isOverExecutionLimit: (j['is_over_execution_limit'] as bool?) ?? false,
      period: usageMap['period'] as String? ?? '',
      allPlans: ((j['all_plans'] as List?) ?? [])
          .map((p) => PlanInfo.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  static UsageStatus get empty => UsageStatus(
    plan: const PlanInfo(
      planId: 'free', name: 'Free', priceMonthly: 0,
      analysesPerMonth: 10, executionsPerMonth: 5,
      features: ['10 analyses/month', '5 executions/month', 'Basic support'],
    ),
    analysesCount: 0, executionsCount: 0,
    analysesRemaining: 10, executionsRemaining: 5,
    isOverAnalysisLimit: false, isOverExecutionLimit: false,
    period: '', allPlans: [],
  );
}

class SubscriptionProvider with ChangeNotifier {
  UsageStatus _status = UsageStatus.empty;
  bool _isLoading = false;
  String? _error;

  UsageStatus get status => _status;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadStatus(String vtUserId) async {
    if (vtUserId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.getUsageStatus(vtUserId);
      _status = UsageStatus.fromJson(data);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> activate({
    required String vtUserId,
    required String planId,
    required String paymentProvider,
    required String paymentId,
    required double amountPaid,
  }) async {
    await ApiService.activateSubscription(
      vtUserId: vtUserId,
      planId: planId,
      paymentProvider: paymentProvider,
      paymentId: paymentId,
      amountPaid: amountPaid,
    );
  }

  void reset() {
    _status = UsageStatus.empty;
    _error = null;
    notifyListeners();
  }
}
