import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'ble_controller.dart'; // Import your BLE controller

class DeviceDataScreen extends StatefulWidget {
  final BleController controller;

  const DeviceDataScreen({required this.controller, super.key});

  @override
  DeviceDataScreenState createState() => DeviceDataScreenState();
}

class DeviceDataScreenState extends State<DeviceDataScreen> {
  late ZoomPanBehavior _zoomPanBehaviorVOC;
  late ZoomPanBehavior _zoomPanBehaviorTemp;
  late ZoomPanBehavior _zoomPanBehaviorHumidity;

  @override
  void initState() {
    // Initialize ZoomPanBehavior with pinch zoom enabled for each chart
    _zoomPanBehaviorVOC = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );

    _zoomPanBehaviorTemp = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );

    _zoomPanBehaviorHumidity = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Quality Data'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // VOC level section
            Obx(() {
              final vocValue = widget.controller.airQualityVOC.value;
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("VOC Level: $vocValue",
                    style: const TextStyle(fontSize: 18)),
              );
            }),
            const SizedBox(height: 20),

            // VOC Line Chart with Syncfusion and pinch zoom enabled
            Obx(() {
              return SizedBox(
                height: 300,
                child: SfCartesianChart(
                  primaryXAxis: const NumericAxis(
                    title: AxisTitle(text: 'Time (s)'),
                  ),
                  primaryYAxis: const NumericAxis(
                    title: AxisTitle(text: 'VOC Level (ppb)'),
                  ),
                  series: <LineSeries<double, double>>[
                    LineSeries<double, double>(
                      dataSource: widget.controller.vocData.toList(),
                      xValueMapper: (double voc, int index) => index.toDouble(),
                      yValueMapper: (double voc, int index) => voc,
                      name: 'VOC',
                      dataLabelSettings:
                      const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'VOC Levels Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorVOC, // Enable pinch zoom and panning
                ),
              );
            }),

            const SizedBox(height: 20),

            // Temperature Section
            Obx(() {
              return Text("Temperature: ${widget.controller.temperature.value} °C",
                  style: const TextStyle(fontSize: 18));
            }),
            const SizedBox(height: 20),

            // Temperature Line Chart with Syncfusion and pinch zoom enabled
            Obx(() {
              return SizedBox(
                height: 300,
                child: SfCartesianChart(
                  primaryXAxis: const NumericAxis(
                    title: AxisTitle(text: 'Time (s)'),
                  ),
                  primaryYAxis: const NumericAxis(
                    title: AxisTitle(text: 'Temperature (°C)'),
                  ),
                  series: <LineSeries<double, double>>[
                    LineSeries<double, double>(
                      dataSource: widget.controller.tempData.toList(),
                      xValueMapper: (double temp, int index) => index.toDouble(),
                      yValueMapper: (double temp, int index) => temp,
                      name: 'Temperature',
                      dataLabelSettings:
                      const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'Temperature Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorTemp, // Enable pinch zoom and panning
                ),
              );
            }),

            const SizedBox(height: 20),

            // Humidity Section
            Obx(() {
              return Text("Humidity: ${widget.controller.humidity.value} %",
                  style: const TextStyle(fontSize: 18));
            }),
            const SizedBox(height: 20),

            // Humidity Line Chart with Syncfusion and pinch zoom enabled
            Obx(() {
              return SizedBox(
                height: 300,
                child: SfCartesianChart(
                  primaryXAxis: const NumericAxis(
                    title: AxisTitle(text: 'Time (s)'),
                  ),
                  primaryYAxis: const NumericAxis(
                    title: AxisTitle(text: 'Humidity (%)'),
                  ),
                  series: <LineSeries<double, double>>[
                    LineSeries<double, double>(
                      dataSource: widget.controller.humidityData.toList(),
                      xValueMapper: (double humidity, int index) =>
                          index.toDouble(),
                      yValueMapper: (double humidity, int index) => humidity,
                      name: 'Humidity',
                      dataLabelSettings:
                      const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'Humidity Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorHumidity, // Enable pinch zoom and panning
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}