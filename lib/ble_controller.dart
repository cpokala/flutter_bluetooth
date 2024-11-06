import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'dart:math';
import 'optimized_dbscan.dart';

class BleController extends GetxController {
  FlutterBlue ble = FlutterBlue.instance;
  BluetoothDevice? connectedDevice;
  var logger = Logger();

  // Observable variables for real-time data
  var airQualityVOC = RxString('VOC: 0 ppb');
  var temperature = RxDouble(0.0);
  var humidity = RxDouble(0.0);
  var batteryLevel = RxInt(0);
  var pmDetails = RxMap<String, double>();
  var pressure = RxDouble(0.0);

  // Historical data for line charts
  var vocData = <double>[].obs;
  var tempData = <double>[].obs;
  var humidityData = <double>[].obs;
  var pressureData = <double>[].obs;

  // Clustering data
  var environmentalDataPoints = <EnvironmentalDataPoint>[].obs;
  var clusterResults = RxMap<int, List<EnvironmentalDataPoint>>();
  var noisePoints = RxList<EnvironmentalDataPoint>();

  // DBSCAN parameters
  var epsilon = 0.3.obs;
  var minPoints = 4.obs;

  // Visualization controls
  var selectedXAxis = 'voc'.obs;
  var selectedYAxis = 'temperature'.obs;

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
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.bluetooth.request().isGranted) {
      if (await ble.isScanning.first) {
        return;
      }

      _scanResultsList.clear();
      ble.scan(timeout: const Duration(seconds: 50)).listen((result) {
        _scanResultsList.add(result);
        _scanResultsController.add(_scanResultsList);
      });

      await Future.delayed(const Duration(seconds: 50));
      ble.stopScan();
    } else {
      logger.e("Required permissions not granted.");
    }
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
  }

  Future<void> readCharacteristic(BluetoothService service, String charUuid, Function(List<int>) handler) async {
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
  }

  void _updateAirQuality(List<int> value) {
    logger.d("Air Quality data received: $value");
    if (value.length == 4) {
      final voc = (value[0] << 8) | value[1];
      airQualityVOC.value = "VOC: ${(voc / 10).toStringAsFixed(2)} ppb";

      if (vocData.length >= 50) vocData.removeAt(0);
      vocData.add((voc / 10).toDouble());

      addEnvironmentalDataPoint();
    } else {
      logger.e("Invalid Air Quality Data Length: ${value.length}");
    }
  }

  void _updateEnvironmental(List<int> value) {
    logger.d("Environmental data received: $value");
    if (value.length == 8) {
      humidity.value = value[0].toDouble();
      int temp = value[1];
      int extendedTemp = (value[6] << 8) | value[7];
      temperature.value = (temp + extendedTemp / 100.0) / 10.0;
      pressure.value = ((value[2] << 24) | (value[3] << 16) | (value[4] << 8) | value[5]) / 100.0;

      if (tempData.length >= 50) tempData.removeAt(0);
      tempData.add(temperature.value);

      if (humidityData.length >= 50) humidityData.removeAt(0);
      humidityData.add(humidity.value);

      if (pressureData.length >= 50) pressureData.removeAt(0);
      pressureData.add(pressure.value);
    } else {
      logger.e("Invalid Environmental Data Length: ${value.length}");
    }
  }

  void _updateStatus(List<int> value) {
    logger.d("Status data received: $value");
    if (value.length == 2) {
      batteryLevel.value = value[1];
    } else {
      logger.e("Invalid Status Data Length: ${value.length}");
    }
  }

  void _updatePM(List<int> value) {
    logger.d("PM data received: $value");
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
  }

  // DBSCAN related methods
  void runDBSCANAnalysis() {
    if (environmentalDataPoints.length < minPoints.value) {
      logger.i('Not enough data points for clustering (minimum ${minPoints.value} required)');
      return;
    }

    try {
      List<List<double>> points = environmentalDataPoints.map((point) => [
        point.voc,
        point.temperature,
        point.pressure,
        point.humidity,
      ]).toList();

      logger.d('Starting DBSCAN analysis with ${points.length} points');

      var dbscan = OptimizedDBSCAN(
        points: points,
        eps: epsilon.value,
        minPoints: minPoints.value,
      );

      Map<String, dynamic> results = dbscan.fit();

      final newClusterResults = <int, List<EnvironmentalDataPoint>>{};
      final clusters = results['clusters'] as Map<int, List<int>>;

      clusters.forEach((clusterId, pointIndices) {
        newClusterResults[clusterId] = pointIndices.map((index) {
          var point = environmentalDataPoints[index];
          return EnvironmentalDataPoint(
            voc: point.voc,
            temperature: point.temperature,
            pressure: point.pressure,
            humidity: point.humidity,
            timestamp: point.timestamp,
            clusterId: clusterId,
          );
        }).toList();

        var stats = (results['statistics'] as Map)[clusterId] as Map<String, double>;
        _logClusterStats(clusterId, stats);
      });

      final noiseIndices = results['noise_points'] as List<int>;
      final newNoisePoints = noiseIndices.map((index) {
        var point = environmentalDataPoints[index];
        return EnvironmentalDataPoint(
          voc: point.voc,
          temperature: point.temperature,
          pressure: point.pressure,
          humidity: point.humidity,
          timestamp: point.timestamp,
          clusterId: -1,
        );
      }).toList();

      clusterResults.value = newClusterResults;
      noisePoints.value = newNoisePoints;

      logger.i('DBSCAN Analysis Complete:');
      logger.i('Found ${clusters.length} clusters');
      logger.i('Noise points: ${noisePoints.length}');

      _analyzeEnvironmentalConditions(results['statistics'] as Map);

    } catch (e, stackTrace) {
      logger.e('Error during clustering: $e');
      logger.e(stackTrace.toString());
    }
  }

  void _logClusterStats(int clusterId, Map<String, double> stats) {
    logger.i('Cluster $clusterId Analysis:');
    logger.i('Size: ${stats['size']?.toInt()}');
    logger.i('VOC: ${stats['avg_voc']?.toStringAsFixed(2)} ± ${stats['std_voc']?.toStringAsFixed(2)} ppb');
    logger.i('Temperature: ${stats['avg_temperature']?.toStringAsFixed(2)} ± ${stats['std_temperature']?.toStringAsFixed(2)} °C');
    logger.i('Humidity: ${stats['avg_humidity']?.toStringAsFixed(2)} ± ${stats['std_humidity']?.toStringAsFixed(2)} %');
    logger.i('Pressure: ${stats['avg_pressure']?.toStringAsFixed(2)} ± ${stats['std_pressure']?.toStringAsFixed(2)} hPa');
  }

  void _analyzeEnvironmentalConditions(Map statistics) {
    statistics.forEach((clusterId, stats) {
      Map<String, double> clusterStats = stats as Map<String, double>;

      // Analyze measurements
      double avgVoc = clusterStats['avg_voc'] ?? 0;
      double avgTemp = clusterStats['avg_temperature'] ?? 0;
      double avgHumidity = clusterStats['avg_humidity'] ?? 0;

      if (avgVoc > 2000) {
        logger.w('High VOC levels in cluster $clusterId: $avgVoc ppb');
      }
      if (avgTemp > 30) {
        logger.w('High temperature in cluster $clusterId: $avgTemp °C');
      }
      if (avgHumidity > 70) {
        logger.w('High humidity in cluster $clusterId: $avgHumidity%');
      }

      _analyzeParameterCorrelations(clusterId);
    });
  }

  void _analyzeParameterCorrelations(int clusterId) {
    var clusterPoints = clusterId == -1 ?
    noisePoints : clusterResults[clusterId] ?? [];

    if (clusterPoints.length < 2) return;

    double vocTempCorr = _calculateCorrelation(
        clusterPoints.map((p) => p.voc).toList(),
        clusterPoints.map((p) => p.temperature).toList()
    );

    if (vocTempCorr.abs() > 0.7) {
      logger.i('Strong correlation (${vocTempCorr.toStringAsFixed(2)}) between VOC and Temperature in cluster $clusterId');
    }
  }

  double _calculateCorrelation(List<double> x, List<double> y) {
    if (x.length != y.length || x.isEmpty) return 0;

    double meanX = x.reduce((a, b) => a + b) / x.length;
    double meanY = y.reduce((a, b) => a + b) / y.length;

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

  void updateClusteringParameters({double? newEpsilon, int? newMinPoints}) {
    if (newEpsilon != null) epsilon.value = newEpsilon;
    if (newMinPoints != null) minPoints.value = newMinPoints;
    runDBSCANAnalysis();
  }

  void addEnvironmentalDataPoint() {
    final vocValue = double.tryParse(
        airQualityVOC.value.split(' ')[1]
    ) ?? 0.0;

    final dataPoint = EnvironmentalDataPoint(
      voc: vocValue,
      temperature: temperature.value,
      pressure: pressure.value,
      humidity: humidity.value,
    );

    environmentalDataPoints.add(dataPoint);

    if (environmentalDataPoints.length >= 30) {
      runDBSCANAnalysis();
    }
  }

  double getAxisValue(EnvironmentalDataPoint point, String axis) {
    switch (axis) {
      case 'voc':
        return point.voc;
      case 'temperature':
        return point.temperature;
      case 'pressure':
        return point.pressure;
      case 'humidity':
        return point.humidity;
      default:
        return 0.0;
    }
  }

  String getAxisUnit(String axis) {
    switch (axis) {
      case 'voc':
        return 'ppb';
      case 'temperature':
        return '°C';
      case 'pressure':
        return 'hPa';
      case 'humidity':
        return '%';
      default:
        return '';
    }
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
      'avgVoc': points.map((p) => p.voc).reduce((a, b) => a + b) / points.length,
      'avgTemperature': points.map((p) => p.temperature).reduce((a, b) => a + b) / points.length,
      'avgHumidity': points.map((p) => p.humidity).reduce((a, b) => a + b) / points.length,
      'avgPressure': points.map((p) => p.pressure).reduce((a, b) => a + b) / points.length,
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

    // Add some padding to the range
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
}