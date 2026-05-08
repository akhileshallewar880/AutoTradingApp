import 'package:intl/intl.dart';

/// ₹27,425  (0 decimals, Indian grouping)
final _fmtRound = NumberFormat.currency(
    locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹27,425.50  (2 decimals, Indian grouping)
final _fmtDecimal = NumberFormat.currency(
    locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Number-only formatters (no ₹ symbol — used when prefix is separate)
final _numRound   = NumberFormat('#,##,##0',    'en_IN');
final _numDecimal = NumberFormat('#,##,##0.##', 'en_IN');

/// Format with ₹ symbol.  [decimals] 0 or 2 (default 2).
String fmtRupees(double value, {int decimals = 2}) =>
    decimals == 0 ? _fmtRound.format(value) : _fmtDecimal.format(value);

/// Format a bare number (no symbol) with Indian comma grouping.
/// [decimals] 0 = whole number, 2 = up to 2 decimal places (trailing zeros dropped).
String fmtNumber(double value, {int decimals = 0}) =>
    decimals == 0 ? _numRound.format(value) : _numDecimal.format(value);
