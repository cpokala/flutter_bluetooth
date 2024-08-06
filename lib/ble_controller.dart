import 'package:flutter_blue/flutter_blue.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'dart:async';

class BleController extends GetxController {
  FlutterBlue ble = FlutterBlue.instance;
  BluetoothDevice? connectedDevice;
  var logger = Logger();
  var airQualityVOC = RxString('');
  var temperature = RxDouble(0.0);
  var humidity = RxDouble(0.0);
  var batteryLevel = RxInt(0);
  var pmDetails = RxMap<String, double>();

  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  final List<ScanResult> _scanResultsList = [];

  @override
  void onClose() {
    _scanResultsController.close();
    super.onClose();
  }

  Future<void> scanDevices() async {
    if (await Permission.bluetoothScan.request().isGranted) {
      if (await Permission.bluetoothConnect.request().isGranted) {
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
      }
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
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
        setupListeners();
      } else {
        logger.w("Device Disconnected");
      }
    });
  }

  void setupListeners() {
    logger.d("Setting up listeners");
    connectedDevice?.discoverServices().then((services) {
      logDiscoveredServices(services);

      final service = services.firstWhereOrNull(
            (s) => s.uuid.toString().toLowerCase() == "db450001-8e9a-4818-add7-6ed94a328ab4".toLowerCase(),
      );
      if (service != null) {
        logger.d("Service discovered: ${service.uuid}");
        subscribeToCharacteristic(service, "db450002-8e9a-4818-add7-6ed94a328ab4".toLowerCase(), _updateAirQuality);
        subscribeToCharacteristic(service, "db450003-8e9a-4818-add7-6ed94a328ab4".toLowerCase(), _updateEnvironmental);
        subscribeToCharacteristic(service, "db450004-8e9a-4818-add7-6ed94a328ab4".toLowerCase(), _updateStatus);
        subscribeToCharacteristic(service, "db450005-8e9a-4818-add7-6ed94a328ab4".toLowerCase(), _updatePM);
      } else {
        logger.w("Service not found");
      }
    }).catchError((error) {
      logger.e("Error discovering services: $error");
    });
  }

  void logDiscoveredServices(List<BluetoothService> services) {
    for (var service in services) {
      logger.d("Service discovered: ${service.uuid}");
    }
  }

  void subscribeToCharacteristic(BluetoothService service, String charUuid, Function(List<int>) handler) {
    final characteristic = service.characteristics.firstWhereOrNull(
          (c) => c.uuid.toString().toLowerCase() == charUuid,
    );
    if (characteristic != null && characteristic.properties.notify) {
      logger.d("Subscribing to characteristic: ${characteristic.uuid}");
      characteristic.setNotifyValue(true).then((_) {
        logger.d("Notification set for characteristic: $charUuid");
        characteristic.value.listen((value) {
          logger.d("Data received for characteristic: $charUuid, Data: $value");
          handler(value);
        }).onError((error) {
          logger.e("Error listening to characteristic: $charUuid, error: $error");
        });
      }).catchError((error) {
        logger.e("Error setting notify value for characteristic: $charUuid, error: $error");
      });
    } else {
      logger.w("Characteristic not found or notify not supported: $charUuid");
    }
  }

  void _updateAirQuality(List<int> value) {
    logger.d("Air Quality data received: $value");
    if (value.length == 4) {
      final voc = (value[0] << 8) | value[1];
      airQualityVOC.value = "VOC: $voc ppb";
      logger.d("VOC: ${airQualityVOC.value}");
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
      // Pressure data is 4 bytes, need to handle properly if needed
      logger.d("Temperature: ${temperature.value}");
      logger.d("Humidity: ${humidity.value}");
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
