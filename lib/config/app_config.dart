import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
 
class AppConfig {
  final String baseUrl;
  final String calendarUrl;
  final int productCode;
  AppConfig._({required this.baseUrl, required this.calendarUrl, required this.productCode,});
 
  static AppConfig? _instance;
 
  static Future<AppConfig> getInstance() async {
    if (_instance != null) return _instance!;
 
    Map<String, dynamic> data;
 
    if (kIsWeb) {
      final response = await http.get(Uri.parse('./config.json'));
      data = json.decode(response.body);
    } else {
      final jsonString = await rootBundle.loadString('assets/config/local.json');
      data = json.decode(jsonString);
    }
 
    _instance = AppConfig._(
      baseUrl: _determineBaseUrl(data['baseUrl']),
      calendarUrl: _determineBaseUrl(data['calendarUrl'] ?? data['baseUrl'].replaceAll('8081', '8080')),
      productCode: data['productCode'],
    );
 
    return _instance!;
  }
 
  static String _determineBaseUrl(String configUrl) {
    if (!kIsWeb) return _fixLocalhost(configUrl);
    
    final currentUri = Uri.base;
    final host = currentUri.host.toLowerCase();
    
    // If running on localhost/127.0.0.1, keep the configured URL
    if (host == 'localhost' || host == '127.0.0.1' || host.startsWith('192.168.')) {
      return configUrl;
    }
    
    // If running in production (e.g. Azure), but config.json already has a non-localhost URL, use it
    if (!configUrl.contains('localhost') && !configUrl.contains('127.0.0.1')) {
      return configUrl;
    }
    
    // Otherwise, dynamically guess the backend API URL based on standard naming conversions
    String productionHost = currentUri.host;
    if (productionHost.contains('-frontend')) {
      productionHost = productionHost.replaceAll('-frontend', '-backend');
    } else if (productionHost.contains('frontend')) {
      productionHost = productionHost.replaceAll('frontend', 'backend');
    } else if (productionHost.contains('-ui')) {
      productionHost = productionHost.replaceAll('-ui', '-backend');
    } else if (productionHost.contains('ui')) {
      productionHost = productionHost.replaceAll('ui', 'backend');
    } else {
      return '${currentUri.scheme}://${currentUri.host}/api';
    }
    
    return '${currentUri.scheme}://$productionHost/api';
  }

  static String _fixLocalhost(String url) {
    if (kIsWeb) return url;
    return url.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
  }

  static String get redirectUri {
    if (!kIsWeb) return 'http://localhost:8085';
    final currentUri = Uri.base;
    final portStr = (currentUri.port == 0 || currentUri.port == 80 || currentUri.port == 443) 
        ? '' 
        : ':${currentUri.port}';
    return '${currentUri.scheme}://${currentUri.host}$portStr';
  }
 
  static AppConfig get instance {
    if (_instance == null) {
      throw Exception('AppConfig not initialized. Call getInstance() first.');
    }
    return _instance!;
  }
}
