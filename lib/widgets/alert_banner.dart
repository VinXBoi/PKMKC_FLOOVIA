import 'package:flutter/material.dart';

class AlertBanner extends StatelessWidget {
  final bool hasRedSegments;

  const AlertBanner({
    super.key,
    required this.hasRedSegments,
  });

  @override
  Widget build(BuildContext context) {
    final color = hasRedSegments ? Colors.red : Colors.green;
    final iconData = hasRedSegments ? Icons.warning_amber_rounded : Icons.check_circle;

    return Card(
      color: color[50],
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, color: color[600], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRedSegments ? 'Peringatan Banjir Aktif' : 'Kondisi Aman',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: hasRedSegments
                        ? [
                            Text(
                              'Kondisi banjir saat ini terdeteksi di area ini.',
                              style: TextStyle(
                                color: color[700],
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Harap hindari area yang terdampak untuk keselamatan Anda.',
                              style: TextStyle(
                                color: color[700],
                                fontSize: 14,
                              ),
                            ),
                          ]
                        : [
                            Text(
                              'Tidak ada peringatan banjir aktif di area ini.',
                              style: TextStyle(
                                color: color[700],
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Rute aman untuk dilalui.',
                              style: TextStyle(
                                color: color[700],
                                fontSize: 14,
                              ),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}