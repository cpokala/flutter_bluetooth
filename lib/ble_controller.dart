import 'package:flutter/cupertino.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'dart:math' show sqrt, pow, Point;

class CustomDBSCAN {
  final List<Point<double>> points;
  final double epsilon;
  final int minPoints;
  final List<List<int>> clusters = [];
  final List<int> noise = [];
  late List<bool> visited;  // Changed this line

  CustomDBSCAN(this.points, this.epsilon, this.minPoints) {
    // Initialize the visited list properly
    visited = List<bool>.filled(points.length, false);  // Changed this line
  }

  double _distance(Point<double> a, Point<double> b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  }

  List<int> _getNeighbors(int pointIndex) {
    List<int> neighbors = [];
    for (int i = 0; i < points.length; i++) {
      if (i != pointIndex && _distance(points[i], points[pointIndex]) <= epsilon) {
        neighbors.add(i);
      }
    }
    return neighbors;
  }

  void run() {
    clusters.clear();  // Clear previous clusters
    noise.clear();     // Clear previous noise

    for (int i = 0; i < points.length; i++) {
      if (visited[i]) continue;

      visited[i] = true;
      List<int> neighbors = _getNeighbors(i);

      if (neighbors.length < minPoints) {
        noise.add(i);
        continue;
      }

      List<int> currentCluster = [i];
      _expandCluster(neighbors, currentCluster);
      clusters.add(currentCluster);
    }
  }

  void _expandCluster(List<int> neighbors, List<int> currentCluster) {
    for (int i = 0; i < neighbors.length; i++) {
      int neighborIndex = neighbors[i];

      if (!visited[neighborIndex]) {
        visited[neighborIndex] = true;
        List<int> newNeighbors = _getNeighbors(neighborIndex);

        if (newNeighbors.length >= minPoints) {
          neighbors.addAll(newNeighbors.where((n) => !neighbors.contains(n)));
        }
      }

      if (!currentCluster.contains(neighborIndex)) {
        currentCluster.add(neighborIndex);
      }
    }
  }
}


class EnvironmentalDataPoint {
  final double voc;
  final double temperature;
  final double pressure;
  final double humidity;
  final DateTime timestamp;

  EnvironmentalDataPoint({
    this.voc = 0.0,
    this.temperature = 0.0,
    this.pressure = 0.0,
    this.humidity = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Point<double> toPoint() {
    return Point(
        voc / 1000.0,      // Normalize VOC (0-3000 ppb range)
        temperature / 50.0  // Normalize temperature (-20 to 50°C range)
    );
  }
}

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

  void runDBSCANAnalysis() {
    if (environmentalDataPoints.isEmpty) return;

    try {
      // Convert environmental data points to Point objects
      List<Point<double>> points = environmentalDataPoints
          .map((point) => point.toPoint())
          .toList();

      // Create and run custom DBSCAN with null safety
      var dbscan = CustomDBSCAN(points, 0.3, 4);
      dbscan.run();

      final clusters = dbscan.clusters;
      final noise = dbscan.noise;

      logger.i('Found clusters: ${clusters.length}');
      logger.i('Noise points: ${noise.length}');

      final newClusterResults = <int, List<EnvironmentalDataPoint>>{};

      // Process each cluster
      for (int i = 0; i < clusters.length; i++) {
        List<int> pointIndices = clusters[i];
        newClusterResults[i] = [];  // Initialize empty list
        for (int index in pointIndices) {
          if (index < environmentalDataPoints.length) {
            newClusterResults[i]!.add(environmentalDataPoints[index]);
          }
        }
      }

      clusterResults.value = newClusterResults;

      // Log cluster information
      clusterResults.forEach((clusterId, points) {
        if (points.isNotEmpty) {
          logger.i('Cluster $clusterId:');
          logger.i('Size: ${points.length}');
          logger.i('Avg VOC: ${points.map((p) => p.voc).reduce((a, b) => a + b) / points.length}');
          logger.i('Avg Temp: ${points.map((p) => p.temperature).reduce((a, b) => a + b) / points.length}');
          logger.i('Avg Humidity: ${points.map((p) => p.humidity).reduce((a, b) => a + b) / points.length}');
          logger.i('Avg Pressure: ${points.map((p) => p.pressure).reduce((a, b) => a + b) / points.length}');
        }
      });
    } catch (e, stackTrace) {
      logger.e('Error during clustering: $e');
      logger.e(stackTrace.toString());
    }
  }
}