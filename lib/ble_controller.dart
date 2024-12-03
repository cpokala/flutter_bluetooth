import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'ml_service.dart';
import 'dart:async';
import 'dart:math';

class BleController extends GetxController {
  FlutterBlue ble = FlutterBlue.instance;
  BluetoothDevice? connectedDevice;
  final logger = Logger();

  // Observable variables for real-time data
  final airQualityVOC = RxString('VOC: 0 ppb');
  final temperature = RxDouble(0.0);
  final humidity = RxDouble(0.0);
  final batteryLevel = RxInt(0);
  final pmDetails = RxMap<String, double>();
  final pressure = RxDouble(0.0);

  // Historical data for line charts
  final vocData = <double>[].obs;
  final tempData = <double>[].obs;
  final humidityData = <double>[].obs;
  final pressureData = <double>[].obs;

  // Clustering data
  final environmentalDataPoints = <EnvironmentalDataPoint>[].obs;
  final clusterResults = RxMap<int, List<EnvironmentalDataPoint>>();
  final noisePoints = RxList<EnvironmentalDataPoint>();

  // Analysis state
  final isAnalyzing = false.obs;
  final analysisError = RxString('');

  // Visualization controls
  final selectedXAxis = 'voc'.obs;
  final selectedYAxis = 'temperature'.obs;

  // Maximum number of data points to store
  static const int maxDataPoints = 1000;

  // Cluster colors
  final clusterColors = [
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
  ];

  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;
  final List<ScanResult> _scanResultsList = [];
  Timer? pollingTimer;

  @override
  void onClose() {
    _scanResultsController.close();
    pollingTimer?.cancel();
    super.onClose();
  }

  Future<void> scanDevices() async {
    if (!await _checkPermissions()) {
      logger.e("Required permissions not granted.");
      return;
    }

    if (await ble.isScanning.first) return;

    _scanResultsList.clear();
    ble.scan(timeout: const Duration(seconds: 60)).listen((result) {
      _scanResultsList.add(result);
      _scanResultsController.add(_scanResultsList);
    });

    await Future.delayed(const Duration(seconds: 60));
    ble.stopScan();
  }

  Future<bool> _checkPermissions() async {
    var permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
    ];

    for (var permission in permissions) {
      if (!await permission.request().isGranted) {
        return false;
      }
    }
    return true;
  }

  Future<void> connectToDevice(BluetoothDevice device, BuildContext context) async {
    connectedDevice = device;
    var currentState = await device.state.first;

    if (currentState != BluetoothDeviceState.connected) {
      try {
        await device.connect(timeout: const Duration(seconds: 100));
      } on TimeoutException {
        logger.e("Connection timed out. Retrying...");
        await device.disconnect();
        return;
      }
    }

    device.state.listen((state) {
      if (state == BluetoothDeviceState.connecting) {
        logger.d("Device connecting to: ${device.name}");
      } else if (state == BluetoothDeviceState.connected) {
        logger.i("Device connected: ${device.name}");
        startPolling();
      } else {
        logger.w("Device Disconnected");
        stopPolling();
      }
    });
  }

  void startPolling() {
    pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      logger.d("Polling data from BLE device...");
      pollDeviceForData();
    });
  }

  void stopPolling() {
    pollingTimer?.cancel();
    logger.d("Stopped polling.");
  }

  Future<void> pollDeviceForData() async {
    if (connectedDevice == null) return;

    try {
      List<BluetoothService> services = await connectedDevice!.discoverServices();

      final service = services.firstWhereOrNull(
            (s) => s.uuid.toString().toLowerCase() == "db450001-8e9a-4818-add7-6ed94a328ab4".toLowerCase(),
      );

      if (service != null) {
        await readCharacteristic(service, "db450002-8e9a-4818-add7-6ed94a328ab4", _updateAirQuality);
        await readCharacteristic(service, "db450003-8e9a-4818-add7-6ed94a328ab4", _updateEnvironmental);
        await readCharacteristic(service, "db450004-8e9a-4818-add7-6ed94a328ab4", _updateStatus);
        await readCharacteristic(service, "db450005-8e9a-4818-add7-6ed94a328ab4", _updatePM);
      } else {
        logger.w("Service not found for polling");
      }
    } catch (e) {
      logger.e("Error polling device: $e");
    }
  }

  Future<void> readCharacteristic(BluetoothService service, String charUuid, Function(List<int>) handler) async {
    try {
      final characteristic = service.characteristics.firstWhereOrNull(
            (c) => c.uuid.toString().toLowerCase() == charUuid.toLowerCase(),
      );

      if (characteristic != null && characteristic.properties.read) {
        List<int> value = await characteristic.read();
        logger.d("Data read for characteristic: $charUuid, Data: $value");
        handler(value);
      } else {
        logger.w("Characteristic not found or read not supported: $charUuid");
      }
    } catch (e) {
      logger.e("Error reading characteristic $charUuid: $e");
    }
  }

  void _updateAirQuality(List<int> value) {
    try {
      if (value.length == 4) {
        final voc = (value[0] << 8) | value[1];
        airQualityVOC.value = "VOC: ${(voc / 10).toStringAsFixed(2)} ppb";

        if (vocData.length >= maxDataPoints) vocData.removeAt(0);
        vocData.add((voc / 10).toDouble());

        addEnvironmentalDataPoint();
      } else {
        logger.e("Invalid Air Quality Data Length: ${value.length}");
      }
    } catch (e) {
      logger.e("Error updating air quality: $e");
    }
  }

  void _updateEnvironmental(List<int> value) {
    try {
      if (value.length == 8) {
        humidity.value = value[0].toDouble();
        int temp = value[1];
        int extendedTemp = (value[6] << 8) | value[7];
        temperature.value = (temp + extendedTemp / 100.0) / 10.0;
        pressure.value = ((value[2] << 24) | (value[3] << 16) | (value[4] << 8) | value[5]) / 100.0;

        _updateHistoricalData();
      } else {
        logger.e("Invalid Environmental Data Length: ${value.length}");
      }
    } catch (e) {
      logger.e("Error updating environmental data: $e");
    }
  }

  void _updateHistoricalData() {
    if (tempData.length >= maxDataPoints) tempData.removeAt(0);
    tempData.add(temperature.value);

    if (humidityData.length >= maxDataPoints) humidityData.removeAt(0);
    humidityData.add(humidity.value);

    if (pressureData.length >= maxDataPoints) pressureData.removeAt(0);
    pressureData.add(pressure.value);
  }

  void _updateStatus(List<int> value) {
    try {
      if (value.length == 2) {
        batteryLevel.value = value[1];
      } else {
        logger.e("Invalid Status Data Length: ${value.length}");
      }
    } catch (e) {
      logger.e("Error updating status: $e");
    }
  }

  void _updatePM(List<int> value) {
    try {
      if (value.length == 12) {
        pmDetails.value = {
          "PM1": (value[0] << 8 | value[1]).toDouble(),
          "PM2.5": (value[2] << 8 | value[3]).toDouble(),
          "PM10": (value[4] << 8 | value[5]).toDouble(),
          "PM4": (value[6] << 8 | value[7]).toDouble(),
        };
      } else {
        logger.e("Invalid PM Data Length: ${value.length}");
      }
    } catch (e) {
      logger.e("Error updating PM data: $e");
    }
  }

  void addEnvironmentalDataPoint() {
    try {
      final vocValue = double.tryParse(airQualityVOC.value.split(' ')[1]) ?? 0.0;

      final dataPoint = EnvironmentalDataPoint(
        voc: vocValue,
        temperature: temperature.value,
        pressure: pressure.value,
        humidity: humidity.value,
      );

      if (environmentalDataPoints.length >= maxDataPoints) {
        environmentalDataPoints.removeAt(0);
      }

      environmentalDataPoints.add(dataPoint);

      // Run clustering when we have enough data points
      if (environmentalDataPoints.length >= 30) {
        runDBSCANAnalysis();
      }
    } catch (e) {
      logger.e("Error adding environmental data point: $e");
    }
  }

  Future<void> runDBSCANAnalysis() async {
    if (environmentalDataPoints.isEmpty) {
      logger.w('No data points available for analysis');
      return;
    }

    try {
      isAnalyzing.value = true;
      analysisError.value = '';

      final points = environmentalDataPoints.map((point) => [
        point.voc,
        point.temperature,
        point.pressure,
        point.humidity,
      ]).toList();

      final predictions = MlService.runClustering(points);

      _processClusteringResults(predictions);

    } catch (e, stackTrace) {
      logger.e('Error during clustering analysis: $e');
      logger.e(stackTrace.toString());
      analysisError.value = 'Analysis failed: ${e.toString()}';
    } finally {
      isAnalyzing.value = false;
    }
  }

  void _processClusteringResults(List<int> predictions) {
    final newClusterResults = <int, List<EnvironmentalDataPoint>>{};
    final newNoisePoints = <EnvironmentalDataPoint>[];

    for (int i = 0; i < predictions.length; i++) {
      final clusterId = predictions[i];
      final point = environmentalDataPoints[i];
      final newPoint = point.copyWith(clusterId: clusterId);

      if (clusterId == -1) {
        newNoisePoints.add(newPoint);
      } else {
        newClusterResults.putIfAbsent(clusterId, () => []).add(newPoint);
      }
    }

    clusterResults.value = newClusterResults;
    noisePoints.value = newNoisePoints;

    _calculateAndLogStatistics(newClusterResults, newNoisePoints);
  }

  void _calculateAndLogStatistics(
      Map<int, List<EnvironmentalDataPoint>> clusters,
      List<EnvironmentalDataPoint> noisePoints
      ) {
    clusters.forEach((clusterId, points) {
      final stats = _calculateClusterStats(points);
      logger.i('\nCluster $clusterId Analysis:');
      _logStats(stats, points.length);
    });

    if (noisePoints.isNotEmpty) {
      final stats = _calculateClusterStats(noisePoints);
      logger.i('\nNoise Points Analysis:');
      _logStats(stats, noisePoints.length);
    }
  }

  Map<String, double> _calculateClusterStats(List<EnvironmentalDataPoint> points) {
    if (points.isEmpty) return {};

    final stats = {
      'avg_voc': _calculateMean(points.map((p) => p.voc)),
      'avg_temperature': _calculateMean(points.map((p) => p.temperature)),
      'avg_pressure': _calculateMean(points.map((p) => p.pressure)),
      'avg_humidity': _calculateMean(points.map((p) => p.humidity)),
    };

    stats.addAll({
      'std_voc': _calculateStdDev(points.map((p) => p.voc), stats['avg_voc']!),
      'std_temperature': _calculateStdDev(points.map((p) => p.temperature), stats['avg_temperature']!),
      'std_pressure': _calculateStdDev(points.map((p) => p.pressure), stats['avg_pressure']!),
      'std_humidity': _calculateStdDev(points.map((p) => p.humidity), stats['avg_humidity']!),
    });

    return stats;
  }

  double _calculateMean(Iterable<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _calculateStdDev(Iterable<double> values, double mean) {
    final squaredDiffs = values.map((x) => pow(x - mean, 2));
    return sqrt(squaredDiffs.reduce((a, b) => a + b) / values.length);
  }

  void _logStats(Map<String, double> stats, int size) {
    logger.i('Size: $size points');
    logger.i('VOC: ${stats['avg_voc']?.toStringAsFixed(2)} ± ${stats['std_voc']?.toStringAsFixed(2)} ppb');
    logger.i('Temperature: ${stats['avg_temperature']?.toStringAsFixed(2)} ± ${stats['std_temperature']?.toStringAsFixed(2)} °C');
    logger.i('Pressure: ${stats['avg_pressure']?.toStringAsFixed(2)} ± ${stats['std_pressure']?.toStringAsFixed(2)} hPa');
    logger.i('Humidity: ${stats['avg_humidity']?.toStringAsFixed(2)} ± ${stats['std_humidity']?.toStringAsFixed(2)} %');
  }
  void clearData() {
    environmentalDataPoints.clear();
    clusterResults.clear();
    noisePoints.clear();
    vocData.clear();
    tempData.clear();
    humidityData.clear();
    pressureData.clear();
    airQualityVOC.value = 'VOC: 0 ppb';
    temperature.value = 0.0;
    humidity.value = 0.0;
    pressure.value = 0.0;
    batteryLevel.value = 0;
    pmDetails.clear();
    analysisError.value = '';
    isAnalyzing.value = false;
  }

  Color getClusterColor(int clusterId) {
    if (clusterId == -1) return Colors.grey;
    return clusterColors[clusterId % clusterColors.length];
  }

  double getAxisValue(EnvironmentalDataPoint point, String axis) {
    switch (axis) {
      case 'voc': return point.voc;
      case 'temperature': return point.temperature;
      case 'pressure': return point.pressure;
      case 'humidity': return point.humidity;
      default: return 0.0;
    }
  }

  String getAxisUnit(String axis) {
    switch (axis) {
      case 'voc': return 'ppb';
      case 'temperature': return '°C';
      case 'pressure': return 'hPa';
      case 'humidity': return '%';
      default: return '';
    }
  }

  Map<String, double> getClusterStatistics(List<EnvironmentalDataPoint> points) {
    if (points.isEmpty) {
      return {
        'avgVoc': 0.0,
        'avgTemperature': 0.0,
        'avgHumidity': 0.0,
        'avgPressure': 0.0,
      };
    }

    return {
      'avgVoc': _calculateMean(points.map((p) => p.voc)),
      'avgTemperature': _calculateMean(points.map((p) => p.temperature)),
      'avgHumidity': _calculateMean(points.map((p) => p.humidity)),
      'avgPressure': _calculateMean(points.map((p) => p.pressure)),
    };
  }

  Map<String, double> getAxisRange(String axisType) {
    List<EnvironmentalDataPoint> allPoints = [];
    clusterResults.forEach((_, points) {
      allPoints.addAll(points);
    });
    allPoints.addAll(noisePoints);

    if (allPoints.isEmpty) {
      return {'min': 0.0, 'max': 100.0}; // Default range
    }

    double minValue = double.infinity;
    double maxValue = double.negativeInfinity;

    for (var point in allPoints) {
      double value = getAxisValue(point, axisType);
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }

    // Add padding to the range (10%)
    double padding = (maxValue - minValue) * 0.1;
    return {
      'min': minValue - padding,
      'max': maxValue + padding,
    };
  }

  String exportClusterData() {
    StringBuffer buffer = StringBuffer();
    buffer.writeln('Cluster Analysis Report');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Total Points: ${environmentalDataPoints.length}');
    buffer.writeln('Number of Clusters: ${clusterResults.length}');
    buffer.writeln('Noise Points: ${noisePoints.length}');
    buffer.writeln('\n--- Cluster Details ---');

    clusterResults.forEach((clusterId, points) {
      buffer.writeln('\nCluster $clusterId:');
      var stats = getClusterStatistics(points);
      buffer.writeln('Size: ${points.length} points');
      buffer.writeln('Average VOC: ${stats['avgVoc']?.toStringAsFixed(2)} ppb');
      buffer.writeln('Average Temperature: ${stats['avgTemperature']?.toStringAsFixed(2)} °C');
      buffer.writeln('Average Humidity: ${stats['avgHumidity']?.toStringAsFixed(2)} %');
      buffer.writeln('Average Pressure: ${stats['avgPressure']?.toStringAsFixed(2)} hPa');

      if (points.isNotEmpty) {
        var timeRange = _getClusterTimeRange(points);
        buffer.writeln('Time Range: ${timeRange['start']} to ${timeRange['end']}');
      }
    });

    if (noisePoints.isNotEmpty) {
      buffer.writeln('\n--- Noise Points ---');
      var noiseStats = getClusterStatistics(noisePoints);
      buffer.writeln('Count: ${noisePoints.length}');
      buffer.writeln('Average VOC: ${noiseStats['avgVoc']?.toStringAsFixed(2)} ppb');
      buffer.writeln('Average Temperature: ${noiseStats['avgTemperature']?.toStringAsFixed(2)} °C');
      buffer.writeln('Average Humidity: ${noiseStats['avgHumidity']?.toStringAsFixed(2)} %');
      buffer.writeln('Average Pressure: ${noiseStats['avgPressure']?.toStringAsFixed(2)} hPa');
    }

    return buffer.toString();
  }

  Map<String, String> _getClusterTimeRange(List<EnvironmentalDataPoint> points) {
    var sortedPoints = List<EnvironmentalDataPoint>.from(points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return {
      'start': sortedPoints.first.timestamp.toString(),
      'end': sortedPoints.last.timestamp.toString(),
    };
  }

  Map<String, double> getFeatureCorrelations(List<EnvironmentalDataPoint> points) {
    if (points.length < 2) return {};

    var vocValues = points.map((p) => p.voc).toList();
    var tempValues = points.map((p) => p.temperature).toList();
    var humidityValues = points.map((p) => p.humidity).toList();
    var pressureValues = points.map((p) => p.pressure).toList();

    return {
      'voc_temperature': _calculateCorrelation(vocValues, tempValues),
      'voc_humidity': _calculateCorrelation(vocValues, humidityValues),
      'voc_pressure': _calculateCorrelation(vocValues, pressureValues),
      'temperature_humidity': _calculateCorrelation(tempValues, humidityValues),
      'temperature_pressure': _calculateCorrelation(tempValues, pressureValues),
      'humidity_pressure': _calculateCorrelation(humidityValues, pressureValues),
    };
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return 0;

    double meanX = _calculateMean(x);
    double meanY = _calculateMean(y);

    double covariance = 0;
    double varX = 0;
    double varY = 0;

    for (int i = 0; i < x.length; i++) {
      covariance += (x[i] - meanX) * (y[i] - meanY);
      varX += (x[i] - meanX) * (x[i] - meanX);
      varY += (y[i] - meanY) * (y[i] - meanY);
    }

    if (varX == 0 || varY == 0) return 0;
    return covariance / (sqrt(varX * varY));
  }
}

class EnvironmentalDataPoint {
  final double voc;
  final double temperature;
  final double pressure;
  final double humidity;
  final DateTime timestamp;
  final int? clusterId;

  EnvironmentalDataPoint({
    this.voc = 0.0,
    this.temperature = 0.0,
    this.pressure = 0.0,
    this.humidity = 0.0,
    DateTime? timestamp,
    this.clusterId,
  }) : timestamp = timestamp ?? DateTime.now();

  EnvironmentalDataPoint copyWith({
    double? voc,
    double? temperature,
    double? pressure,
    double? humidity,
    DateTime? timestamp,
    int? clusterId,
  }) {
    return EnvironmentalDataPoint(
      voc: voc ?? this.voc,
      temperature: temperature ?? this.temperature,
      pressure: pressure ?? this.pressure,
      humidity: humidity ?? this.humidity,
      timestamp: timestamp ?? this.timestamp,
      clusterId: clusterId ?? this.clusterId,
    );
  }
}