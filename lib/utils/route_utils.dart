// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class RouteUtils {
  static Color getStatusColor(String status) {
    switch (status) {
      case 'Aman':
        return Colors.green;
      case 'Ringan':
      case 'Ringan Tersebar':
        return Colors.orange;
      case 'Banjir Sebagian':
        return Colors.deepOrange;
      case 'Banjir':
        return Colors.red;
      case 'Banjir Parah':
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }

  static String getStatusIcon(String status) {
    switch (status) {
      case 'Aman':
        return '✓';
      case 'Ringan':
        return '⚠';
      case 'Ringan Tersebar':
        return '⚠';
      case 'Banjir Sebagian':
        return '⚠';
      case 'Banjir':
        return '✗';
      case 'Banjir Parah':
        return '⛔';
      default:
        return '?';
    }
  }
  
  static Color tintedBg(BuildContext context, Color base) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = isDark ? 0.20 : 0.14;
    return Color.alphaBlend(base.withOpacity(opacity), surface);
  }
}