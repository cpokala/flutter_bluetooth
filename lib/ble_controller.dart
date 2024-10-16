import 'package:flutter/cupertino.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'dart:async';

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

  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  final List<ScanResult> _scanResultsList = [];
  Timer? pollingTimer;

  @override
  void onClose() {
    _scanResultsController.close();
    pollingTimer?.cancel();  // Stop the polling when the controller is closed
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
        startPolling();  // Start polling when the device is connected
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

    List<BluetoothService> services = await connectedDevice?.discoverServices() ?? [];

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
          (c) => c.uuid.toString().toLowerCase() == charUuid,
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
      airQualityVOC.value = "VOC: $voc ppb";

      if (vocData.length >= 50) vocData.removeAt(0);
      vocData.add(voc.toDouble());
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
      temperature.value = temp + extendedTemp / 100.0;
      pressure.value = (value[2] << 24 | value[3] << 16 | value[4] << 8 | value[5]).toDouble();

      // Update chart data
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
      logger.d("Battery Level: ${batteryLevel.value}");
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
      logger.d("PM Details: $pmDetails");
    } else {
      logger.e("Invalid PM Data Length: ${value.length}");
    }
  }
}
