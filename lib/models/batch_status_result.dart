// ==================== DATA MODELS ====================
class BatchStatusResult {
  final double maxValue;
  final List<double> batchData;
  final List<Map<String, dynamic>> batchDataXY;
  final List<String> labels;
  final double currentValue;
  final bool isFromCache;
  final String? errorMessage;
  final bool isDemo;

  const BatchStatusResult({
    required this.maxValue,
    required this.batchData,
    required this.batchDataXY,
    required this.labels,
    required this.currentValue,
    this.isFromCache = false,
    required this.isDemo,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'max_value': maxValue,
      'batch_data': batchData,
      'batch_data_xy': batchDataXY,
      'labels': labels,
      'current_value': currentValue,
      'is_from_cache': isFromCache,
      'error_message': errorMessage,
      'isDemo' : isDemo
    };
  }
}