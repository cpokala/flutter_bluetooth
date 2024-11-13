import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;

class MlService {
  static final _logger = Logger();
  static Map<String, dynamic>? _scalerParams;
  static bool _initialized = false;

  // Cache for the sample predictions to help validate our clustering
  static Map<String, dynamic>? _samplePredictions;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load scaler parameters
      final String scalerJson = await rootBundle.loadString('assets/scaler_params.json');
      _scalerParams = jsonDecode(scalerJson);

      // Load sample predictions for validation
      final String predictionsJson = await rootBundle.loadString('assets/sample_predictions.json');
      _samplePredictions = jsonDecode(predictionsJson);

      _initialized = true;
      _logger.i('ML Service initialized successfully');
    } catch (e) {
      _logger.e('Error initializing ML Service: $e');
      rethrow;
    }
  }

  static List<int> runClustering(List<List<double>> points) {
    if (!_initialized || _scalerParams == null) {
      throw Exception('ML Service not initialized');
    }

    try {
      // Scale the points
      final scaledPoints = _scalePoints(points);

      // Implement DBSCAN clustering directly in Dart
      return _dbscanClustering(
        scaledPoints,
        eps: 0.5,
        minPoints: 5,
      );
    } catch (e) {
      _logger.e('Error running clustering: $e');
      rethrow;
    }
  }

  static List<List<double>> _scalePoints(List<List<double>> points) {
    final means = List<double>.from(_scalerParams!['mean']);
    final scales = List<double>.from(_scalerParams!['scale']);

    return points.map((point) {
      return List.generate(
        point.length,
            (i) => (point[i] - means[i]) / scales[i],
      );
    }).toList();
  }

  static List<int> _dbscanClustering(
      List<List<double>> points, {
        required double eps,
        required int minPoints,
      }) {
    final int n = points.length;
    final labels = List.filled(n, -1);
    final visited = List.filled(n, false);
    int currentCluster = 0;

    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      visited[i] = true;
      final neighbors = _getNeighbors(points, i, eps);

      if (neighbors.length < minPoints) {
        labels[i] = -1; // Noise point
        continue;
      }

      // Expand cluster
      labels[i] = currentCluster;

      for (int j = 0; j < neighbors.length; j++) {
        int neighborIdx = neighbors[j];

        if (!visited[neighborIdx]) {
          visited[neighborIdx] = true;
          final newNeighbors = _getNeighbors(points, neighborIdx, eps);

          if (newNeighbors.length >= minPoints) {
            neighbors.addAll(
                newNeighbors.where((n) => !neighbors.contains(n))
            );
          }
        }

        if (labels[neighborIdx] == -1) {
          labels[neighborIdx] = currentCluster;
        }
      }

      currentCluster++;
    }

    return labels;
  }

  static List<int> _getNeighbors(List<List<double>> points, int pointIdx, double eps) {
    final neighbors = <int>[];
    final point = points[pointIdx];

    for (int i = 0; i < points.length; i++) {
      if (i != pointIdx && _calculateDistance(point, points[i]) <= eps) {
        neighbors.add(i);
      }
    }

    return neighbors;
  }

  static double _calculateDistance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw Exception('Points have different dimensions');
    }

    double sumSquared = 0.0;
    for (int i = 0; i < a.length; i++) {
      sumSquared += math.pow(a[i] - b[i], 2);
    }
    return math.sqrt(sumSquared);
  }

  static bool validatePrediction(List<double> input, int prediction) {
    if (_samplePredictions == null) return true;

    final scaledInput = _scalePoints([input])[0];
    final sampleInputs = List<List<double>>.from(
        _samplePredictions!['input_scaled'].map((x) => List<double>.from(x))
    );

    // Find the closest sample point
    double minDistance = double.infinity;
    int closestPrediction = -1;

    for (int i = 0; i < sampleInputs.length; i++) {
      final distance = _calculateDistance(scaledInput, sampleInputs[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestPrediction = _samplePredictions!['predictions'][i];
      }
    }

    // If the point is very close to a sample point, predictions should match
    return minDistance > 0.1 || prediction == closestPrediction;
  }
}
