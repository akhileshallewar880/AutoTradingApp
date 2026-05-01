import '../theme/vt_color_scheme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
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
      ).timeout(Duration(seconds: 20));

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Resume AI Monitoring', style: AppTextStyles.h2),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: context.vt.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Sp.base),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Info banner ──────────────────────────────────────────
              Container(
                padding: EdgeInsets.all(Sp.md),
                decoration: BoxDecoration(
                  color: context.vt.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Rad.md),
                  border: Border.all(
                      color: context.vt.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: context.vt.warning, size: 20),
                    SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(
                        'Server restarted. Your SL and target orders are still '
                        'active on Zerodha. Enter the details from your Zerodha '
                        'order book to re-attach AI monitoring and trailing SL.',
                        style: AppTextStyles.caption.copyWith(
                            color: context.vt.warning, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: Sp.lg),

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
                  SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Type', style: AppTextStyles.caption),
                        SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _optionType,
                          dropdownColor: context.vt.surface2,
                          style: AppTextStyles.body,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: context.vt.surface2,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Rad.md),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Rad.md),
                              borderSide: BorderSide(
                                  color: context.vt.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(Rad.md),
                              borderSide: BorderSide(
                                  color: context.vt.accentPurple, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: Sp.md, vertical: Sp.md),
                          ),
                          items: ['CE', 'PE']
                              .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t,
                                      style: AppTextStyles.body)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _optionType = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Sp.md),
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
                  const SizedBox(width: Sp.md),
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
              const SizedBox(height: Sp.lg),

              // ── Order IDs ────────────────────────────────────────────
              _section('Zerodha Order IDs', Icons.receipt_long_outlined),
              _field(
                controller: _slOrderCtrl,
                label: 'SL Order ID',
                hint: '260402001234567',
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: Sp.md),
              _field(
                controller: _targetOrderCtrl,
                label: 'Target Order ID',
                hint: '260402001234568',
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: Sp.lg),

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
                  const SizedBox(width: Sp.md),
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
              const SizedBox(height: Sp.md),
              _field(
                controller: _targetPriceCtrl,
                label: 'Target Premium ₹',
                hint: '499.60',
                numeric: true,
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Number' : null,
              ),
              SizedBox(height: Sp.lg),

              // ── WebSocket token (optional) ────────────────────────────
              _section('WebSocket (optional)', Icons.wifi_outlined),
              _field(
                controller: _instrumentTokenCtrl,
                label: 'Instrument Token',
                hint: '10425858  (from Zerodha instruments list)',
                numeric: true,
              ),
              SizedBox(height: Sp.xxl),

              // ── Submit ───────────────────────────────────────────────
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submit,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white),
                        )
                      : Icon(Icons.play_circle_outline),
                  label: Text(
                    _isLoading ? 'Restarting…' : 'Resume AI Monitoring',
                    style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.vt.accentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Rad.lg)),
                  ),
                ),
              ),

              // ── Feedback ─────────────────────────────────────────────
              if (_success != null) ...[
                SizedBox(height: Sp.base),
                Container(
                  padding: EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: context.vt.accentGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(Rad.md),
                    border: Border.all(
                        color: context.vt.accentGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: context.vt.accentGreen, size: 20),
                      SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text(_success!,
                            style: AppTextStyles.body.copyWith(
                                color: context.vt.accentGreen)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                SizedBox(height: Sp.base),
                Container(
                  padding: EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: context.vt.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(Rad.md),
                    border: Border.all(
                        color: context.vt.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: context.vt.danger, size: 20),
                      SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text(_error!,
                            style: AppTextStyles.body.copyWith(
                                color: context.vt.danger)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Sp.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(bottom: Sp.md),
      child: Row(
        children: [
          Icon(icon, color: context.vt.accentPurple, size: 18),
          const SizedBox(width: Sp.sm),
          Text(title, style: AppTextStyles.h3),
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
          ? TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: AppTextStyles.caption,
        hintStyle: AppTextStyles.caption,
        filled: true,
        fillColor: context.vt.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: context.vt.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide:
              BorderSide(color: context.vt.accentPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: context.vt.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: context.vt.danger, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
      ),
      validator: validator,
    );
  }
}
