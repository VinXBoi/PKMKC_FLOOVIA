import 'package:flutter/material.dart';

class AlternativeRouteCard extends StatefulWidget {
  final VoidCallback onTap;

  const AlternativeRouteCard({super.key, required this.onTap});

  @override
  State<AlternativeRouteCard> createState() => _AlternativeRouteCardState();
}

class _AlternativeRouteCardState extends State<AlternativeRouteCard> {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.blue[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Rute Alternatif",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600], // warna utama biru
                  foregroundColor: Colors.white, // teks dan ikon putih
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.alt_route),
                label: const Text(
                  "Cari Rute Sekarang",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  widget.onTap();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
