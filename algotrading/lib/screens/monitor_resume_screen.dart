import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/api_config.dart';

/// Shown after a server restart when the user has an open trade.
/// Lets them re-attach AI monitoring by entering their Zerodha order details.
class MonitorResumeScreen extends StatefulWidget {
  const MonitorResumeScreen({super.key});

  @override
  State<MonitorResumeScreen> createState() => _MonitorResumeScreenState();
}

class _MonitorResumeScreenState extends State<MonitorResumeScreen> {
  final _formKey = GlobalKey<FormState>();

  final _symbolCtrl          = TextEditingController();
  final _quantityCtrl        = TextEditingController();
  final _fillPriceCtrl       = TextEditingController();
  final _slOrderCtrl         = TextEditingController();
  final _targetOrderCtrl     = TextEditingController();
  final _slTriggerCtrl       = TextEditingController();
  final _slLimitCtrl         = TextEditingController();
  final _targetPriceCtrl     = TextEditingController();
  final _instrumentTokenCtrl = TextEditingController();

  String _optionType = 'CE';
  bool _isLoading = false;
  String? _error;
  String? _success;

  final _purple = const Color(0xFF7C3AED);

  @override
  void dispose() {
    for (final c in [
      _symbolCtrl, _quantityCtrl, _fillPriceCtrl, _slOrderCtrl,
      _targetOrderCtrl, _slTriggerCtrl, _slLimitCtrl, _targetPriceCtrl,
      _instrumentTokenCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;

    setState(() { _isLoading = true; _error = null; _success = null; });

    // Use a random UUID as analysis_id for resumed sessions
    final analysisId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final tokenText = _instrumentTokenCtrl.text.trim();
      final body = jsonEncode({
        'symbol':            _symbolCtrl.text.trim().toUpperCase(),
        'option_type':       _optionType,
        'quantity':          int.parse(_quantityCtrl.text.trim()),
        'fill_price':        double.parse(_fillPriceCtrl.text.trim()),
        'sl_order_id':       _slOrderCtrl.text.trim(),
        'target_order_id':   _targetOrderCtrl.text.trim(),
        'sl_trigger':        double.parse(_slTriggerCtrl.text.trim()),
        'sl_limit':          double.parse(_slLimitCtrl.text.trim()),
        'target_price':      double.parse(_targetPriceCtrl.text.trim()),
        'instrument_token':  tokenText.isNotEmpty ? int.tryParse(tokenText) ?? 0 : 0,
        'api_key':           auth.user!.apiKey,
        'access_token':      auth.user!.accessToken,
      });

      final resp = await http.post(
        Uri.parse(ApiConfig.optionsMonitorResumeUrl(analysisId)),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _success =
            data['message'] ?? 'Monitoring restarted successfully.');
      } else {
        String msg = 'Resume failed';
        try { msg = jsonDecode(resp.body)['detail'] ?? msg; } catch (_) {}
        setState(() => _error = msg);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resume AI Monitoring'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Info banner ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[800], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Server restarted. Your SL and target orders are still '
                        'active on Zerodha. Enter the details from your Zerodha '
                        'order book to re-attach AI monitoring and trailing SL.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Symbol + option type ─────────────────────────────────
              _section('Position Details', Icons.candlestick_chart_outlined),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _field(
                      controller: _symbolCtrl,
                      label: 'Trading Symbol',
                      hint: 'NIFTY2640722200CE',
                      caps: true,
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Type',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _optionType,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                          ),
                          items: ['CE', 'PE']
                              .map((t) => DropdownMenuItem(
                                  value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _optionType = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _quantityCtrl,
                      label: 'Quantity (units)',
                      hint: '65',
                      numeric: true,
                      validator: (v) =>
                          int.tryParse(v ?? '') == null ? 'Integer' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      controller: _fillPriceCtrl,
                      label: 'Fill Price ₹',
                      hint: '319.80',
                      numeric: true,
                      validator: (v) =>
                          double.tryParse(v ?? '') == null ? 'Number' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Order IDs ────────────────────────────────────────────
              _section('Zerodha Order IDs', Icons.receipt_long_outlined),
              _field(
                controller: _slOrderCtrl,
                label: 'SL Order ID',
                hint: '260402001234567',
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _targetOrderCtrl,
                label: 'Target Order ID',
                hint: '260402001234568',
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // ── Price levels ─────────────────────────────────────────
              _section('Price Levels', Icons.price_change_outlined),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _slTriggerCtrl,
                      label: 'SL Trigger ₹',
                      hint: '229.70',
                      numeric: true,
                      validator: (v) =>
                          double.tryParse(v ?? '') == null ? 'Number' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      controller: _slLimitCtrl,
                      label: 'SL Limit ₹',
                      hint: '225.10',
                      numeric: true,
                      validator: (v) =>
                          double.tryParse(v ?? '') == null ? 'Number' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(
                controller: _targetPriceCtrl,
                label: 'Target Premium ₹',
                hint: '499.60',
                numeric: true,
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Number' : null,
              ),
              const SizedBox(height: 20),

              // ── WebSocket token (optional) ────────────────────────────
              _section('WebSocket (optional)', Icons.wifi_outlined),
              _field(
                controller: _instrumentTokenCtrl,
                label: 'Instrument Token',
                hint: '10425858  (from Zerodha instruments list)',
                numeric: true,
                // Optional — 0 means fall back to REST polling
              ),
              const SizedBox(height: 28),

              // ── Submit ───────────────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _submit,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_circle_outline),
                label: Text(
                  _isLoading ? 'Restarting…' : 'Resume AI Monitoring',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),

              // ── Feedback ─────────────────────────────────────────────
              if (_success != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.green[700], size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_success!,
                            style: TextStyle(color: Colors.green[800])),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red[700], size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: TextStyle(color: Colors.red[700])),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: _purple, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool numeric = false,
    bool caps = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _purple),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      validator: validator,
    );
  }
}
