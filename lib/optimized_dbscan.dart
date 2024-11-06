import 'dart:math' show sqrt, pow;

class OptimizedDBSCAN {
  final double eps;
  final int minPoints;
  final List<List<double>> points;
  late List<int> labels;
  late List<bool> visited;
  late List<List<double>> normalizedPoints;

  // Statistics for each feature
  late List<double> means;
  late List<double> stdDevs;

  OptimizedDBSCAN({
    required this.points,
    required this.eps,
    required this.minPoints,
  }) {
    labels = List.filled(points.length, -1);
    visited = List.filled(points.length, false);
    normalizedPoints = _normalizeData(points);
  }

  List<List<double>> _normalizeData(List<List<double>> data) {
    if (data.isEmpty) return [];

    int numFeatures = data[0].length;
    means = List.filled(numFeatures, 0.0);
    stdDevs = List.filled(numFeatures, 0.0);

    // Calculate means
    for (var point in data) {
      for (int i = 0; i < numFeatures; i++) {
        means[i] += point[i];
      }
    }
    for (int i = 0; i < numFeatures; i++) {
      means[i] /= data.length;
    }

    // Calculate standard deviations
    for (var point in data) {
      for (int i = 0; i < numFeatures; i++) {
        stdDevs[i] += pow(point[i] - means[i], 2);
      }
    }
    for (int i = 0; i < numFeatures; i++) {
      stdDevs[i] = sqrt(stdDevs[i] / data.length);
      if (stdDevs[i] == 0) stdDevs[i] = 1.0; // Prevent division by zero
    }

    // Normalize the data
    return data.map((point) {
      return List.generate(numFeatures,
              (i) => (point[i] - means[i]) / stdDevs[i]);
    }).toList();
  }

  double _euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) return double.infinity;

    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      sum += pow(a[i] - b[i], 2);
    }
    return sqrt(sum);
  }

  List<int> _getNeighbors(int pointIndex) {
    List<int> neighbors = [];
    for (int i = 0; i < normalizedPoints.length; i++) {
      if (i != pointIndex &&
          _euclideanDistance(normalizedPoints[i], normalizedPoints[pointIndex]) <= eps) {
        neighbors.add(i);
      }
    }
    return neighbors;
  }

  void _expandCluster(int pointIndex, List<int> neighbors, int clusterId) {
    labels[pointIndex] = clusterId;

    for (int i = 0; i < neighbors.length; i++) {
      int neighborIndex = neighbors[i];

      if (!visited[neighborIndex]) {
        visited[neighborIndex] = true;
        List<int> newNeighbors = _getNeighbors(neighborIndex);

        if (newNeighbors.length >= minPoints) {
          neighbors.addAll(newNeighbors.where((n) => !neighbors.contains(n)));
        }
      }

      if (labels[neighborIndex] == -1) {
        labels[neighborIndex] = clusterId;
      }
    }
  }

  Map<String, dynamic> fit() {
    int clusterId = 0;

    for (int i = 0; i < points.length; i++) {
      if (visited[i]) continue;

      visited[i] = true;
      List<int> neighbors = _getNeighbors(i);

      if (neighbors.length < minPoints) {
        labels[i] = -1; // Noise point
        continue;
      }

      _expandCluster(i, neighbors, clusterId);
      clusterId++;
    }

    return _generateStatistics();
  }

  Map<String, dynamic> _generateStatistics() {
    Map<int, List<int>> clusters = {};
    List<int> noisePoints = [];
    Map<int, Map<String, double>> statistics = {};

    // Group points by cluster
    for (int i = 0; i < labels.length; i++) {
      int label = labels[i];
      if (label == -1) {
        noisePoints.add(i);
      } else {
        clusters.putIfAbsent(label, () => []).add(i);
      }
    }

    // Calculate statistics for each cluster
    clusters.forEach((clusterId, pointIndices) {
      List<List<double>> clusterPoints =
      pointIndices.map((i) => points[i]).toList();

      statistics[clusterId] = {
        'size': pointIndices.length.toDouble(),
        'avg_voc': _calculateMean(clusterPoints, 0),
        'std_voc': _calculateStd(clusterPoints, 0),
        'avg_temperature': _calculateMean(clusterPoints, 1),
        'std_temperature': _calculateStd(clusterPoints, 1),
        'avg_pressure': _calculateMean(clusterPoints, 2),
        'std_pressure': _calculateStd(clusterPoints, 2),
        'avg_humidity': _calculateMean(clusterPoints, 3),
        'std_humidity': _calculateStd(clusterPoints, 3),
      };
    });

    // Calculate statistics for noise points
    if (noisePoints.isNotEmpty) {
      List<List<double>> noiseData =
      noisePoints.map((i) => points[i]).toList();

      statistics[-1] = {
        'size': noisePoints.length.toDouble(),
        'avg_voc': _calculateMean(noiseData, 0),
        'std_voc': _calculateStd(noiseData, 0),
        'avg_temperature': _calculateMean(noiseData, 1),
        'std_temperature': _calculateStd(noiseData, 1),
        'avg_pressure': _calculateMean(noiseData, 2),
        'std_pressure': _calculateStd(noiseData, 2),
        'avg_humidity': _calculateMean(noiseData, 3),
        'std_humidity': _calculateStd(noiseData, 3),
      };
    }

    return {
      'labels': labels,
      'clusters': clusters,
      'noise_points': noisePoints,
      'statistics': statistics,
    };
  }

  double _calculateMean(List<List<double>> points, int featureIndex) {
    if (points.isEmpty) return 0.0;
    return points.map((p) => p[featureIndex]).reduce((a, b) => a + b) /
        points.length;
  }

  double _calculateStd(List<List<double>> points, int featureIndex) {
    if (points.isEmpty) return 0.0;
    double mean = _calculateMean(points, featureIndex);
    num sumSquaredDiff = points.map((p) =>
        pow(p[featureIndex] - mean, 2)).reduce((a, b) => a + b);
    return sqrt(sumSquaredDiff / points.length);
  }
}