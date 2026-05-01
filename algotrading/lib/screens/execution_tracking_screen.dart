import '../theme/vt_color_scheme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/analysis_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/animated_completion_widget.dart';
import '../widgets/vt_button.dart';
import '../services/notification_service.dart';

class ExecutionTrackingScreen extends StatefulWidget {
  final String analysisId;
  ExecutionTrackingScreen({super.key, required this.analysisId});

  @override
  State<ExecutionTrackingScreen> createState() =>
      _ExecutionTrackingScreenState();
}

class _ExecutionTrackingScreenState extends State<ExecutionTrackingScreen>
    with SingleTickerProviderStateMixin {
  Timer? _pollTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final _scrollController = ScrollController();

  int _notifiedUpdateCount = 0;
  bool _completionNotified = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _loadStatus();
    _pollTimer =
        Timer.periodic(Duration(seconds: 3), (_) => _loadStatus());
  }

  Future<void> _loadStatus() async {
    final authProvider = context.read<AuthProvider>();
    final analysisProvider = context.read<AnalysisProvider>();
    await analysisProvider.loadExecutionStatus(
        widget.analysisId, authProvider.user!.accessToken);

    final execStatus = analysisProvider.executionStatus;
    final overallStatus = execStatus?.overallStatus;

    if (overallStatus == 'COMPLETED' ||
        overallStatus == 'FAILED' ||
        overallStatus == 'MARKET_CLOSED' ||
        overallStatus == 'AMO_PLACED') {
      _pollTimer?.cancel();
      _pulseController.stop();
    }

    if (execStatus != null) {
      final updates = execStatus.updates;
      if (updates.length > _notifiedUpdateCount) {
        final newUpdates = updates.sublist(_notifiedUpdateCount);
        for (final update in newUpdates) {
          await NotificationService.instance.showOrderUpdate(
            stockSymbol: update.stockSymbol,
            message: update.message,
            updateType: update.updateType,
          );
        }
        _notifiedUpdateCount = updates.length;
      }

      if (!_completionNotified &&
          (overallStatus == 'COMPLETED' ||
              overallStatus == 'FAILED' ||
              overallStatus == 'GTT_FAILED')) {
        _completionNotified = true;
        await NotificationService.instance.showExecutionComplete(
          completedCount: execStatus.completedStocks,
          failedCount: execStatus.failedStocks,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AnalysisProvider>().executionStatus;
    final isDone = status?.overallStatus == 'COMPLETED' ||
        status?.overallStatus == 'FAILED' ||
        status?.overallStatus == 'GTT_FAILED';
    final isSuccess = status?.overallStatus == 'COMPLETED' ||
        status?.overallStatus == 'GTT_FAILED';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Order Execution', style: AppTextStyles.h2),
        automaticallyImplyLeading: isDone,
      ),
      body: status == null
          ? _buildInitialLoading()
          : Column(
              children: [
                _buildStatusCard(status, isDone, isSuccess),
                Expanded(
                  child: status.updates.isEmpty
                      ? _buildEmptyUpdates()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(
                              Sp.base, Sp.sm, Sp.base, Sp.base),
                          itemCount: status.updates.length,
                          itemBuilder: (context, i) =>
                              _buildUpdateTile(status.updates[i], i),
                        ),
                ),
                if (isDone) _buildCompletionSection(status, isSuccess),
              ],
            ),
    );
  }

  // ── Initial loading ────────────────────────────────────────────────────────

  Widget _buildInitialLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.vt.accentPurpleDim,
                boxShadow: [
                  BoxShadow(
                    color: context.vt.accentPurple
                        .withValues(alpha: _pulseAnim.value * 0.35),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(Icons.receipt_long_rounded,
                  size: 42, color: context.vt.accentPurple),
            ),
          ),
          const SizedBox(height: Sp.xl),
          Text('Placing orders…', style: AppTextStyles.bodyLarge),
          const SizedBox(height: Sp.xs),
          Text('This may take a moment', style: AppTextStyles.caption),
        ],
      ),
    );
  }

  // ── Status card ────────────────────────────────────────────────────────────

  Widget _buildStatusCard(
      ExecutionStatusModel status, bool isDone, bool isSuccess) {
    final color = isDone
        ? (isSuccess ? context.vt.accentGreen : context.vt.danger)
        : context.vt.accentPurple;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) => Container(
        margin: const EdgeInsets.all(Sp.base),
        padding: EdgeInsets.all(Sp.base),
        decoration: BoxDecoration(
          color: context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: isDone
              ? null
              : [
                  BoxShadow(
                    color: color
                        .withValues(alpha: _pulseAnim.value * 0.2),
                    blurRadius: 16,
                    spreadRadius: -2,
                  ),
                ],
        ),
        child: child,
      ),
      child: Row(
        children: [
          // Status icon / pulsing dot
          if (!isDone)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) => Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.vt.accentPurple
                      .withValues(alpha: _pulseAnim.value),
                  boxShadow: [
                    BoxShadow(
                      color: context.vt.accentPurple
                          .withValues(alpha: _pulseAnim.value * 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            )
          else
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: color,
              size: 18,
            ),
          SizedBox(width: Sp.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone
                      ? (isSuccess ? 'Execution Complete' : 'Execution Failed')
                      : 'AI Executing…',
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.completedStocks} of ${status.totalStocks} processed'
                  '${status.failedStocks > 0 ? '  ·  ${status.failedStocks} failed' : ''}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),

          // Progress ring
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: status.totalStocks > 0
                      ? status.completedStocks / status.totalStocks
                      : 0,
                  backgroundColor: context.vt.surface3,
                  color: color,
                  strokeWidth: 4,
                ),
                Text(
                  '${status.completedStocks}/${status.totalStocks}',
                  style: AppTextStyles.caption.copyWith(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Update tile ────────────────────────────────────────────────────────────

  Widget _buildUpdateTile(ExecutionUpdateModel update, int index) {
    final isOrder = update.updateType == 'ORDER_PLACED';
    final isError =
        update.updateType == 'ERROR' || update.updateType == 'FAILED';
    final isMarketClosed = update.updateType == 'MARKET_CLOSED';
    final isAmo = update.updateType == 'AMO_PLACED';
    final isGtt = update.updateType == 'GTT_CREATED' ||
        update.updateType == 'GTT_PLACED';
    final isSquaredOff = update.updateType == 'SQUAREDOFF';
    final isSquareOffFailed = update.updateType == 'SQUAREOFF_FAILED';
    final isGttFailed = update.updateType == 'GTT_FAILED';

    Color tileColor;
    IconData icon;
    if (isSquareOffFailed || isGttFailed) {
      tileColor = context.vt.danger;
      icon = Icons.warning_amber_rounded;
    } else if (isAmo) {
      tileColor = context.vt.accentPurple;
      icon = Icons.schedule_rounded;
    } else if (isMarketClosed) {
      tileColor = context.vt.warning;
      icon = Icons.access_time_rounded;
    } else if (isError) {
      tileColor = context.vt.danger;
      icon = Icons.error_outline_rounded;
    } else if (isSquaredOff) {
      tileColor = context.vt.accentPurple;
      icon = Icons.swap_horiz_rounded;
    } else if (isOrder) {
      tileColor = context.vt.accentGreen;
      icon = Icons.check_circle_outline_rounded;
    } else if (isGtt) {
      tileColor = Color(0xFF60A5FA);
      icon = Icons.alarm_on_rounded;
    } else {
      tileColor = context.vt.warning;
      icon = Icons.info_outline_rounded;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 250 + index * 50),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(16 * (1 - value), 0),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: Sp.sm),
        padding: EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.md),
          border:
              Border.all(color: tileColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon box
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tileColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Icon(icon, color: tileColor, size: 16),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        update.stockSymbol,
                        style: AppTextStyles.body.copyWith(
                            color: tileColor,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        DateFormat('HH:mm:ss').format(update.timestamp),
                        style: AppTextStyles.caption
                            .copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    update.message,
                    style: AppTextStyles.caption
                        .copyWith(color: context.vt.textSecondary),
                  ),
                  if (update.orderId != null) ...[
                    SizedBox(height: 3),
                    Text(
                      'ID: ${update.orderId}',
                      style: AppTextStyles.monoSm.copyWith(
                          color: context.vt.textTertiary, fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty updates ──────────────────────────────────────────────────────────

  Widget _buildEmptyUpdates() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 40, color: context.vt.textTertiary),
          const SizedBox(height: Sp.md),
          Text('Waiting for updates…',
              style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }

  // ── Completion section ─────────────────────────────────────────────────────

  String _completionSubtitle(ExecutionStatusModel status) {
    final hasGttFailed =
        status.updates.any((u) => u.updateType == 'GTT_FAILED');
    final hasSquaredOff =
        status.updates.any((u) => u.updateType == 'SQUAREDOFF');
    final hasSquareOffFailed =
        status.updates.any((u) => u.updateType == 'SQUAREOFF_FAILED');
    final hasSlmPlaced = status.updates.any((u) =>
        u.updateType == 'GTT_PLACED' && u.message.contains('SL-M'));
    final allFilled =
        status.completedStocks > 0 && status.failedStocks == 0;

    if (hasSquareOffFailed) {
      return '⚠ GTT failed and auto square-off also failed. '
          'Exit your open position manually in Zerodha NOW.';
    }
    if (hasSquaredOff) {
      return 'GTT failed — position was automatically squared off. No open position.';
    }
    if (allFilled && hasGttFailed) {
      return 'Orders filled but stop-loss could not be set. '
          'Set SL & target manually in your Zerodha app.';
    }
    if (allFilled && hasSlmPlaced) {
      return 'Trades executed with SL-M protection. '
          'Monitor target manually and cancel SL-M if target is hit first.';
    }
    if (allFilled) {
      return 'All trades executed with GTT stop-loss & target orders.';
    }
    if (status.completedStocks > 0 && status.failedStocks > 0) {
      return '${status.completedStocks} order(s) executed, '
          '${status.failedStocks} failed. Check Zerodha app.';
    }
    return 'Some orders could not be placed. Check your Zerodha app.';
  }

  Widget _buildCompletionSection(
      ExecutionStatusModel status, bool isSuccess) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
          Sp.xl, Sp.xl, Sp.xl, Sp.xl + bottomPadding),
      decoration: BoxDecoration(
        color: context.vt.surface1,
        border: Border(top: BorderSide(color: context.vt.divider)),
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Rad.xl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCompletionWidget(
            isSuccess: isSuccess,
            title: isSuccess ? 'Orders Placed!' : 'Execution Failed',
            subtitle: _completionSubtitle(status),
            stats: [
              CompletionStatItem('Completed', '${status.completedStocks}',
                  color: context.vt.accentGreen),
              CompletionStatItem('Failed', '${status.failedStocks}',
                  color: context.vt.danger),
              CompletionStatItem('Total', '${status.totalStocks}',
                  color: context.vt.textSecondary),
            ],
          ),
          const SizedBox(height: Sp.xl),
          VtButton(
            label: 'Back to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
