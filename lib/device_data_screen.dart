import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'ble_controller.dart'; // Import your BLE controller

class DeviceDataScreen extends StatelessWidget {
  final BleController controller;

  const DeviceDataScreen({required this.controller, super.key});

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
              final vocValue = controller.airQualityVOC.value;
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("VOC Level: $vocValue",
                    style: const TextStyle(fontSize: 18)),
              );
            }),
            const SizedBox(height: 20),

            // VOC Line Chart with Syncfusion
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
                      dataSource: controller.vocData.toList(),
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
                ),
              );
            }),

            const SizedBox(height: 20),

            // Temperature Section
            Obx(() {
              return Text("Temperature: ${controller.temperature.value} °C",
                  style: const TextStyle(fontSize: 18));
            }),
            const SizedBox(height: 20),

            // Temperature Line Chart
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
                      dataSource: controller.tempData.toList(),
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
                ),
              );
            }),

            const SizedBox(height: 20),

            // Humidity Section
            Obx(() {
              return Text("Humidity: ${controller.humidity.value} %",
                  style: const TextStyle(fontSize: 18));
            }),
            const SizedBox(height: 20),

            // Humidity Line Chart
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
                      dataSource: controller.humidityData.toList(),
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
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
