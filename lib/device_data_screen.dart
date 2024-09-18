import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:fl_chart/fl_chart.dart';
import 'ble_controller.dart';

class DeviceDataScreen extends StatelessWidget {
  final BleController controller;

  const DeviceDataScreen({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Air Quality Data")),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Obx(() {
                final vocValue = controller.airQualityVOC.value;
                return Text("VOC Level: $vocValue");
              }),
              const SizedBox(height: 20),

              // VOC Line Chart
              Obx(() {
                return SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: controller.vocData.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value);
                          }).toList(),
                          isCurved: true,
                          barWidth: 3,
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),

              Obx(() {
                return Text("Temperature: ${controller.temperature.value} °C");
              }),

              // Temperature Line Chart
              Obx(() {
                return SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: controller.tempData.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value);
                          }).toList(),
                          isCurved: true,
                          barWidth: 3,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 20),

              Obx(() {
                return Text("Humidity: ${controller.humidity.value} %");
              }),

              // Humidity Line Chart
              Obx(() {
                return SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: controller.humidityData.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value);
                          }).toList(),
                          isCurved: true,
                          barWidth: 3,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
