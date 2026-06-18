import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class AuthService {
  static const String _childTokenKey = 'child_token';
  static const String _motherTokenKey = 'mother_token';
  static const String _sessionDataKey = 'session_data';
  static const String _emailKey = 'email';

  static Future<Map<String, dynamic>?> exchangeToken(String motherToken) async {
    try {
      if (motherToken.isEmpty) {
        debugPrint('❌ Token Exchange Failed: motherToken is empty');
        return null;
      }

      final baseUrl = AppConfig.instance.baseUrl;
      final productCode = AppConfig.instance.productCode;

      debugPrint('🔄 Exchange Token Request to Email Backend:');
      debugPrint('   MotherToken length: ${motherToken.length}');

      final response = await http.post(
        Uri.parse("$baseUrl/am/exchange-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $motherToken",
        },
        body: jsonEncode({"productCode": productCode}),
      );

      debugPrint('🔄 Exchange Token Response Status: ${response.statusCode}');
      debugPrint('🔄 Exchange Token Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final exchangeData = jsonDecode(response.body);
        debugPrint('✅ Token Exchange Successful in Email App');
        return exchangeData;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Token Exchange Exception: $e');
      return null;
    }
  }

  static Future<bool> loginWithMotherToken(String motherToken) async {
    final exchangeResponse = await exchangeToken(motherToken);
    if (exchangeResponse == null) return false;

    final childToken = exchangeResponse['child_token'];
    final sessionData = exchangeResponse['session_data'];

    if (childToken == null || sessionData == null) {
      debugPrint('❌ Exchanged response is missing child_token or session_data');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_motherTokenKey, motherToken);
    await prefs.setString(_childTokenKey, childToken);
    await prefs.setString(_sessionDataKey, jsonEncode(sessionData));

    final email = sessionData['email']?.toString() ?? '';
    if (email.isNotEmpty) {
      await prefs.setString(_emailKey, email);
      debugPrint('✅ Saved user email to SharedPreferences: $email');
    }

    return true;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_motherTokenKey);
    await prefs.remove(_childTokenKey);
    await prefs.remove(_sessionDataKey);
    await prefs.remove(_emailKey);
    await prefs.remove('password');
    await prefs.remove('mail_password');
    debugPrint('✅ Session cleaned up on logout');
  }

  static Future<String?> getChildToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_childTokenKey);
  }

  static Future<String?> getMotherToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_motherTokenKey);
  }

  static Future<Map<String, dynamic>?> getSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_sessionDataKey);
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
