import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'ble_controller.dart';
import 'package:share_plus/share_plus.dart';

class ClusteringControls extends StatelessWidget {
  final BleController controller;

  const ClusteringControls({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Clustering Analysis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Obx(() => controller.isAnalyzing.value
                    ? const CircularProgressIndicator()
                    : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: controller.runDBSCANAnalysis,
                ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Status and information
            Obx(() => controller.analysisError.value.isNotEmpty
                ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                controller.analysisError.value,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            )
                : const Text(
              'Clustering parameters are automatically optimized based on the data distribution.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }
}


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
  late ZoomPanBehavior _zoomPanBehaviorPressure;
  late ZoomPanBehavior _zoomPanBehaviorScatter;
  late TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _initializeChartBehaviors();
  }

  void _initializeChartBehaviors() {
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
    _zoomPanBehaviorPressure = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );
    _zoomPanBehaviorScatter = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
    );
    _tooltipBehavior = TooltipBehavior(
      enable: true,
      format: 'point.x : point.y',
    );
  }

  Widget _buildConnectionStatus() {
    return Obx(() {
      final isConnected = widget.controller.connectedDevice != null;
      final isConnecting = widget.controller.isConnecting.value;
      final connectionError = widget.controller.connectionError.value;

      return Card(
        margin: const EdgeInsets.all(8),
        color: isConnected ? Colors.green.shade50 : Colors.grey.shade100,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isConnected
                    ? Icons.bluetooth_connected
                    : (isConnecting ? Icons.bluetooth_searching : Icons.bluetooth_disabled),
                color: isConnected
                    ? Colors.green
                    : (isConnecting ? Colors.blue : Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConnected
                          ? 'Connected to ${widget.controller.connectedDevice?.platformName}'
                          : (isConnecting ? 'Connecting...' : 'Disconnected'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (connectionError.isNotEmpty)
                      Text(
                        connectionError,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (isConnected)
                TextButton.icon(
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect'),
                  onPressed: () {
                    widget.controller.disconnectDevice();
                  },
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildScatterPlot() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: GetX<BleController>( // Wrap with GetX
                    builder: (_) => DropdownButtonFormField<String>(
                      value: widget.controller.selectedXAxis.value,
                      decoration: const InputDecoration(
                        labelText: 'X Axis',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'voc', child: Text('VOC')),
                        DropdownMenuItem(value: 'temperature', child: Text('Temperature')),
                        DropdownMenuItem(value: 'pressure', child: Text('Pressure')),
                        DropdownMenuItem(value: 'humidity', child: Text('Humidity')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          widget.controller.selectedXAxis.value = value;
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GetX<BleController>( // Wrap with GetX
                    builder: (_) => DropdownButtonFormField<String>(
                      value: widget.controller.selectedYAxis.value,
                      decoration: const InputDecoration(
                        labelText: 'Y Axis',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'temperature', child: Text('Temperature')),
                        DropdownMenuItem(value: 'voc', child: Text('VOC')),
                        DropdownMenuItem(value: 'pressure', child: Text('Pressure')),
                        DropdownMenuItem(value: 'humidity', child: Text('Humidity')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          widget.controller.selectedYAxis.value = value;
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            child: GetX<BleController>( // Wrap with GetX
              builder: (_) {
                List<ScatterSeries<EnvironmentalDataPoint, double>> series = [];

                widget.controller.clusterResults.forEach((clusterId, points) {
                  series.add(
                    ScatterSeries<EnvironmentalDataPoint, double>(
                      name: 'Cluster $clusterId',
                      dataSource: points,
                      xValueMapper: (EnvironmentalDataPoint point, _) =>
                          widget.controller.getAxisValue(point, widget.controller.selectedXAxis.value),
                      yValueMapper: (EnvironmentalDataPoint point, _) =>
                          widget.controller.getAxisValue(point, widget.controller.selectedYAxis.value),
                      color: widget.controller.getClusterColor(clusterId),
                      markerSettings: const MarkerSettings(height: 8, width: 8),
                      dataLabelSettings: const DataLabelSettings(isVisible: false),
                    ),
                  );
                });

                if (widget.controller.noisePoints.isNotEmpty) {
                  series.add(
                    ScatterSeries<EnvironmentalDataPoint, double>(
                      name: 'Noise',
                      dataSource: widget.controller.noisePoints.toList(),
                      xValueMapper: (EnvironmentalDataPoint point, _) =>
                          widget.controller.getAxisValue(point, widget.controller.selectedXAxis.value),
                      yValueMapper: (EnvironmentalDataPoint point, _) =>
                          widget.controller.getAxisValue(point, widget.controller.selectedYAxis.value),
                      color: Colors.grey,
                      markerSettings: const MarkerSettings(height: 6, width: 6),
                    ),
                  );
                }

                Map<String, double> xRange = widget.controller.getAxisRange(widget.controller.selectedXAxis.value);
                Map<String, double> yRange = widget.controller.getAxisRange(widget.controller.selectedYAxis.value);

                return SfCartesianChart(
                  primaryXAxis: NumericAxis(
                    title: AxisTitle(
                      text: '${widget.controller.selectedXAxis.value.toUpperCase()} '
                          '(${widget.controller.getAxisUnit(widget.controller.selectedXAxis.value)})',
                    ),
                    minimum: xRange['min'],
                    maximum: xRange['max'],
                  ),
                  primaryYAxis: NumericAxis(
                    title: AxisTitle(
                      text: '${widget.controller.selectedYAxis.value.toUpperCase()} '
                          '(${widget.controller.getAxisUnit(widget.controller.selectedYAxis.value)})',
                    ),
                    minimum: yRange['min'],
                    maximum: yRange['max'],
                  ),
                  series: series,
                  title: const ChartTitle(text: 'Cluster Analysis'),
                  legend: const Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                  ),
                  tooltipBehavior: _tooltipBehavior,
                  zoomPanBehavior: _zoomPanBehaviorScatter,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClusterCard(int clusterId, List<EnvironmentalDataPoint> points) {
    // Null safety checks
    if (points.isEmpty) return const SizedBox.shrink();

    final color = widget.controller.getClusterColor(clusterId);
    final stats = widget.controller.getClusterStatistics(points);
    final correlations = widget.controller.getFeatureCorrelations(points);

    // Null-safe access with default values
    final avgVoc = stats['avgVoc'] ?? 0.0;
    final avgTemp = stats['avgTemperature'] ?? 0.0;
    final avgHumidity = stats['avgHumidity'] ?? 0.0;
    final avgPressure = stats['avgPressure'] ?? 0.0;

    // Null-safe correlation access
    final vocTemp = correlations['voc_temperature'] ?? 0.0;
    final vocHumidity = correlations['voc_humidity'] ?? 0.0;
    final vocPressure = correlations['voc_pressure'] ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color,
          radius: 12,
        ),
        title: Text(clusterId >= 0 ? 'Cluster $clusterId' : 'Noise Points'),
        subtitle: Text('${points.length} points'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow('VOC', avgVoc, 'ppb'),
                _buildStatRow('Temperature', avgTemp, '°C'),
                _buildStatRow('Humidity', avgHumidity, '%'),
                _buildStatRow('Pressure', avgPressure, 'hPa'),
                const SizedBox(height: 8),
                const Divider(),
                const Text('Correlations:', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildCorrelationRow('VOC-Temperature', vocTemp),
                _buildCorrelationRow('VOC-Humidity', vocHumidity),
                _buildCorrelationRow('VOC-Pressure', vocPressure),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: points.length / widget.controller.environmentalDataPoints.length,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(points.length / widget.controller.environmentalDataPoints.length * 100).toStringAsFixed(1)}% of total points',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, double value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text('${value.toStringAsFixed(2)} $unit'),
        ],
      ),
    );
  }

  Widget _buildCorrelationRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value.toStringAsFixed(3)),
        ],
      ),
    );
  }

  Widget _buildLineChart({
    required String title,
    required RxList<double> data,
    required String yAxisTitle,
    required ZoomPanBehavior zoomPanBehavior,
  }) {
    return GetX<BleController>( // Wrap with GetX
      builder: (_) => SizedBox(
        height: 300,
        child: SfCartesianChart(
          primaryXAxis: const NumericAxis(
            title: AxisTitle(text: 'Time (s)'),
          ),
          primaryYAxis: NumericAxis(
            title: AxisTitle(text: yAxisTitle),
          ),
          series: <LineSeries<double, double>>[
            LineSeries<double, double>(
              dataSource: data.toList(), // Convert RxList to List
              xValueMapper: (double value, int index) => index.toDouble(),
              yValueMapper: (double value, _) => value,
              name: title,
              dataLabelSettings: const DataLabelSettings(isVisible: false),
            ),
          ],
          title: ChartTitle(text: title),
          legend: const Legend(isVisible: true),
          tooltipBehavior: TooltipBehavior(enable: true),
          zoomPanBehavior: zoomPanBehavior,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Quality Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Store context in a local variable
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final report = widget.controller.exportClusterData();

              // Use the stored context reference
              Share.share(
                report,
                subject: 'Cluster Analysis Report ${DateTime.now().toString().split('.')[0]}',
              ).catchError((error) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to share report: $error'),
                    backgroundColor: Colors.red,
                  ),
                );
                return null;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Connection Status
            _buildConnectionStatus(),

            // Current Values Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current Readings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Obx(() => Column(
                      children: [
                        Text(widget.controller.airQualityVOC.value),
                        Text('Temperature: ${widget.controller.temperature.value.toStringAsFixed(2)} °C'),
                        Text('Humidity: ${widget.controller.humidity.value.toStringAsFixed(2)} %'),
                        Text('Pressure: ${widget.controller.pressure.value.toStringAsFixed(2)} hPa'),
                        if (widget.controller.batteryLevel.value > 0)
                          Text('Battery: ${widget.controller.batteryLevel.value}%'),
                        if (widget.controller.pmDetails.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text('Particulate Matter:'),
                          ...widget.controller.pmDetails.entries.map(
                                (e) => Text('${e.key}: ${e.value.toStringAsFixed(1)} µg/m³'),
                          ),
                        ],
                      ],
                    )),
                  ],
                ),
              ),
            ),

            // Clustering Controls
            ClusteringControls(controller: widget.controller),

            // Clustering Analysis Section
            _buildScatterPlot(),

            // Cluster Statistics Section
            Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Cluster Analysis',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${widget.controller.environmentalDataPoints.length} total points',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Obx(() {
                    if (widget.controller.clusterResults.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Collecting data for clustering analysis...',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        ...widget.controller.clusterResults.entries
                            .map((entry) => _buildClusterCard(entry.key, entry.value)),
                        if (widget.controller.noisePoints.isNotEmpty)
                          _buildClusterCard(-1, widget.controller.noisePoints),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // Historical Data Charts
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Historical Data',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _buildLineChart(
                    title: 'VOC Levels',
                    data: widget.controller.vocData,
                    yAxisTitle: 'VOC (ppb)',
                    zoomPanBehavior: _zoomPanBehaviorVOC,
                  ),
                  const SizedBox(height: 20),
                  _buildLineChart(
                    title: 'Temperature',
                    data: widget.controller.tempData,
                    yAxisTitle: 'Temperature (°C)',
                    zoomPanBehavior: _zoomPanBehaviorTemp,
                  ),
                  const SizedBox(height: 20),
                  _buildLineChart(
                    title: 'Humidity',
                    data: widget.controller.humidityData,
                    yAxisTitle: 'Humidity (%)',
                    zoomPanBehavior: _zoomPanBehaviorHumidity,
                  ),
                  const SizedBox(height: 20),
                  _buildLineChart(
                    title: 'Pressure',
                    data: widget.controller.pressureData,
                    yAxisTitle: 'Pressure (hPa)',
                    zoomPanBehavior: _zoomPanBehaviorPressure,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          widget.controller.clearData();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data cleared')),
          );
        },
        tooltip: 'Clear Data',
        child: const Icon(Icons.clear_all),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}