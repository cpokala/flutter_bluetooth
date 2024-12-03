import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;

class MlService {
  static final _logger = Logger();
  static Map<String, dynamic>? _scalerParams;
  static bool _initialized = false;
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
      // Log raw input statistics
      _logInputStats(points, "Raw");

      // First apply log transformation to pressure values
      final logTransformedPoints = _applyLogTransformation(points);
      _logInputStats(logTransformedPoints, "Log Transformed");

      // Then scale all features
      final scaledPoints = _scalePoints(logTransformedPoints);
      _logInputStats(scaledPoints, "Scaled");

      // Calculate appropriate epsilon based on scaled data
      double eps = _calculateOptimalEpsilon(scaledPoints);
      int minPoints = _calculateOptimalMinPoints(points.length);

      _logger.i('DBSCAN Parameters - eps: $eps, minPoints: $minPoints');

      // Run DBSCAN clustering
      final labels = _dbscanClustering(
          scaledPoints,
          eps: eps,
          minPoints: minPoints
      );

      // Log clustering results
      _logClusteringResults(points, labels);

      return labels;
    } catch (e, stackTrace) {
      _logger.e('Error running clustering: $e');
      _logger.e('Stack trace: $stackTrace');
      rethrow;
    }
  }

  static List<List<double>> _applyLogTransformation(List<List<double>> points) {
    if (points.isEmpty) return [];

    return points.map((point) => List.generate(point.length, (i) {
      // Apply log transformation only to pressure (index 2) and ensure it's positive
      if (i == 2) {
        final value = math.max(point[i], 1e-10);
        return math.log(value);
      }
      return point[i];
    })).toList();
  }

  static void _logInputStats(List<List<double>> points, String stage) {
    if (points.isEmpty) return;

    _logger.i('=== $stage Data Statistics ===');
    for (int i = 0; i < points[0].length; i++) {
      var values = points.map((p) => p[i]).toList();
      var min = values.reduce(math.min);
      var max = values.reduce(math.max);
      var avg = values.reduce((a, b) => a + b) / values.length;
      var stdDev = _calculateStdDev(values);

      String feature = i == 0 ? "VOC" :
      i == 1 ? "Temperature" :
      i == 2 ? "Pressure" : "Humidity";

      _logger.i('$feature - Min: ${min.toStringAsFixed(2)}, Max: ${max.toStringAsFixed(2)}, '
          'Avg: ${avg.toStringAsFixed(2)}, StdDev: ${stdDev.toStringAsFixed(2)}');
    }
  }

  static double _calculateStdDev(List<double> values) {
    double mean = values.reduce((a, b) => a + b) / values.length;
    num sumSquaredDiff = values.map((x) => math.pow(x - mean, 2))
        .reduce((a, b) => a + b);
    return math.sqrt(sumSquaredDiff / values.length);
  }

  static List<List<double>> _scalePoints(List<List<double>> points) {
    if (points.isEmpty) return [];

    final numFeatures = points[0].length;
    List<double> mins = List.filled(numFeatures, double.infinity);
    List<double> maxs = List.filled(numFeatures, double.negativeInfinity);

    // Find min and max for each feature
    for (var point in points) {
      for (int i = 0; i < numFeatures; i++) {
        mins[i] = math.min(mins[i], point[i]);
        maxs[i] = math.max(maxs[i], point[i]);
      }
    }

    // Scale to [0,1] range
    return points.map((point) {
      return List.generate(numFeatures, (i) {
        double range = maxs[i] - mins[i];
        if (range.abs() < 1e-10) return 0.0;
        return (point[i] - mins[i]) / range;
      });
    }).toList();
  }

  static double _calculateOptimalEpsilon(List<List<double>> scaledPoints) {
    if (scaledPoints.length < 2) return 0.3; // default for very small datasets

    // Calculate k-distance graph (k=4)
    const int k = 4;
    var distances = <double>[];

    for (var point in scaledPoints) {
      var pointDistances = scaledPoints
          .where((p) => p != point)
          .map((p) => _calculateDistance(point, p))
          .toList()
        ..sort();

      if (pointDistances.length >= k) {
        distances.add(pointDistances[k - 1]);
      }
    }

    distances.sort();

    // Find the "elbow" point
    double maxCurvature = 0.0;
    double optimalEps = 0.3; // default value

    for (int i = 1; i < distances.length - 1; i++) {
      double curvature = (distances[i+1] - 2 * distances[i] + distances[i-1]).abs();
      if (curvature > maxCurvature) {
        maxCurvature = curvature;
        optimalEps = distances[i];
      }
    }

    // Ensure epsilon is within reasonable bounds
    return math.max(0.1, math.min(0.5, optimalEps));
  }

  static int _calculateOptimalMinPoints(int numPoints) {
    // Scale with dataset size but keep within reasonable bounds
    int minPoints = (math.log(numPoints) * 1.5).round();
    return math.max(3, math.min(minPoints, 6));
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

    _logger.d('Starting DBSCAN clustering with eps=$eps, minPoints=$minPoints');

    // Build neighbor cache for efficiency
    Map<int, List<int>> neighborCache = _buildNeighborCache(points, eps);

    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      visited[i] = true;
      List<int> neighbors = neighborCache[i] ?? [];

      _logger.d('Processing point $i with ${neighbors.length} neighbors');

      if (neighbors.length < minPoints) {
        labels[i] = -1;
        continue;
      }

      // Start new cluster
      labels[i] = currentCluster;
      List<int> seedSet = List<int>.from(neighbors);

      for (int seedIdx = 0; seedIdx < seedSet.length; seedIdx++) {
        int current = seedSet[seedIdx];

        if (labels[current] == -1) {
          labels[current] = currentCluster;
        }

        if (!visited[current]) {
          visited[current] = true;
          List<int> currentNeighbors = neighborCache[current] ?? [];

          if (currentNeighbors.length >= minPoints) {
            for (int newPoint in currentNeighbors) {
              if (!seedSet.contains(newPoint)) {
                seedSet.add(newPoint);
              }
            }
          }
        }
      }

      _logger.i('Completed cluster $currentCluster with ${seedSet.length} points');
      currentCluster++;
    }

    return labels;
  }

  static Map<int, List<int>> _buildNeighborCache(List<List<double>> points, double eps) {
    var cache = <int, List<int>>{};

    for (int i = 0; i < points.length; i++) {
      cache[i] = _getNeighbors(points, i, eps);
    }

    return cache;
  }

  static List<int> _getNeighbors(List<List<double>> points, int pointIdx, double eps) {
    List<int> neighbors = [];
    for (int i = 0; i < points.length; i++) {
      if (i != pointIdx && _calculateDistance(points[pointIdx], points[i]) <= eps) {
        neighbors.add(i);
      }
    }
    return neighbors;
  }

  static void _logClusteringResults(List<List<double>> points, List<int> labels) {
    var clusters = <int, List<int>>{};
    var noisePoints = <int>[];

    for (int i = 0; i < labels.length; i++) {
      if (labels[i] == -1) {
        noisePoints.add(i);
      } else {
        clusters.putIfAbsent(labels[i], () => []).add(i);
      }
    }

    _logger.i('=== Clustering Results ===');
    _logger.i('Total Points: ${points.length}');
    _logger.i('Number of Clusters: ${clusters.length}');
    _logger.i('Noise Points: ${noisePoints.length}');

    clusters.forEach((clusterId, pointIndices) {
      var stats = _calculateClusterStats(points, pointIndices);
      _logger.i('\nCluster $clusterId:');
      _logger.i('Points: ${pointIndices.length}');
      _logger.i('Center: ${stats.center.map((e) => e.toStringAsFixed(2))}');
      _logger.i('Std Dev: ${stats.stdDev.map((e) => e.toStringAsFixed(2))}');
    });

    if (noisePoints.isNotEmpty) {
      var noiseStats = _calculateClusterStats(points, noisePoints);
      _logger.i('\nNoise Points:');
      _logger.i('Count: ${noisePoints.length}');
      _logger.i('Center: ${noiseStats.center.map((e) => e.toStringAsFixed(2))}');
      _logger.i('Std Dev: ${noiseStats.stdDev.map((e) => e.toStringAsFixed(2))}');
    }
  }

  static ClusterStats _calculateClusterStats(List<List<double>> points, List<int> indices) {
    var dimensions = points[0].length;
    var center = List<double>.filled(dimensions, 0.0);
    var stdDev = List<double>.filled(dimensions, 0.0);

    // Calculate center
    for (var idx in indices) {
      for (int d = 0; d < dimensions; d++) {
        center[d] += points[idx][d];
      }
    }
    for (int d = 0; d < dimensions; d++) {
      center[d] /= indices.length;
    }

    // Calculate standard deviation
    for (var idx in indices) {
      for (int d = 0; d < dimensions; d++) {
        stdDev[d] += math.pow(points[idx][d] - center[d], 2);
      }
    }
    for (int d = 0; d < dimensions; d++) {
      stdDev[d] = math.sqrt(stdDev[d] / indices.length);
    }

    return ClusterStats(center: center, stdDev: stdDev);
  }

  static double _calculateDistance(List<double> a, List<double> b) {
    double sumSquared = 0.0;
    for (int i = 0; i < a.length; i++) {
      sumSquared += math.pow(a[i] - b[i], 2);
    }
    return math.sqrt(sumSquared);
  }
}

class ClusterStats {
  final List<double> center;
  final List<double> stdDev;

  ClusterStats({required this.center, required this.stdDev});
}