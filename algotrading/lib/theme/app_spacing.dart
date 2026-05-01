/// 8pt spacing grid. Values unchanged — they were already correct.
abstract final class Sp {
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double base = 16;
  static const double lg   = 20;
  static const double xl   = 24;
  static const double xxl  = 32;
  static const double xxxl = 48;
}

/// Border radius scale.
/// Reduced from previous values — tighter radii read as precise, not playful.
abstract final class Rad {
  static const double sm   = 4;    // status chips, tiny tags
  static const double md   = 8;    // inputs, buttons
  static const double lg   = 12;   // cards (was 16 — too round)
  static const double xl   = 14;   // bottom sheets
  static const double pill = 100;  // pill badges only
}
