import 'package:flutter/material.dart';

class AppTheme {
  // UI Design Tokens (White Theme, Material 3, Clean Engineering layout)
  static const Color colorBackground = Colors.white;
  static const Color colorCardBg = Colors.white;
  static const Color colorBorder = Color(0xFFE5E7EB); // #E5E7EB Light Grey
  static const Color colorPrimary = Color(0xFF1976D2); // Material Blue
  static const Color colorSuccess = Color(0xFF2E7D32); // Material Green
  static const Color colorWarning = Color(0xFFEF6C00); // Material Orange
  static const Color colorError = Color(0xFFC62828); // Material Red
  static const Color colorTextDark = Color(0xFF111827); // #111827 Primary Text
  static const Color colorTextGrey = Color(0xFF6B7280); // #6B7280 Secondary Text

  // Typography Styles
  static const TextStyle styleTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.bold,
    color: colorTextDark,
  );
  static const TextStyle styleSubtitle = TextStyle(
    fontSize: 14,
    color: colorTextGrey,
  );
  static const TextStyle stylePrediction = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: colorTextDark,
  );
  static const TextStyle styleConfidence = TextStyle(
    fontSize: 16,
    color: colorTextGrey,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle styleCardTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: colorTextDark,
  );
  static const TextStyle styleLabel = TextStyle(
    fontSize: 13,
    color: colorTextGrey,
    fontWeight: FontWeight.w500,
  );
}
