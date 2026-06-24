import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
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

      // Check URL fragment for hash routing compatibility
      if (urlToken == null && uri.fragment.contains('token=')) {
        try {
          final frag = uri.fragment.startsWith('/')
              ? uri.fragment.substring(1)
              : uri.fragment;
          final fragUri = Uri.parse('?${frag.split('?').last}');
          urlToken = fragUri.queryParameters['token'];
        } catch (e) {
          debugPrint('⚠️ Error parsing token from URL fragment: $e');
        }
      }

      // 1️⃣ Mother Token exists in URL -> Process Exchange
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

    // 3️⃣ Try Microsoft silent token refresh (no OAuth popup)
    final prefs = await SharedPreferences.getInstance();
    final isMicrosoftLogin = prefs.getBool('is_microsoft_login') ?? false;
    final savedEmail = prefs.getString('email') ?? '';

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

    // 4️⃣ Check regular email/password session
    final savedPass = prefs.getString('password') ?? '';
    if (savedEmail.isNotEmpty && savedPass.isNotEmpty && !isMicrosoftLogin) {
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
