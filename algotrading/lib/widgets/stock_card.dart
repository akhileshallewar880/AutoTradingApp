import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/analysis_model.dart';
import '../providers/analysis_provider.dart';

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

class _StockCardState extends State<StockCard> {
  late TextEditingController _qtyController;
  bool _isEditingQty = false;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: widget.stock.quantity.toString());
  }

  @override
  void didUpdateWidget(StockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep controller in sync if provider updates the stock externally
    if (!_isEditingQty &&
        oldWidget.stock.quantity != widget.stock.quantity) {
      _qtyController.text = widget.stock.quantity.toString();
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _increment() {
    final provider = context.read<AnalysisProvider>();
    provider.updateStockQuantity(widget.stockIndex, widget.stock.quantity + 1);
  }

  void _decrement() {
    if (widget.stock.quantity <= 1) return;
    final provider = context.read<AnalysisProvider>();
    provider.updateStockQuantity(widget.stockIndex, widget.stock.quantity - 1);
  }

  void _commitTextEdit() {
    final parsed = int.tryParse(_qtyController.text);
    if (parsed != null && parsed >= 1) {
      context.read<AnalysisProvider>().updateStockQuantity(widget.stockIndex, parsed);
    } else {
      // Revert to current value if invalid
      _qtyController.text = widget.stock.quantity.toString();
    }
    setState(() => _isEditingQty = false);
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    return Opacity(
      opacity: widget.isSelected ? 1.0 : 0.5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: widget.isSelected,
                  onChanged: (val) {
                    widget.onSelectionChanged?.call(val ?? false);
                  },
                  activeColor: Colors.green[700],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.stock.action == 'BUY' ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.stock.action,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: widget.stock.action == 'BUY' ? Colors.green[700] : Colors.red[700],
                  ),
                ),
              ),
            ],
          ),
          title: Text(
            widget.stock.stockSymbol,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.stock.companyName != null)
                Text(
                  widget.stock.companyName!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              if (widget.stock.daysToTarget != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule,
                                size: 11, color: Colors.blue[700]),
                            const SizedBox(width: 3),
                            Text(
                              '~${widget.stock.daysToTarget}d to target',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[700],
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
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currencyFormat.format(widget.stock.entryPrice),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Qty: ${widget.stock.quantity}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Entry Price', currencyFormat.format(widget.stock.entryPrice)),
                  _buildDetailRow('Stop Loss', currencyFormat.format(widget.stock.stopLoss)),
                  _buildDetailRow('Target', currencyFormat.format(widget.stock.targetPrice)),
                  // ── Editable Quantity Row ──────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Quantity',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Decrement button
                            _QtyButton(
                              icon: Icons.remove,
                              onTap: _decrement,
                              enabled: widget.stock.quantity > 1,
                            ),
                            const SizedBox(width: 6),
                            // Tappable / editable quantity value
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isEditingQty = true;
                                  _qtyController.text = widget.stock.quantity.toString();
                                  _qtyController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: _qtyController.text.length,
                                  );
                                });
                              },
                              child: _isEditingQty
                                  ? SizedBox(
                                      width: 60,
                                      height: 32,
                                      child: TextField(
                                        controller: _qtyController,
                                        autofocus: true,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                        ],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 6,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: BorderSide(
                                              color: Colors.green[700]!,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            borderSide: BorderSide(
                                              color: Colors.green[700]!,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        onSubmitted: (_) => _commitTextEdit(),
                                        onTapOutside: (_) => _commitTextEdit(),
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            widget.stock.quantity.toString(),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit,
                                            size: 12,
                                            color: Colors.grey[500],
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 6),
                            // Increment button
                            _QtyButton(
                              icon: Icons.add,
                              onTap: _increment,
                              enabled: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ─────────────────────────────────────────────────────────
                  const Divider(height: 24),
                  _buildDetailRow(
                    'Potential Profit',
                    currencyFormat.format(widget.stock.potentialProfit),
                    valueColor: Colors.green,
                  ),
                  _buildDetailRow(
                    'Potential Loss',
                    currencyFormat.format(widget.stock.potentialLoss),
                    valueColor: Colors.red,
                  ),
                  _buildDetailRow(
                    'Risk:Reward',
                    '1:${widget.stock.riskRewardRatio.toStringAsFixed(2)}',
                  ),
                  _buildDetailRow(
                    'Confidence',
                    '${(widget.stock.confidenceScore * 100).toStringAsFixed(0)}%',
                  ),
                  const Divider(height: 24),
                  const Text(
                    'AI Reasoning:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.stock.aiReasoning,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular +/− button used for quantity stepping.
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.green[700] : Colors.grey[300],
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.white : Colors.grey[500],
        ),
      ),
    );
  }
}
