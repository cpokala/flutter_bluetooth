import 'dart:convert';
import 'dart:ffi';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class EnvironmentalAnalysis {
  final String rawAnalysis;
  final String airQualityStatus;
  final List<String> healthImplications;
  final String comfortLevel;
  final List<String> recommendedActions;
  final Map<String, double> readings;
  final DateTime timestamp;

  EnvironmentalAnalysis({
    required this.rawAnalysis,
    required this.airQualityStatus,
    required this.healthImplications,
    required this.comfortLevel,
    required this.recommendedActions,
    required this.readings,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EnvironmentalAnalysis.fromRawAnalysis(
      String rawAnalysis,
      Map<String, double> readings,
      ) {
    final sections = _parseAnalysisSections(rawAnalysis);

    return EnvironmentalAnalysis(
      rawAnalysis: rawAnalysis,
      airQualityStatus: sections['Air Quality Status'] ?? 'Unknown',
      healthImplications: _parseList(sections['Health Implications']),
      comfortLevel: sections['Comfort Level'] ?? 'Unknown',
      recommendedActions: _parseList(sections['Recommended Actions']),
      readings: readings,
    );
  }

  static Map<String, String> _parseAnalysisSections(String analysis) {
    final Map<String, String> sections = {};
    final lines = analysis.split('\n');
    String currentSection = '';
    StringBuffer currentContent = StringBuffer();

    for (var line in lines) {
      if (line.contains('Air Quality Status') ||
          line.contains('Health Implications') ||
          line.contains('Comfort Level') ||
          line.contains('Recommended Actions')) {
        if (currentSection.isNotEmpty) {
          sections[currentSection] = currentContent.toString().trim();
          currentContent.clear();
        }
        currentSection = line.split(':')[0].trim();
      } else if (currentSection.isNotEmpty) {
        currentContent.writeln(line.trim());
      }
    }

    if (currentSection.isNotEmpty) {
      sections[currentSection] = currentContent.toString().trim();
    }

    return sections;
  }

  static List<String> _parseList(String? content) {
    if (content == null) return [];
    return content
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.replaceAll(RegExp(r'^\d+\.\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'rawAnalysis': rawAnalysis,
    'airQualityStatus': airQualityStatus,
    'healthImplications': healthImplications,
    'comfortLevel': comfortLevel,
    'recommendedActions': recommendedActions,
    'readings': readings,
    'timestamp': timestamp.toIso8601String(),
  };
}

class PhiService {
  static final _logger = Logger();
  static Map<String, dynamic>? _vocabulary;
  static Map<String, dynamic>? _preprocessorConfig;
  static Map<String, dynamic>? _envConfig;
  static bool _initialized = false;
  static const int _maxLength = 512;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load configurations
      _vocabulary = json.decode(
          await rootBundle.loadString('assets/phi_model/vocabulary.json')
      );

      _preprocessorConfig = json.decode(
          await rootBundle.loadString('assets/phi_model/preprocessor_config.json')
      );

      _envConfig = json.decode(
          await rootBundle.loadString('assets/phi_model/env_analysis_config.json')
      );

      // Initialize ONNX runtime (this is a placeholder - implement based on your ONNX runtime setup)
      // await _initializeOnnxRuntime();

      _initialized = true;
      _logger.i('Phi Service initialized successfully');
    } catch (e) {
      _logger.e('Error initializing Phi Service: $e');
      rethrow;
    }
  }

  static Future<EnvironmentalAnalysis> analyzeEnvironmentalData({
    required double voc,
    required double temperature,
    required double humidity,
    required double pressure,
    Map<String, double>? pm,
  }) async {
    if (!_initialized) {
      throw Exception('Phi Service not initialized');
    }

    try {
      final readings = {
        'voc': voc,
        'temperature': temperature,
        'humidity': humidity,
        'pressure': pressure,
        if (pm != null) ...pm,
      };

      // Format readings
      final readingsText = readings.entries
          .map((e) => '${e.key}: ${e.value}${_getUnit(e.key)}')
          .join('\n');

      // Create prompt using template
      final prompt = _envConfig!['prompt_template']
          .toString()
          .replaceAll('{readings}', readingsText);

      // Run model inference
      final analysis = await _runInference(prompt);

      return EnvironmentalAnalysis.fromRawAnalysis(analysis, readings);
    } catch (e) {
      _logger.e('Error analyzing environmental data: $e');
      rethrow;
    }
  }

  static String _getUnit(String metric) {
    switch (metric.toLowerCase()) {
      case 'voc':
        return ' ppb';
      case 'temperature':
        return '°C';
      case 'humidity':
        return '%';
      case 'pressure':
        return ' hPa';
      default:
        return metric.toLowerCase().startsWith('pm') ? ' µg/m³' : '';
    }
  }

  static Future<String> _runInference(String prompt) async {
    // This is a placeholder - implement actual ONNX inference
    // You'll need to:
    // 1. Tokenize the input
    // 2. Run the ONNX model
    // 3. Process the output
    throw UnimplementedError('ONNX inference not implemented yet');
  }
}