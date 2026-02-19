import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/analysis_provider.dart';
import '../models/analysis_model.dart';
import '../widgets/animated_completion_widget.dart';

class ExecutionTrackingScreen extends StatefulWidget {
  final String analysisId;
  const ExecutionTrackingScreen({super.key, required this.analysisId});

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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
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
        Timer.periodic(const Duration(seconds: 3), (_) => _loadStatus());
  }

  Future<void> _loadStatus() async {
    final authProvider = context.read<AuthProvider>();
    final analysisProvider = context.read<AnalysisProvider>();
    await analysisProvider.loadExecutionStatus(
        widget.analysisId, authProvider.user!.accessToken);

    final status = analysisProvider.executionStatus?.overallStatus;
    if (status == 'COMPLETED' || status == 'FAILED' || status == 'MARKET_CLOSED') {
      _pollTimer?.cancel();
      _pulseController.stop();
    }

    // Auto-scroll to bottom on new updates
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
        status?.overallStatus == 'FAILED';
    final isSuccess = status?.overallStatus == 'COMPLETED';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Execution'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: isDone,
      ),
      body: status == null
          ? _buildInitialLoading()
          : Column(
              children: [
                // Status header
                _buildStatusHeader(status, isDone, isSuccess),
                // Updates list
                Expanded(
                  child: status.updates.isEmpty
                      ? _buildEmptyUpdates()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: status.updates.length,
                          itemBuilder: (context, i) =>
                              _buildUpdateTile(status.updates[i], i),
                        ),
                ),
                // Completion widget
                if (isDone) _buildCompletionSection(status, isSuccess),
              ],
            ),
    );
  }

  Widget _buildInitialLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) => Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.receipt_long,
                    size: 40, color: Colors.green[700]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Placing orders…',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text('This may take a moment',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(
      ExecutionStatusModel status, bool isDone, bool isSuccess) {
    final color = isDone
        ? (isSuccess ? Colors.green[700]! : Colors.red[600]!)
        : Colors.orange[700]!;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (!isDone)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) => Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          else
            Icon(
              isSuccess ? Icons.check_circle : Icons.cancel,
              color: color,
              size: 18,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone
                      ? (isSuccess ? 'Execution Complete' : 'Execution Failed')
                      : 'Executing Orders…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${status.completedStocks} of ${status.totalStocks} orders processed'
                  '${status.failedStocks > 0 ? ' • ${status.failedStocks} failed' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                  backgroundColor: Colors.grey[200],
                  color: color,
                  strokeWidth: 4,
                ),
                Text(
                  '${status.completedStocks}/${status.totalStocks}',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateTile(ExecutionUpdateModel update, int index) {
    final isOrder = update.updateType == 'ORDER_PLACED';
    final isError = update.updateType == 'ERROR' ||
        update.updateType == 'FAILED';
    final isMarketClosed = update.updateType == 'MARKET_CLOSED';
    final isGtt = update.updateType == 'GTT_CREATED';

    Color tileColor;
    IconData icon;
    if (isMarketClosed) {
      tileColor = Colors.orange[700]!;
      icon = Icons.access_time_rounded;
    } else if (isError) {
      tileColor = Colors.red[700]!;
      icon = Icons.error_outline;
    } else if (isOrder) {
      tileColor = Colors.green[700]!;
      icon = Icons.check_circle_outline;
    } else if (isGtt) {
      tileColor = Colors.blue[700]!;
      icon = Icons.alarm_on;
    } else {
      tileColor = Colors.orange[700]!;
      icon = Icons.info_outline;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tileColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tileColor.withOpacity(0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: tileColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        update.stockSymbol,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: tileColor,
                        ),
                      ),
                      Text(
                        DateFormat('HH:mm:ss').format(update.timestamp),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    update.message,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  if (update.orderId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Order ID: ${update.orderId}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontFamily: 'monospace'),
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

  Widget _buildEmptyUpdates() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('Waiting for updates…',
              style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildCompletionSection(
      ExecutionStatusModel status, bool isSuccess) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCompletionWidget(
            isSuccess: isSuccess,
            title: isSuccess ? 'Orders Placed!' : 'Execution Failed',
            subtitle: isSuccess
                ? 'All trades have been executed. GTT orders set for targets & stop-losses.'
                : 'Some orders could not be placed. Check your Zerodha app.',
            stats: [
              CompletionStatItem('Completed', '${status.completedStocks}',
                  color: Colors.green[700]),
              CompletionStatItem('Failed', '${status.failedStocks}',
                  color: Colors.red[600]),
              CompletionStatItem('Total', '${status.totalStocks}'),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Back to Home',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
