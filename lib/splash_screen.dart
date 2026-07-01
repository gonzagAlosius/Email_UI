import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config/app_config.dart';

import 'utils/web_helpers.dart';

import 'services/auth_service.dart';
import 'email_screen.dart';
import 'login_screen.dart';
import 'main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Small delay for smooth transition
    await Future.delayed(const Duration(milliseconds: 200));

    if (kIsWeb) {
      final uri = Uri.base;
      String? urlToken = uri.queryParameters['token'];
      String? urlProvider = uri.queryParameters['provider'];
      String? urlEmail = uri.queryParameters['email'];

      // Check URL fragment for hash routing compatibility
      if (urlToken == null && uri.fragment.contains('token=')) {
        try {
          final frag = uri.fragment.startsWith('/')
              ? uri.fragment.substring(1)
              : uri.fragment;
          final fragUri = Uri.parse('?${frag.split('?').last}');
          urlToken = fragUri.queryParameters['token'];
          urlProvider = fragUri.queryParameters['provider'];
          urlEmail = fragUri.queryParameters['email'];
        } catch (e) {
          debugPrint('⚠️ Error parsing token from URL fragment: $e');
        }
      }

      // 1️⃣ Backend OAuth Token exists (Google Login complete) -> Save and open inbox
      if (urlToken != null && urlToken.isNotEmpty && urlProvider == 'google' && urlEmail != null) {
        debugPrint('✅ Google login callback received. Navigating to Email Home...');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', urlEmail);
        await prefs.setString('password', urlToken);
        await prefs.setBool('is_google_login', true);
        await prefs.remove('is_microsoft_login');

        try {
          replaceUrlState('/#/');
        } catch (e) {
          debugPrint('⚠️ Could not replace URL history: $e');
        }

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
        );
        return;
      }

      // 2️⃣ Mother Token exists in URL -> Process Exchange
      if (urlToken != null && urlToken.isNotEmpty) {
        debugPrint('🔑 Found mother token in URL. Attempting exchange...');
        final success = await AuthService.loginWithMotherToken(urlToken);

        if (success) {
          debugPrint('✅ Token exchange success! Navigating to Email Home...');

          // Clean URL token for security and hygiene
          try {
            replaceUrlState('/#/');
          } catch (e) {
            debugPrint('⚠️ Could not replace URL history: $e');
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
          );
          return;
        } else {
          debugPrint('❌ Token exchange failed.');
        }
      }
    }

    // 2️⃣ Check child token (from mother token exchange)
    final childToken = await AuthService.getChildToken();
    if (!mounted) return;

    if (childToken != null && childToken.isNotEmpty) {
      debugPrint('✅ Active session found. Navigating to Email Home...');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
      );
      return;
    }

    // 4️⃣ Try Microsoft silent token refresh (no OAuth popup)
    final prefs = await SharedPreferences.getInstance();
    final isMicrosoftLogin = prefs.getBool('is_microsoft_login') ?? false;
    final isGoogleLogin = prefs.getBool('is_google_login') ?? false;
    final savedEmail = prefs.getString('email') ?? '';

    // Try Google silent token refresh via backend
    if (isGoogleLogin && savedEmail.isNotEmpty) {
      debugPrint('🔄 Google login detected. Attempting silent token refresh via backend...');
      try {
        final response = await http.post(
          Uri.parse('${AppConfig.instance.baseUrl}/auth/google/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': savedEmail}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['access_token'] != null) {
            await prefs.setString('password', data['access_token']);
            debugPrint('✅ Silent Google token refresh succeeded.');
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Silent Google refresh failed: $e');
      }
    }

    if (isMicrosoftLogin && savedEmail.isNotEmpty) {
      debugPrint('🔄 Microsoft login detected. Attempting silent token refresh...');
      try {
        final Config config = Config(
          tenant: 'common',
          clientId: '04b47bff-348d-41d1-829a-f4276486e287',
          scope: 'openid profile email https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access',
          redirectUri: AppConfig.redirectUri,
          navigatorKey: navigatorKey,
        );
        final AadOAuth oauth = AadOAuth(config);
        final String? freshToken = await oauth.getAccessToken();

        if (freshToken != null && freshToken.isNotEmpty) {
          await prefs.setString('password', freshToken);
          debugPrint('✅ Silent Microsoft token refresh succeeded. Navigating to Email Home...');
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
          );
          return;
        }
      } catch (e) {
        debugPrint('⚠️ Silent Microsoft refresh failed: $e');
      }
    }

    // 6️⃣ Check regular email/password session
    final savedPass = prefs.getString('password') ?? '';
    if (savedEmail.isNotEmpty && savedPass.isNotEmpty && !isMicrosoftLogin && !isGoogleLogin) {
      debugPrint('✅ Regular session found. Navigating to Email Home...');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
      );
      return;
    }

    debugPrint('ℹ️ No active session. Navigating to Login...');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF1A237E),
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Authenticating Workspace...',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF555555),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
