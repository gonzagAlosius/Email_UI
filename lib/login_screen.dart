import 'package:flutter/material.dart';
import 'signup_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_screen.dart';
import 'config/app_config.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'main.dart';
import 'services/notification_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'utils/web_helpers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure = true;

  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('email');
    final isMicrosoftLogin = prefs.getBool('is_microsoft_login') ?? false;

    if (savedEmail != null && savedEmail.isNotEmpty) {
      if (isMicrosoftLogin) {
        // Try silent Microsoft token refresh — no OAuth popup if refresh token is cached
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
            debugPrint('✅ Silent Microsoft token refresh succeeded.');
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
              );
            }
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Silent Microsoft refresh failed: $e');
        }
        // Silent refresh failed — show login screen (full OAuth will be required)
        return;
      } else {
        // Regular email/password login
        final savedPass = prefs.getString('password');
        if (savedPass != null && savedPass.isNotEmpty) {
          if (mounted) {
            setState(() {
              _emailController.text = savedEmail;
              _passwordController.text = savedPass;
            });
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) _login();
            });
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    if (email.isEmpty || pass.isEmpty) {
      _snack('Please fill all fields', true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': pass}),
      );
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', email);
        await prefs.setString('password', pass);
        await prefs.remove('is_microsoft_login');
        await prefs.remove('is_google_login');
        // Register this device for push notifications
        await _registerDeviceForPush(email);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
          );
        }
      } else {
        _snack('Invalid email or password', true);
      }
    } catch (_) {
      _snack('Connection error. Is the server running?', true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    if (kIsWeb) {
      final redirectUrl = Uri.base.toString().split('?').first.split('#').first;
      String baseUrl = AppConfig.instance.baseUrl;
      if (baseUrl.endsWith('/api')) baseUrl = baseUrl.substring(0, baseUrl.length - 4);
      final backendAuthUrl = '$baseUrl/oauth/google/login?redirect=$redirectUrl';
      redirectTo(backendAuthUrl);
      return;
    }
    
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: '497665028004-3d7sq2e5096d1bsacfgmpdje7je8npee.apps.googleusercontent.com',
        scopes: [
          'email',
          'https://mail.google.com/', // Scope for full IMAP/SMTP access
        ],
      );
      
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final GoogleSignInAuthentication googleAuth = await account.authentication;
      final String? accessToken = googleAuth.accessToken;
      
      if (accessToken == null) {
        _snack('Failed to get access token from Google', true);
        setState(() => _isLoading = false);
        return;
      }

      final email = account.email;
      
      final res = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': accessToken}),
      );
      
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', email);
        await prefs.setString('password', accessToken);
        await prefs.setBool('is_google_login', true);
        await prefs.remove('is_microsoft_login');
        // Register this device for push notifications
        await _registerDeviceForPush(email);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
          );
        }
      } else {
        _snack('Server authorization failed with Google token', true);
      }
    } catch (e) {
      _snack('Google Sign-In Error: $e', true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithMicrosoft() async {
    setState(() => _isLoading = true);
    try {
      final Config config = Config(
        tenant: 'common',
        clientId: '04b47bff-348d-41d1-829a-f4276486e287',
        scope: 'openid profile email https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access',
        redirectUri: AppConfig.redirectUri,
        navigatorKey: navigatorKey,
        customParameters: {'prompt': 'select_account'},
      );

      final AadOAuth oauth = AadOAuth(config);
      try {
        await oauth.login();
      } catch (e) {
        debugPrint('Ignored JS cast error during login: $e');
      }
      final String? accessToken = await oauth.getAccessToken();

      if (accessToken == null) {
        _snack('Failed to get access token from Microsoft', true);
        setState(() => _isLoading = false);
        return;
      }

      String email = "";
      final String? idToken = await oauth.getIdToken();
      if (idToken != null) {
        try {
          final parts = idToken.split('.');
          if (parts.length > 1) {
            final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
            final Map<String, dynamic> claims = jsonDecode(payload);
            email = claims['preferred_username'] ?? claims['email'] ?? claims['unique_name'] ?? "";
          }
        } catch (_) {}
      }

      if (email.isEmpty) {
        final graphRes = await http.get(
          Uri.parse('https://graph.microsoft.com/v1.0/me'),
          headers: {'Authorization': 'Bearer $accessToken'},
        );
        if (graphRes.statusCode == 200) {
          final profile = jsonDecode(graphRes.body);
          email = profile['mail'] ?? profile['userPrincipalName'] ?? "";
        }
      }

      if (email.isEmpty) {
        _snack('Failed to retrieve Microsoft account email', true);
        setState(() => _isLoading = false);
        return;
      }

      final res = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': accessToken}),
      );

      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', email);
        await prefs.setString('password', accessToken);
        await prefs.setBool('is_microsoft_login', true);
        await prefs.remove('is_google_login');
        // Register this device for push notifications
        await _registerDeviceForPush(email);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const EmailHomeScreen()),
          );
        }
      } else {
        _snack('Server authorization failed with Microsoft token', true);
      }
    } catch (e) {
      _snack('Microsoft Sign-In Error: $e', true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Registers this device for push notifications after a successful login.
  /// Links the user's email to their OneSignal subscription ID on the backend.
  Future<void> _registerDeviceForPush(String email) async {
    try {
      // 1. Associate user email as external ID in OneSignal
      NotificationService.loginUser(email);

      // 2. Wait briefly for the subscription ID to be available
      await Future.delayed(const Duration(seconds: 2));

      // 3. Get the device subscription ID from OneSignal
      final String? subscriptionId = NotificationService.getSubscriptionId();
      if (subscriptionId == null || subscriptionId.isEmpty) {
        debugPrint('[OneSignal] Subscription ID not yet available. Skipping registration.');
        return;
      }

      // 4. POST the subscription ID to the backend
      final response = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}/api/notifications/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'subscriptionId': subscriptionId}),
      );

      if (response.statusCode == 200) {
        debugPrint('[OneSignal] Device registered for push notifications: $subscriptionId');
      } else {
        debugPrint('[OneSignal] Failed to register device: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[OneSignal] Error registering device for push: $e');
    }
  }

  void _snack(String msg, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Gradient fills full screen
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF0288D1), Color(0xFF00BCD4)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: FadeTransition(
                opacity: _fade,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
              border: Border.all(color: Colors.white.withOpacity(0.4)),
            ),
            child: const Icon(Icons.mail_lock_rounded, size: 34, color: Colors.white),
          ),
          const SizedBox(height: 14),

          // Title
          const Text(
            "Welcome Back",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 5),
          Text(
            "Sign in to continue to your workspace",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.78)),
          ),
          const SizedBox(height: 22),

          // Email
          _field(_emailController, "Email Address", Icons.email_outlined),
          const SizedBox(height: 12),

          // Password
          _field(_passwordController, "Password", Icons.lock_outline, pass: true),

          // Forgot
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text("Forgot Password?",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 8),

          // Sign In button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A237E),
                elevation: 5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          color: Color(0xFF1A237E), strokeWidth: 2.5))
                  : const Text("Sign In",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text("OR", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _loginWithGoogle,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              icon: Image.network(
                'https://www.gstatic.com/images/branding/googleg/1x/googleg_standard_color_128dp.png',
                height: 20,
                width: 20,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.g_mobiledata, size: 24, color: Colors.white);
                },
              ),
              label: const Text("Sign In with Google",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _loginWithMicrosoft,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              icon: Image.network(
                'https://img.icons8.com/color/48/000000/microsoft.png',
                height: 20,
                width: 20,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.window, size: 22, color: Colors.white);
                },
              ),
              label: const Text("Sign In with Microsoft",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),

          // Sign Up
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Don't have an account? ",
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12.5)),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (c, a, b) => const SignupScreen(),
                    transitionsBuilder: (c, a, b, child) =>
                        FadeTransition(opacity: a, child: child),
                  ),
                ),
                child: const Text("Sign Up",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {bool pass = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: pass ? _obscure : false,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13.5),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.85), size: 19),
          suffixIcon: pass
              ? IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white.withOpacity(0.85),
                    size: 19,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}
