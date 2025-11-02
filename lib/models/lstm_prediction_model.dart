class LSTMPredictionResponse {
  final bool success;
  final double? waktuSurutJam;
  final int? waktuSurutMenit;
  final String? estimasiWaktuSelesai;
  final double? confidence;
  final String? message;
  final int? dataPointsUsed;
  final String? error;

  LSTMPredictionResponse({
    required this.success,
    this.waktuSurutJam,
    this.waktuSurutMenit,
    this.estimasiWaktuSelesai,
    this.confidence,
    this.message,
    this.dataPointsUsed,
    this.error,
  });

  /// Factory constructor to parse from JSON API response
  factory LSTMPredictionResponse.fromJson(Map<String, dynamic> json) {
    // Prefer the key your API actually sends: "prediksi_waktu_surut_jam"
    final waktuJam = json['prediksi_waktu_surut_jam'] ??
        json['waktu_surut_jam']; // fallback for backward compatibility

    return LSTMPredictionResponse(
      success: json['success'] ?? false,
      waktuSurutJam: (waktuJam is num) ? waktuJam.toDouble() : null,
      waktuSurutMenit: (waktuJam is num)
          ? ((waktuJam - waktuJam.floor()) * 60).round()
          : null,
      estimasiWaktuSelesai: json['estimasi_waktu_selesai'],
      confidence: (json['confidence'] is num)
          ? json['confidence'].toDouble()
          : null,
      message: json['message'],
      dataPointsUsed: json['data_points_used']?.toInt(),
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'prediksi_waktu_surut_jam': waktuSurutJam,
      'waktu_surut_menit': waktuSurutMenit,
      'estimasi_waktu_selesai': estimasiWaktuSelesai,
      'confidence': confidence,
      'message': message,
      'data_points_used': dataPointsUsed,
      'error': error,
    };
  }

  /// Get formatted time string (e.g., "12 jam 16 menit")
  String get formattedTime {
    if (waktuSurutJam == null) return 'N/A';
    final hours = waktuSurutJam!.floor();
    final minutes = ((waktuSurutJam! - hours) * 60).round();
    if (hours == 0) return '$minutes menit';
    if (minutes == 0) return '$hours jam';
    return '$hours jam $minutes menit';
  }

  /// Get confidence percentage (e.g., "85%")
  String get confidencePercentage {
    if (confidence == null) return 'N/A';
    return '${(confidence! * 100).toStringAsFixed(0)}%';
  }

  /// Check if prediction is valid
  bool get isValid => success && waktuSurutJam != null && waktuSurutJam! > 0;

  @override
  String toString() {
    return 'LSTMPredictionResponse(success: $success, waktuSurutJam: $waktuSurutJam, error: $error)';
  }
}

/// Data point for LSTM input
class LSTMDataPoint {
  final double suhuCelsius;
  final double featureX; // curah_hujan (rainfall)
  final double featureY; // ketinggian_air (water level)
  final String? timestamp;

  LSTMDataPoint({
    required this.suhuCelsius,
    required this.featureX,
    required this.featureY,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'suhu_celsius': suhuCelsius,
        'featureX': featureX,
        'featureY': featureY,
        if (timestamp != null) 'timestamp': timestamp,
      };

  factory LSTMDataPoint.fromJson(Map<String, dynamic> json) => LSTMDataPoint(
        suhuCelsius: (json['suhu_celsius'] ?? 0).toDouble(),
        featureX: (json['featureX'] ?? 0).toDouble(),
        featureY: (json['featureY'] ?? 0).toDouble(),
        timestamp: json['timestamp'],
      );
}

/// Request model for LSTM prediction
class LSTMPredictRequest {
  final List<LSTMDataPoint> data;

  LSTMPredictRequest({required this.data});

  Map<String, dynamic> toJson() => {
        'data': data.map((e) => e.toJson()).toList(),
      };
}
