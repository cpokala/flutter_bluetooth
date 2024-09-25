import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'ble_controller.dart'; // Import your updated BleController
import 'device_data_screen.dart'; // Import your DeviceDataScreen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Flutter BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE SCANNER")),
      body: GetBuilder<BleController>(
        init: BleController(), // Initialize the BleController
        builder: (controller) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Device Scanning Section
                Expanded(
                  child: StreamBuilder<List<ScanResult>>(
                    stream: controller.scanResults,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final data = snapshot.data![index];
                            return Card(
                              elevation: 2,
                              child: ListTile(
                                title: Text(
                                  data.device.name.isNotEmpty ? data.device.name : "Unnamed Device",
                                ),
                                subtitle: Text(data.device.id.id),
                                trailing: Text(data.rssi.toString()),

                                // onTap logic to connect only to ATMOTUBE by name
                                onTap: () {
                                  if (data.device.name == "ATMOTUBE") {
                                    controller.connectToDevice(data.device, context);
                                    Get.to(() => DeviceDataScreen(controller: controller)); // Navigate to DeviceDataScreen
                                  } else {
                                    controller.connectToDevice(data.device, context);
                                  }
                                },
                              ),
                            );
                          },
                        );
                      } else {
                        return const Center(child: Text("No Devices Found"));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    controller.scanDevices();
                  },
                  child: const Text("SCAN"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
