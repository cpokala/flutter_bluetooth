import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'ble_controller.dart';

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

  Widget _buildClusterCard(int clusterId, List<EnvironmentalDataPoint> points) {
    double avgVoc = points.isEmpty ? 0 : points.map((p) => p.voc).reduce((a, b) => a + b) / points.length;
    double avgTemp = points.isEmpty ? 0 : points.map((p) => p.temperature).reduce((a, b) => a + b) / points.length;
    double avgHumidity = points.isEmpty ? 0 : points.map((p) => p.humidity).reduce((a, b) => a + b) / points.length;
    double avgPressure = points.isEmpty ? 0 : points.map((p) => p.pressure).reduce((a, b) => a + b) / points.length;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text('Cluster $clusterId'),
        subtitle: Text('${points.length} points'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Average VOC: ${avgVoc.toStringAsFixed(2)} ppb'),
                Text('Average Temperature: ${avgTemp.toStringAsFixed(2)} °C'),
                Text('Average Humidity: ${avgHumidity.toStringAsFixed(2)} %'),
                Text('Average Pressure: ${avgPressure.toStringAsFixed(2)} hPa'),
              ],
            ),
          ),
        ],
      ),
    );
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

            // Cluster Analysis Section
            Card(
              margin: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cluster Analysis',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => widget.controller.runDBSCANAnalysis(),
                        ),
                      ],
                    ),
                  ),
                  Obx(() {
                    if (widget.controller.clusterResults.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Collecting data for clustering analysis...',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      );
                    }
                    return Column(
                      children: widget.controller.clusterResults.entries
                          .map((entry) => _buildClusterCard(entry.key, entry.value))
                          .toList(),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // VOC Line Chart
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
                      dataLabelSettings: const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'VOC Levels Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorVOC,
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

            // Temperature Chart
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
                      dataLabelSettings: const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'Temperature Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorTemp,
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

            // Humidity Chart
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
                      xValueMapper: (double humidity, int index) => index.toDouble(),
                      yValueMapper: (double humidity, int index) => humidity,
                      name: 'Humidity',
                      dataLabelSettings: const DataLabelSettings(isVisible: true),
                    ),
                  ],
                  title: const ChartTitle(text: 'Humidity Over Time'),
                  legend: const Legend(isVisible: true),
                  tooltipBehavior: TooltipBehavior(enable: true),
                  zoomPanBehavior: _zoomPanBehaviorHumidity,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}