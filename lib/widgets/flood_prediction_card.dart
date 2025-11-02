import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:floovia/models/lstm_prediction_model.dart';
import 'package:intl/intl.dart';
import '../providers/flood_data_provider.dart';

class FloodPredictionCard extends StatefulWidget {
  final VoidCallback onTap;
  const FloodPredictionCard({super.key, required this.onTap});

  @override
  State<FloodPredictionCard> createState() => _FloodPredictionCardState();
}

class _FloodPredictionCardState extends State<FloodPredictionCard> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheImage();
  }

  Future<void> _precacheImage() async {
    try {
      await precacheImage(
        const AssetImage('assets/download-removebg-preview.png'),
        context,
      );
    } catch (e) {
      debugPrint('Error precaching image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FloodDataProvider>(
      builder: (context, floodProvider, _) {
        final currentWaterLevel =
            max(floodProvider.currentWaterLevel?.toInt() ?? 0, 0);
        final maxWaterLevel = floodProvider.maxWaterLevel?.toInt() ?? 200;
        final lstmPrediction = floodProvider.lstmPrediction;
        final isLoading = floodProvider.isLoading;

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
                _buildWaterLevelIndicator(
                    currentWaterLevel, maxWaterLevel, isLoading),
                const SizedBox(height: 16),
                if (isLoading)
                  _buildLoadingState()
                else if (lstmPrediction != null &&
                    lstmPrediction.isValid &&
                    currentWaterLevel > 0)
                  _buildPredictionContent(lstmPrediction)
                else
                  _buildNoDataState(
                    floodProvider.predictionError ?? lstmPrediction?.error,
                  ),
                const SizedBox(height: 16),
                _buildDetailedPredictionButton(),
              ],
            ),
          ),
        );
      },
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

  Widget _buildNoDataState(String? errorMessage) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
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
        const SizedBox(height: 16),
        _buildEstimatedCompletion(prediction),
      ],
    );
  }

  Widget _buildWaterLevelIndicator(
      int currentWaterLevel, int maxWaterLevel, bool isLoading) {
    double waterHeight = maxWaterLevel > 0 ? (currentWaterLevel / 4)  : 0;
    waterHeight = waterHeight.clamp(0.0, 100.0);

    return Row(
      children: [
        SizedBox(
          width: 55,
          height: 100,
          child: Stack(
            children: [
              Container(
                width: 55,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Image.asset(
                      'assets/download-removebg-preview.png',
                      fit: BoxFit.contain,
                      cacheWidth: 55,
                      cacheHeight: 100,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.blue[100],
                          child: Icon(
                            Icons.water,
                            size: 40,
                            color: Colors.blue[300],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  width: 55,
                  height: waterHeight,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.5),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ketinggian Air Saat Ini',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              if (!isLoading)
                Text(
                  '$currentWaterLevel cm',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[600],
                  ),
                )
              else
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Terakhir diperbarui: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
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
            const Text('Status Surut Banjir',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text('$percentage%',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
        ),
      ],
    );
  }

  /// ✅ Simplified for your current model
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

  Widget _buildDetailedPredictionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: widget.onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: const Text('Lihat Detail Banjir'),
      ),
    );
  }
}
