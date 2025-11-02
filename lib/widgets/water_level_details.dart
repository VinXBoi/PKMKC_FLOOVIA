// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:floovia/models/lstm_prediction_model.dart';
import 'package:floovia/providers/flood_data_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WaterLevelDetails extends StatefulWidget {
  final double currentWaterLevel;
  final double maxWaterLevel;
  final List<double> waterLevelData;
  final FloodDataProvider floodDataProvider;

  const WaterLevelDetails({
    super.key,
    required this.currentWaterLevel,
    required this.maxWaterLevel,
    required this.waterLevelData,
    required this.floodDataProvider,
  });

  @override
  State<WaterLevelDetails> createState() => _WaterLevelDetailsState();
}

class _WaterLevelDetailsState extends State<WaterLevelDetails> {
  // Check if all water levels are zero
  bool get _hasNoFloodData {
    return widget.waterLevelData.isEmpty || 
           widget.waterLevelData.every((level) => level == 0.0);
  }

  @override
  Widget build(BuildContext context) {
    double waterHeight = (widget.currentWaterLevel / 4);
    final rateInfo = _calculateRateOfChange();

    return Column(
      children: [
        _buildCurrentLevelCard(waterHeight),
        const SizedBox(height: 16),
        _buildFloodPredictionSection(widget.floodDataProvider),
        const SizedBox(height: 16),
        _buildWaterLevelInfo(
          rateLabel: rateInfo.label,
          rateValue: rateInfo.value,
        ),
      ],
    );
  }

  ({String label, double value}) _calculateRateOfChange() {
    if (widget.waterLevelData.length < 2) {
      return (label: 'Status', value: 0.0);
    }

    final currentLevel = widget.waterLevelData.last;
    final previousLevel = widget.waterLevelData[widget.waterLevelData.length - 2];

    const double timeIntervalInHours = 1.0;
    final double heightChange = currentLevel - previousLevel;
    final double speed = heightChange.abs() / timeIntervalInHours;

    if (heightChange > 0.1) {
      return (label: 'Kecepatan Naik', value: speed);
    } else if (heightChange < -0.1) {
      return (label: 'Kecepatan Surut', value: speed);
    } else {
      return (label: 'Status', value: 0.0);
    }
  }

  Widget _buildCurrentLevelCard(double waterHeight) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detail Ketinggian Air Saat Ini',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 48,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.asset(
                        'assets/download-removebg-preview.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        width: 48,
                        height: waterHeight,
                        color: Colors.blue.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  Text(
                    'Status Saat Ini',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.floodDataProvider.isLoading)
                    const CircularProgressIndicator(
                      color: Colors.blue,
                    )
                  else
                    Text(
                      'Ketinggian air: ${widget.currentWaterLevel.toStringAsFixed(1)} cm',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterLevelInfo({
    required String rateLabel,
    required double rateValue,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informasi Ketinggian Air',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoContainer(
                    'Ketinggian Maksimum',
                    widget.maxWaterLevel,
                    'cm',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoContainer(
                    rateLabel,
                    rateValue,
                    rateLabel == 'Status' ? 'Stabil' : 'cm/jam',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoContainer(String label, double value, String unit) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          if (widget.floodDataProvider.isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            )
          else
            Text(
              unit == 'Stabil' ? unit : '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloodPredictionSection(FloodDataProvider floodProvider) {
    final lstmPrediction = floodProvider.lstmPrediction;
    final isLoading = floodProvider.isLoading;
    final currentLevel = max(floodProvider.currentWaterLevel?.toDouble() ?? 0.0, 0.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_down, color: Colors.blue[600]),
                const SizedBox(width: 8),
                const Text(
                  'Prediksi Surut Banjir',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Loading state
            if (isLoading)
              _buildLoadingState()
            
            // No flood data (all zeros)
            else if (_hasNoFloodData || currentLevel == 0.0)
              _buildNoFloodState()
            
            // Valid prediction with flood data
            else if (lstmPrediction != null && lstmPrediction.isValid)
              _buildPredictionContent(lstmPrediction)
            
            // Error or no data
            else
              _buildNoDataState(
                floodProvider.predictionError ?? lstmPrediction?.error,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Memuat prediksi AI...',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFloodState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 48,
              color: Colors.green[600],
            ),
            const SizedBox(height: 12),
            Text(
              'Tidak Ada Banjir',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Kondisi normal, prediksi tidak diperlukan',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataState(String? errorMessage) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              errorMessage ?? 'Prediksi tidak tersedia',
              style: TextStyle(
                color: Colors.orange[900],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionContent(LSTMPredictionResponse prediction) {
    final progress = prediction.waktuSurutJam != null
        ? (1 - (prediction.waktuSurutJam! / 10)).clamp(0.0, 1.0)
        : 0.65;

    return Column(
      children: [
        _buildRecessionProgress(progress, prediction.confidencePercentage),
        const SizedBox(height: 12),
        _buildEstimatedCompletion(prediction),
      ],
    );
  }

  Widget _buildRecessionProgress(double progress, String confidence) {
    final percentage = (progress * 100).toInt();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Status Surut Banjir',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '$percentage%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        // Align(
        //   alignment: Alignment.centerRight,
        //   child: Text(
        //     'Tingkat kepercayaan: $confidence',
        //     style: TextStyle(
        //       color: Colors.grey[600],
        //       fontSize: 12,
        //     ),
        //   ),
        // ),
      ],
    );
  }

  Widget _buildEstimatedCompletion(LSTMPredictionResponse prediction) {
    final formattedTime = prediction.formattedTime;
    final now = DateTime.now();
    final estimated = now
        .add(Duration(hours: prediction.waktuSurutJam?.toInt() ?? 0))
        .add(Duration(minutes: prediction.waktuSurutMenit ?? 0));
    final estimatedCompletion = DateFormat('HH:mm').format(estimated);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        // border: Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.blue[600], size: 16),
              const SizedBox(width: 8),
              Text(
                'Estimasi Waktu Surut',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formattedTime,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.blue[600],
            ),
          ),
          Text(
            'Estimasi selesai: $estimatedCompletion',
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}