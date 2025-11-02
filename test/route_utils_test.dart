import 'package:floovia/utils/route_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // --- Tes untuk fungsi getStatusColor ---
  group('RouteUtils.getStatusColor', () {
    test('should return green for "Aman" status', () {
      // Act: Panggil fungsi dengan status "Aman"
      final color = RouteUtils.getStatusColor('Aman');

      // Assert: Periksa apakah warna yang dikembalikan adalah hijau
      expect(color, Colors.green);
    });

    test('should return orange for "Ringan" status', () {
      // Act
      final color = RouteUtils.getStatusColor('Ringan');

      // Assert
      expect(color, Colors.orange);
    });

    test('should return red for "Banjir" status', () {
      // Act
      final color = RouteUtils.getStatusColor('Banjir');

      // Assert
      expect(color, Colors.red);
    });

    test('should return grey for any other status', () {
      // Act
      final color = RouteUtils.getStatusColor('Status Tidak Dikenal');

      // Assert
      expect(color, Colors.grey);
    });
  });

  // --- Tes untuk fungsi getStatusIcon ---
  group('RouteUtils.getStatusIcon', () {
    test('should return check icon for "Aman" status', () {
      // Act
      final icon = RouteUtils.getStatusIcon('Aman');

      // Assert
      expect(icon, '✓');
    });

    test('should return warning icon for "Ringan" status', () {
      // Act
      final icon = RouteUtils.getStatusIcon('Ringan');

      // Assert
      expect(icon, '⚠');
    });

    test('should return cross icon for "Banjir" status', () {
      // Act
      final icon = RouteUtils.getStatusIcon('Banjir');

      // Assert
      expect(icon, '✗');
    });

    test('should return question mark icon for any other status', () {
      // Act
      final icon = RouteUtils.getStatusIcon('Status Apapun');

      // Assert
      expect(icon, '?');
    });
  });
}