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
      // Scale the points
      final scaledPoints = _scalePoints(points);

      // Run DBSCAN with adjusted parameters
      final labels = _dbscanClustering(
          scaledPoints,
          eps: 0.3,  // Reduced epsilon for tighter clusters
          minPoints: 4  // Minimum points for core point
      );

      // Analyze and log density information
      final densityStats = analyzeDensity(scaledPoints, labels);
      _logger.i('Cluster Density Analysis:');
      densityStats.forEach((key, value) {
        _logger.i('$key: $value');
      });

      // Log cluster statistics
      _logClusterStats(scaledPoints, labels);

      return labels;
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
    final labels = List.filled(n, -1);     // -1 indicates unvisited/noise
    final visited = List.filled(n, false);
    int currentCluster = 0;

    _logger.d('Starting DBSCAN clustering with eps=$eps, minPoints=$minPoints');

    // Function to find points in eps neighborhood
    List<int> getNeighbors(int pointIdx) {
      List<int> neighbors = [];
      for (int i = 0; i < points.length; i++) {
        if (i != pointIdx &&
            _calculateDistance(points[pointIdx], points[i]) <= eps) {
          neighbors.add(i);
        }
      }
      return neighbors;
    }

    // Main DBSCAN algorithm
    for (int i = 0; i < n; i++) {
      if (visited[i]) continue;

      visited[i] = true;
      List<int> neighbors = getNeighbors(i);

      _logger.d('Processing point $i with ${neighbors.length} neighbors');

      // If point doesn't have enough neighbors, mark as noise
      if (neighbors.length < minPoints) {
        labels[i] = -1;  // Mark as noise
        _logger.d('Point $i marked as noise');
        continue;
      }

      // Start new cluster
      labels[i] = currentCluster;
      _logger.d('Starting new cluster $currentCluster with point $i');

      // Process all neighbors
      List<int> seedSet = List<int>.from(neighbors);
      int seedIdx = 0;

      // Expand cluster through density-reachable points
      while (seedIdx < seedSet.length) {
        int current = seedSet[seedIdx];

        // Handle previously marked noise points
        if (labels[current] == -1) {
          labels[current] = currentCluster;  // Change noise to border point
          _logger.d('Point $current changed from noise to border point');
        }

        // If point not processed yet
        if (!visited[current]) {
          visited[current] = true;

          // Find its neighbors
          List<int> currentNeighbors = getNeighbors(current);

          // If it's a core point, add its neighbors to process
          if (currentNeighbors.length >= minPoints) {
            for (int newPoint in currentNeighbors) {
              if (!seedSet.contains(newPoint)) {
                seedSet.add(newPoint);
                _logger.d('Added point $newPoint to seedSet of cluster $currentCluster');
              }
            }
          }
        }
        seedIdx++;
      }

      _logger.i('Completed cluster $currentCluster with ${seedSet.length} points');
      currentCluster++;
    }

    return labels;
  }

  static Map<String, double> analyzeDensity(List<List<double>> points, List<int> labels) {
    Map<String, double> densityStats = {};
    Set<int> uniqueClusters = labels.where((l) => l != -1).toSet();

    for (int clusterId in uniqueClusters) {
      List<int> clusterPoints = [];
      for (int i = 0; i < labels.length; i++) {
        if (labels[i] == clusterId) clusterPoints.add(i);
      }

      // Calculate average distance between points in cluster
      double avgDistance = 0;
      int connections = 0;
      double maxDistance = 0;

      for (int i = 0; i < clusterPoints.length; i++) {
        for (int j = i + 1; j < clusterPoints.length; j++) {
          double dist = _calculateDistance(
              points[clusterPoints[i]],
              points[clusterPoints[j]]
          );
          avgDistance += dist;
          maxDistance = math.max(maxDistance, dist);
          connections++;
        }
      }

      if (connections > 0) {
        avgDistance /= connections;
        densityStats['cluster_${clusterId}_density'] =
            clusterPoints.length / avgDistance;
        densityStats['cluster_${clusterId}_avg_distance'] = avgDistance;
        densityStats['cluster_${clusterId}_max_distance'] = maxDistance;
        densityStats['cluster_${clusterId}_point_count'] =
            clusterPoints.length.toDouble();
      }
    }

    return densityStats;
  }

  static void _logClusterStats(List<List<double>> points, List<int> labels) {
    Map<int, List<int>> clusters = {};
    int noiseCount = 0;

    // Group points by cluster
    for (int i = 0; i < labels.length; i++) {
      if (labels[i] == -1) {
        noiseCount++;
      } else {
        clusters.putIfAbsent(labels[i], () => []).add(i);
      }
    }

    _logger.i('Clustering Results:');
    _logger.i('Total Points: ${points.length}');
    _logger.i('Number of Clusters: ${clusters.length}');
    _logger.i('Noise Points: $noiseCount');

    clusters.forEach((clusterId, clusterPoints) {
      _logger.i('\nCluster $clusterId:');
      _logger.i('Points: ${clusterPoints.length}');

      // Calculate cluster center
      List<double> center = List.filled(points[0].length, 0);
      for (int idx in clusterPoints) {
        for (int j = 0; j < points[idx].length; j++) {
          center[j] += points[idx][j];
        }
      }
      for (int j = 0; j < center.length; j++) {
        center[j] /= clusterPoints.length;
      }

      _logger.i('Cluster Center: ${center.map((e) => e.toStringAsFixed(2))}');
    });
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

  // Helper method to get density metrics for a specific cluster
  static Map<String, double> getClusterDensityMetrics(
      List<List<double>> points,
      List<int> clusterIndices
      ) {
    if (clusterIndices.isEmpty) {
      return {
        'density': 0.0,
        'avg_distance': 0.0,
        'max_distance': 0.0
      };
    }

    List<List<double>> clusterPoints =
    clusterIndices.map((i) => points[i]).toList();

    double avgDistance = 0;
    double maxDistance = 0;
    int connections = 0;

    for (int i = 0; i < clusterPoints.length; i++) {
      for (int j = i + 1; j < clusterPoints.length; j++) {
        double dist = _calculateDistance(clusterPoints[i], clusterPoints[j]);
        avgDistance += dist;
        maxDistance = math.max(maxDistance, dist);
        connections++;
      }
    }

    if (connections > 0) {
      avgDistance /= connections;
      return {
        'density': clusterPoints.length / avgDistance,
        'avg_distance': avgDistance,
        'max_distance': maxDistance
      };
    } else {
      return {
        'density': 0.0,
        'avg_distance': 0.0,
        'max_distance': 0.0
      };
    }
  }
}