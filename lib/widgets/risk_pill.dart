// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../utils/route_utils.dart';

class RiskPill extends StatelessWidget {
  const RiskPill({
    super.key,
    required this.label,   
    required this.status,  
  });

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final base = RouteUtils.getStatusColor(status);
    final bg = RouteUtils.tintedBg(context, base);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(
            color: base.withOpacity(isDark ? 0.40 : 0.45),
            width: 1,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: base.withOpacity(isDark ? 0.90 : 0.85),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
