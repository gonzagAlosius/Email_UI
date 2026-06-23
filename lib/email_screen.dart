import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'calendar_view.dart';
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aad_oauth/aad_oauth.dart';
import 'package:aad_oauth/model/config.dart';
import 'main.dart';
import 'services/auth_service.dart';
import 'config/app_config.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';



class EmailHomeScreen extends StatefulWidget {
  const EmailHomeScreen({super.key});

  @override
  State<EmailHomeScreen> createState() => _EmailHomeScreenState();
}

class _EmailHomeScreenState extends State<EmailHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedApp = "Mail";

  String? _getMailPassword(SharedPreferences prefs) {
    bool isOAuth = prefs.getBool('is_microsoft_login') == true || prefs.getBool('is_google_login') == true;
    if (isOAuth) {
      return prefs.getString('password');
    } else {
      return prefs.getString('mail_password');
    }
  }
  bool _isPasswordMissing = false;
  bool _isOrgConfigMissing = false;
  bool _isConnecting = false;
  final TextEditingController _promptPasswordController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  final ScrollController _scrollController = ScrollController();
  int _inboxPage = 0;
  int _sentPage = 0;
  bool _isInboxLoadingMore = false;
  bool _isSentLoadingMore = false;
  bool _hasMoreInbox = true;
  bool _hasMoreSent = true;

  String _selectedFolder = "Inbox";
  int? _selectedEmailIndex;
  bool _isComposing = false;
  bool _isReplyingInline = false;
  bool _showEmailDetails = false;
  bool _isStarred = false;
  String? _selectedReaction;
  bool _isLoadingDetails = false;

  final TextEditingController _toController = TextEditingController();
  final TextEditingController _ccController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _showCcBcc = false;
  String _userName = "User";
  String _userEmail = "";
  String _userInitials = "U";

  List<PlatformFile> _attachments = [];

  final Map<String, List<Map<String, dynamic>>> _folders = {
    "Inbox": [],
    "Sent": [],
    "Drafts": [],
  };

  @override
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _folders["Inbox"]!.add({
      "sender": "Google",
      "email": "no-reply@accounts.google.com",
      "toName": "User",
      "toEmail": "user@example.com",
      "date": "10:53 AM",
      "subject": "Security Alert",
      "snippet": "New sign-in detected...",
      "content": "Hi there, a new device signed into your account. If it wasn't you, secure your account.",
      "isRead": false,
    });
    _initializeScreen();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && _selectedApp == "Mail" && _selectedFolder == "Inbox" && !_isPasswordMissing && !_isOrgConfigMissing) {
        _silentFetchInbox();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_selectedFolder == "Inbox") {
        _fetchInboxFromBackend(loadMore: true);
      } else if (_selectedFolder == "Sent") {
        _fetchSentFromBackend(loadMore: true);
      }
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _promptPasswordController.dispose();
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _contentController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('email');
    if (email != null) {
      String rawName = email.split('@')[0];
      String formattedName = "";
      String initials = "U";
      
      if (rawName.contains('.')) {
        var parts = rawName.split('.');
        formattedName = parts.map((p) => p.isNotEmpty ? p[0].toUpperCase() + p.substring(1) : "").join(' ');
        if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          initials = parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
        } else if (parts[0].isNotEmpty) {
          initials = parts[0][0].toUpperCase();
        }
      } else {
        formattedName = rawName.isNotEmpty ? rawName[0].toUpperCase() + rawName.substring(1) : "User";
        initials = rawName.isNotEmpty ? rawName[0].toUpperCase() : "U";
      }
      
      setState(() {
        _userEmail = email;
        _userName = formattedName;
        _userInitials = initials;
      });
    }
  }

  Future<void> _initializeScreen() async {
    await _loadUserData();
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      
      final orgConfigExists = await _checkOrgConfigAndPrompt();
      
      if (orgConfigExists) {
        _fetchInboxFromBackend();
      } else {
        setState(() {
          _isPasswordMissing = false;
        });
      }
    });
  }

  Future<bool> _checkOrgConfigAndPrompt() async {
    try {
      final sessionData = await AuthService.getSessionData();
      int? orgCode;
      if (sessionData != null) {
        final rawOrgCode = sessionData['orgCode'] ?? sessionData['orgcode'];
        if (rawOrgCode is num) {
          orgCode = rawOrgCode.toInt();
        } else if (rawOrgCode is String) {
          orgCode = int.tryParse(rawOrgCode);
        }
      }

      String checkUrl = "";
      if (orgCode != null) {
        checkUrl = '${AppConfig.instance.baseUrl}/org-config/check/$orgCode';
      } else if (_userEmail.isNotEmpty) {
        checkUrl = '${AppConfig.instance.baseUrl}/org-config/check-by-email?email=${Uri.encodeComponent(_userEmail)}';
      } else {
        return true;
      }

      final response = await http.get(Uri.parse(checkUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final bool exists = data['exists'] ?? false;
        final resolvedOrgCode = data['orgCode'] ?? data['orgcode'] ?? orgCode;

        if (!exists && resolvedOrgCode != null) {
          setState(() {
            _isOrgConfigMissing = true;
          });
          if (!mounted) return false;
          await _showOrgConfigPopup(resolvedOrgCode);
          return false;
        }
        setState(() {
          _isOrgConfigMissing = false;
        });
        return exists;
      }
      return true;
    } catch (e) {
      debugPrint("Error checking organization configuration: $e");
      return true;
    }
  }

  Future<void> _showOrgConfigPopup(dynamic orgCode) async {
    final formKey = GlobalKey<FormState>();
    final imapHostController = TextEditingController();
    final imapPortController = TextEditingController(text: '993');
    final smtpHostController = TextEditingController();
    final smtpPortController = TextEditingController(text: '465');
    bool isSaving = false;
    String? errorMessage;

    final contextToUse = navigatorKey.currentContext ?? context;

    await showDialog(
      context: contextToUse,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: const Color(0xFF1E293B),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.settings_suggest_rounded,
                                color: Color(0xFF3B82F6),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Organization Setup",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Configure mail servers for Org: $orgCode",
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Your organization does not have email server details configured yet. Please provide the mail server connection details below.",
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: const TextStyle(color: Color(0xFFF87171), fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        const Text(
                          "IMAP Configuration (Receiving)",
                          style: TextStyle(
                            color: Color(0xFF3B82F6),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildDialogField(
                                controller: imapHostController,
                                label: "IMAP Host",
                                hint: "imap.domain.com",
                                icon: Icons.dns_outlined,
                                validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _buildDialogField(
                                controller: imapPortController,
                                label: "IMAP Port",
                                hint: "993",
                                icon: Icons.numbers,
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return "Required";
                                  if (int.tryParse(value) == null) return "Invalid port";
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          "SMTP Configuration (Sending)",
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildDialogField(
                                controller: smtpHostController,
                                label: "SMTP Host",
                                hint: "smtp.domain.com",
                                icon: Icons.dns_outlined,
                                validator: (value) => value == null || value.trim().isEmpty ? "Required" : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _buildDialogField(
                                controller: smtpPortController,
                                label: "SMTP Port",
                                hint: "465",
                                icon: Icons.numbers,
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return "Required";
                                  if (int.tryParse(value) == null) return "Invalid port";
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      Navigator.of(dialogContext).pop();
                                      await AuthService.logout();
                                      if (mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                                        );
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF94A3B8),
                                side: const BorderSide(color: Color(0xFF475569)),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "Logout",
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        if (formKey.currentState!.validate()) {
                                          setState(() {
                                            isSaving = true;
                                            errorMessage = null;
                                          });

                                          try {
                                            final body = {
                                              "orgcode": orgCode,
                                              "imapHost": imapHostController.text.trim(),
                                              "imapPort": int.parse(imapPortController.text.trim()),
                                              "imapSecure": true,
                                              "smtpHost": smtpHostController.text.trim(),
                                              "smtpPort": int.parse(smtpPortController.text.trim()),
                                              "smtpSecure": true
                                            };

                                            final saveRes = await http.post(
                                              Uri.parse('${AppConfig.instance.baseUrl}/org-config/save'),
                                              headers: {"Content-Type": "application/json"},
                                              body: jsonEncode(body),
                                            );

                                            if (saveRes.statusCode == 200) {
                                               Navigator.of(dialogContext).pop();
                                               this.setState(() {
                                                 _isOrgConfigMissing = false;
                                               });
                                               _fetchInboxFromBackend();
                                             } else {
                                              final errBody = jsonDecode(saveRes.body);
                                              setState(() {
                                                errorMessage = errBody['error'] ?? "Failed to save configuration details";
                                                isSaving = false;
                                              });
                                            }
                                          } catch (e) {
                                            setState(() {
                                              errorMessage = "Error: $e";
                                              isSaving = false;
                                            });
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Save & Setup",
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
              prefixIcon: Icon(icon, size: 16, color: const Color(0xFF64748B)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _fetchInboxFromBackend({bool loadMore = false}) async {
    if (loadMore) {
      if (_isInboxLoadingMore || !_hasMoreInbox) return;
      setState(() {
        _isInboxLoadingMore = true;
      });
    } else {
      setState(() {
        _inboxPage = 0;
        _hasMoreInbox = true;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      String? password = _getMailPassword(prefs);
      if (email == null) return;

      final Map<String, String> headers = {'X-Email': email};
      if (password != null && password.isNotEmpty) {
        headers['X-Password'] = password;
      }

      int targetPage = loadMore ? _inboxPage + 1 : 0;
      final response = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/email/inbox?page=$targetPage&size=50'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newEmails = data.map((e) => Map<String, dynamic>.from(e)).toList();
        
        setState(() {
          if (loadMore) {
            _folders["Inbox"]!.addAll(newEmails);
            _inboxPage = targetPage;
          } else {
            _folders["Inbox"] = newEmails;
          }
          if (newEmails.length < 50) {
            _hasMoreInbox = false;
          }
          _isPasswordMissing = false;
        });
      } else if (response.statusCode == 401) {
        await _handleAuthFailureOrMissing(email);
      }
    } catch (e) {
      debugPrint("Failed to fetch inbox: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isInboxLoadingMore = false;
        });
      }
    }
  }

  Future<void> _silentFetchInbox() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString("email");
      String? password = _getMailPassword(prefs);
      if (email == null) return;

      final Map<String, String> headers = {"X-Email": email};
      if (password != null && password.isNotEmpty) {
        headers["X-Password"] = password;
      }

      final response = await http.get(
        Uri.parse("${AppConfig.instance.baseUrl}/email/inbox?page=0&size=50"),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> fetchedEmails = data.map((e) => Map<String, dynamic>.from(e)).toList();

        if (fetchedEmails.isEmpty) return;

        setState(() {
          dynamic selectedUid;
          if (_selectedEmailIndex != null &&
              _selectedFolder == "Inbox" &&
              _selectedEmailIndex! < _folders["Inbox"]!.length) {
            selectedUid = _folders["Inbox"]![_selectedEmailIndex!]["uid"];
          }

          final currentInbox = _folders["Inbox"]!;
          final existingUids = currentInbox.map((e) => e["uid"]).toSet();
          final newEmails = fetchedEmails.where((e) => !existingUids.contains(e["uid"])).toList();

          if (newEmails.isNotEmpty) {
            currentInbox.insertAll(0, newEmails);
          }

          for (var fetched in fetchedEmails) {
            int idx = currentInbox.indexWhere((e) => e["uid"] == fetched["uid"]);
            if (idx != -1) {
              currentInbox[idx]["isRead"] = fetched["isRead"];
            }
          }

          if (selectedUid != null) {
            int newIndex = currentInbox.indexWhere((e) => e["uid"] == selectedUid);
            if (newIndex != -1) {
              _selectedEmailIndex = newIndex;
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Silent fetch failed: $e");
    }
  }

  Future<void> _fetchSentFromBackend({bool loadMore = false}) async {
    if (loadMore) {
      if (_isSentLoadingMore || !_hasMoreSent) return;
      setState(() {
        _isSentLoadingMore = true;
      });
    } else {
      setState(() {
        _sentPage = 0;
        _hasMoreSent = true;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      String? password = _getMailPassword(prefs);
      if (email == null) return;

      final Map<String, String> headers = {'X-Email': email};
      if (password != null && password.isNotEmpty) {
        headers['X-Password'] = password;
      }

      int targetPage = loadMore ? _sentPage + 1 : 0;
      final response = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/email/sent?page=$targetPage&size=50'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newEmails = data.map((e) => Map<String, dynamic>.from(e)).toList();
        
        setState(() {
          if (loadMore) {
            _folders["Sent"]!.addAll(newEmails);
            _sentPage = targetPage;
          } else {
            _folders["Sent"] = newEmails;
          }
          if (newEmails.length < 50) {
            _hasMoreSent = false;
          }
          _isPasswordMissing = false;
        });
      } else if (response.statusCode == 401) {
        await _handleAuthFailureOrMissing(email);
      }
    } catch (e) {
      debugPrint("Failed to fetch sent messages: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSentLoadingMore = false;
        });
      }
    }
  }

  Future<void> _fetchEmailDetails(Map<String, dynamic> email, int index) async {
    if (email['content'] != null && email['content'].toString().isNotEmpty) {
      return;
    }
    if (email['uid'] == null) {
      return;
    }

    setState(() {
      _isLoadingDetails = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userEmail = prefs.getString('email');
      String? password = _getMailPassword(prefs);
      if (userEmail == null) return;

      final Map<String, String> headers = {'X-Email': userEmail};
      if (password != null && password.isNotEmpty) {
        headers['X-Password'] = password;
      }

      final response = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/email/details?folder=$_selectedFolder&uid=${email['uid']}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> details = jsonDecode(response.body);
        setState(() {
          _folders[_selectedFolder]![index]['content'] = details['content'];
          _folders[_selectedFolder]![index]['attachments'] = details['attachments'];
          if (details['snippet'] != null && details['snippet'].toString().isNotEmpty) {
            _folders[_selectedFolder]![index]['snippet'] = details['snippet'];
          }
        });
      } else if (response.statusCode == 401) {
        await _handleAuthFailureOrMissing(userEmail);
      }
    } catch (e) {
      debugPrint("Failed to fetch email details: $e");
    } finally {
      setState(() {
        _isLoadingDetails = false;
      });
    }
  }

  Future<void> _handleAuthFailureOrMissing(String email) async {
    final lowerEmail = email.toLowerCase();
    final bool isGoogle = lowerEmail.endsWith('@gmail.com') || lowerEmail.contains('google');
    final bool isMicrosoft = lowerEmail.endsWith('@outlook.com') || 
                             lowerEmail.endsWith('@hotmail.com') || 
                             lowerEmail.endsWith('@live.com') ||
                             lowerEmail.contains('microsoft');

    if (isGoogle) {
      debugPrint("🔄 Auto-triggering Google Sign-In for $email...");
      try {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          clientId: '497665028004-3d7sq2e5096d1bsacfgmpdje7je8npee.apps.googleusercontent.com',
          scopes: [
            'email',
            'https://mail.google.com/',
          ],
        );
        
        GoogleSignInAccount? account = await googleSignIn.signInSilently();
        account ??= await googleSignIn.signIn();

        if (account != null) {
          final GoogleSignInAuthentication googleAuth = await account.authentication;
          final String? accessToken = googleAuth.accessToken;
          if (accessToken != null) {
            await _updateCredentialsOnBackendAndLocal(email, accessToken);
            return;
          }
        }
      } catch (e) {
        debugPrint("❌ Auto Google OAuth failed: $e");
      }
    } else if (isMicrosoft) {
      debugPrint("🔄 Auto-triggering Microsoft Sign-In for $email...");
      try {
        final Config config = Config(
          tenant: 'common',
          clientId: '04b47bff-348d-41d1-829a-f4276486e287',
          scope: 'openid profile email https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access',
          redirectUri: 'http://localhost:8085',
          navigatorKey: navigatorKey,
          customParameters: {'prompt': 'select_account'},
        );
        final AadOAuth oauth = AadOAuth(config);
        
        try {
          await oauth.login();
        } catch (e) {
          debugPrint('Ignored Microsoft JS cast error: $e');
        }
        
        final String? accessToken = await oauth.getAccessToken();
        if (accessToken != null) {
          await _updateCredentialsOnBackendAndLocal(email, accessToken);
          return;
        }
      } catch (e) {
        debugPrint("❌ Auto Microsoft OAuth failed: $e");
      }
    }

    setState(() {
      _isPasswordMissing = true;
    });
  }

  Future<void> _updateCredentialsOnBackendAndLocal(String email, String tokenOrPassword) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.instance.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': tokenOrPassword}),
      );
      
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', email);
        await prefs.setString('password', tokenOrPassword);
        await prefs.setString('mail_password', tokenOrPassword);
        setState(() {
          _isPasswordMissing = false;
        });
        if (_selectedFolder == "Inbox") {
          _fetchInboxFromBackend();
        } else if (_selectedFolder == "Sent") {
          _fetchSentFromBackend();
        }
      } else {
        setState(() {
          _isPasswordMissing = true;
        });
      }
    } catch (e) {
      debugPrint("Error updating credentials: $e");
      setState(() {
        _isPasswordMissing = true;
      });
    }
  }


  void _selectFolder(String folder) {
    setState(() {
      _selectedFolder = folder;
      _isComposing = false;
      _isReplyingInline = false;
      _selectedEmailIndex = null;
    });

    if (folder == "Inbox") {
      _fetchInboxFromBackend();
    } else if (folder == "Sent") {
      _fetchSentFromBackend();
    }

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _startCompose() {
    setState(() {
      _toController.clear();
      _ccController.clear();
      _subjectController.clear();
      _contentController.clear();
      _attachments = [];
      _isComposing = true;
      _isReplyingInline = false;
      _showCcBcc = false;
      _selectedEmailIndex = null;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickAttachments() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
    );

    if (result != null) {
      setState(() {
        _attachments.addAll(result.files);
      });
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _sendEmail() async {
    debugPrint("🚀 _sendEmail called!");
    final to = _toController.text;
    debugPrint("  To: '$to'");
    if (to.isEmpty) {
      debugPrint("  ❌ returning early: 'to' is empty");
      return;
    }
    
    final subject = _subjectController.text.isNotEmpty ? _subjectController.text : "(No Subject)";
    final content = _contentController.text;
    debugPrint("  Subject: '$subject', Content length: ${content.length}");

    List<Map<String, String>> attachmentPayload = [];
    for (var file in _attachments) {
      if (file.bytes != null) {
        attachmentPayload.add({
          'fileName': file.name,
          'base64Content': base64Encode(file.bytes!),
        });
      } else {
        debugPrint("  ⚠️ Attachment '${file.name}' has null bytes");
      }
    }
    debugPrint("  Attachments count: ${attachmentPayload.length}");

    try {
       SharedPreferences prefs = await SharedPreferences.getInstance();
       String? userEmail = prefs.getString('email');
       String? userPassword = _getMailPassword(prefs);
       debugPrint("  userEmail from prefs: '$userEmail'");
       debugPrint("  userPassword is null? ${userPassword == null}");
       if (userEmail == null) {
         debugPrint("  ❌ returning early: userEmail is null");
         return;
       }

       final Map<String, String> headers = {
         'Content-Type': 'application/json',
         'X-Email': userEmail,
       };
       if (userPassword != null && userPassword.isNotEmpty) {
         headers['X-Password'] = userPassword;
       }

       final url = '${AppConfig.instance.baseUrl}/email/send';
       debugPrint("  Sending POST request to '$url' with headers: $headers");

       final response = await http.post(
          Uri.parse(url),
          headers: headers,
           body: jsonEncode({
              'to': to,
              'cc': _ccController.text,
              'subject': subject,
              'content': content,
              'attachments': attachmentPayload,
           }),
       );
       debugPrint("  Response status: ${response.statusCode}");
       debugPrint("  Response body: ${response.body}");
       if (response.statusCode == 200) {
          _showSnackBar("Email Sent successfully!");
          // Wait a moment for the server to sync then refresh
          Future.delayed(const Duration(seconds: 2), () => _fetchSentFromBackend());
       } else {
          _showSnackBar("Failed to send: ${response.body}");
       }
    } catch (e) {
       debugPrint("  ❌ Exception in _sendEmail: $e");
       _showSnackBar("API Error: $e");
    }

    setState(() {
      _isComposing = false;
      _isReplyingInline = false;
      _selectedFolder = "Sent";
      _selectedEmailIndex = null; 
    });
  }

  void _deleteSelectedEmail() {
     if (_selectedEmailIndex == null) return;
     final list = _folders[_selectedFolder]!;
     list.removeAt(_selectedEmailIndex!);
     setState(() {
        _selectedEmailIndex = null;
     });
     _showSnackBar("Deleted");
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _fetchAndDownloadAttachment(Map<String, dynamic> email, Map<String, dynamic> att) async {
    final String fileName = att['fileName'] ?? 'Unnamed File';
    final String contentType = att['contentType'] ?? 'application/octet-stream';
    String base64Data = att['base64Data'] ?? '';

    if (base64Data.isNotEmpty) {
      _downloadAttachment(fileName, contentType, base64Data);
      return;
    }

    if (email['uid'] == null) {
      _showSnackBar("Cannot download attachment: Message UID is missing.");
      return;
    }

    _showSnackBar("Fetching attachment $fileName...");

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userEmail = prefs.getString('email');
      String? password = _getMailPassword(prefs);
      if (userEmail == null) return;

      final Map<String, String> headers = {'X-Email': userEmail};
      if (password != null && password.isNotEmpty) {
        headers['X-Password'] = password;
      }

      final response = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/email/attachment?folder=$_selectedFolder&uid=${email['uid']}&fileName=${Uri.encodeComponent(fileName)}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> resData = jsonDecode(response.body);
        final String fetchedBase64 = resData['base64Data'] ?? '';
        if (fetchedBase64.isNotEmpty) {
          setState(() {
            att['base64Data'] = fetchedBase64;
          });
          _downloadAttachment(fileName, contentType, fetchedBase64);
        } else {
          _showSnackBar("Attachment data is empty on the server.");
        }
      } else if (response.statusCode == 401) {
        await _handleAuthFailureOrMissing(userEmail);
      } else {
        _showSnackBar("Failed to fetch attachment. Status: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Failed to fetch attachment: $e");
      _showSnackBar("Failed to download attachment: $e");
    }
  }

  void _downloadAttachment(String fileName, String contentType, String base64Data) {
    if (base64Data.isEmpty) {
      _showSnackBar("Attachment data is empty.");
      return;
    }
    if (kIsWeb) {
      try {
        js.context.callMethod('eval', ["""
          var link = document.createElement('a');
          link.href = 'data:$contentType;base64,$base64Data';
          link.download = '$fileName';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
        """]);
        _showSnackBar("Downloading $fileName...");
      } catch (e) {
        _showSnackBar("Failed to download: $e");
      }
    } else {
      _showSnackBar("Download only supported on Web version.");
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(0xFF1E293B),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5F56).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFFF5F56),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Confirm Logout",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Are you sure you want to log out? You will need to sign in again to access your workspace.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          side: const BorderSide(color: Color(0xFF475569)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          await AuthService.logout();
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          }
                        },

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5F56),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Logout",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {


    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;
    final bool isTablet = screenWidth >= 600 && screenWidth < 900;
    final bool isMobile = screenWidth < 600;

    Widget mainContent;

    if (isMobile) {
      if (_selectedApp == "Mail") {
        if (_isComposing) {
          mainContent = _buildComposeView(key: const ValueKey('compose'));
        } else if (_selectedEmailIndex != null) {
          mainContent = _buildMessageDetail(key: const ValueKey('detail'));
        } else {
          mainContent = KeyedSubtree(key: const ValueKey('list'), child: _buildMessageList());
        }
      } else if (_selectedApp == "Calendar") {
        mainContent = const CalendarView(key: ValueKey('calendar'));
      } else {
        mainContent = Center(key: ValueKey(_selectedApp), child: Text("$_selectedApp View"));
      }
    } else {
      mainContent = Row(
        key: ValueKey('main-row-$_selectedApp'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: (isDesktop && _selectedApp == "Mail") ? 250 : 0,
            child: (isDesktop && _selectedApp == "Mail")
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: 250,
                      child: _buildFolderSidebar(),
                    ),
                  )
                : const SizedBox(),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: (isDesktop && _selectedApp == "Mail") ? 1 : 0,
            child: const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          ),
          
          if (_selectedApp == "Mail") ...[
            SizedBox(width: isTablet ? 320 : 360, child: _buildMessageList()),
            const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            Expanded(
              child: SizedBox.expand(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.01, 0.0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    );
                  },
                  child: _isComposing 
                    ? _buildComposeView(key: const ValueKey('compose')) 
                    : _buildMessageDetail(key: const ValueKey('detail')),
                ),
              ),
            ),
          ] else if (_selectedApp == "Calendar") ...[
            const Expanded(child: CalendarView(key: ValueKey('calendar-desktop')))
          ] else ...[
            Expanded(key: ValueKey(_selectedApp), child: Center(child: Text("$_selectedApp View"))),
          ],
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F172A),
      drawer: isDesktop ? null : Drawer(
        width: _selectedApp == "Mail" ? 330 : 80,
        child: Row(
          children: [
            _buildThinRail(),
            if (_selectedApp == "Mail")
              Expanded(child: _buildFolderSidebar()),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppTopBar(isDesktop),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile) _buildThinRail(),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: isMobile ? BorderRadius.zero : const BorderRadius.only(topLeft: Radius.circular(24)),
                    ),
                    child: ClipRRect(
                      borderRadius: isMobile ? BorderRadius.zero : const BorderRadius.only(topLeft: Radius.circular(24)),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.005, 0.0),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          );
                        },
                        child: mainContent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showProfilePopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.15),
      builder: (BuildContext context) {
        return Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 50, right: 8),
            child: Material(
              color: Colors.transparent,
              child: _buildProfilePopupCard(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilePopupCard() {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  _userEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                onPressed: () => Navigator.of(context).pop(),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  _userInitials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                    )
                  ]
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 14,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Hi, $_userName!",
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A8A),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              "Manage your Workspace Account",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      bottomLeft: Radius.circular(24),
                    ),
                  ),
                  child: InkWell(
                    onTap: () {},
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Color(0xFF1E293B), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Add account",
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _logout();
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: Color(0xFF1E293B), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Sign out",
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.cloud_queue, color: Color(0xFF64748B), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: const LinearProgressIndicator(
                          value: 0.79,
                          backgroundColor: Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "79% of 15 GB used",
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Privacy Policy",
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
              Text(
                "  •  ",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              Text(
                "Terms of Service",
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppTopBar(bool isDesktop) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 900;
    final double barHeight = isMobile ? 56 : 64;

    if (isMobile && _isSearching) {
      return Container(
        width: double.infinity,
        height: barHeight,
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = "";
                });
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    hintText: "Search...",
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? InkWell(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = "";
                              });
                            },
                            child: const Icon(Icons.clear, size: 18, color: Colors.white38),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      );
    }

    // Build Left Section
    Widget leftSection;
    if (isDesktop) {
      leftSection = SizedBox(
        width: 330,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(width: 24),
            const Flexible(
              child: Text(
                "BotsEdge mail",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else if (isTablet) {
      leftSection = SizedBox(
        width: 200,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                "BotsEdge mail",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else {
      leftSection = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          const SizedBox(width: 8),
          const Text(
            "BotsEdge mail",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    // Build Middle Section
    Widget middleSection;
    if (!isMobile) {
      middleSection = Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isDesktop ? 520 : 360),
            child: Container(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  hintText: "Search mail...",
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? InkWell(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = "";
                            });
                          },
                          child: const Icon(Icons.clear, size: 18, color: Colors.white38),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      middleSection = const Expanded(child: SizedBox());
    }

    // Build Right Section
    Widget rightSection = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (isMobile) ...[
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white70),
            onPressed: () => setState(() => _isSearching = true),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.white70),
          onPressed: () => _showSnackBar("No new notifications"),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: _showProfilePopup,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF6366F1),
              child: Text(
                _userInitials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      height: barHeight,
      color: const Color(0xFF0F172A),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
      alignment: Alignment.center,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leftSection,
          middleSection,
          rightSection,
        ],
      ),
    );
  }

  Widget _buildThinRail() {
    return Container(
      width: 80,
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _buildRailIcon(Icons.mark_email_unread_outlined, "Mail"),
          _buildRailIcon(Icons.people_outline, "Contacts"),
          _buildRailIcon(Icons.calendar_month_outlined, "Calendar"),
          const Spacer(),
          _buildRailIcon(Icons.settings_outlined, "Settings"),
          const SizedBox(height: 12),
          InkWell(
            onTap: _logout,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.logout_rounded, color: Color(0xFFFF5F56), size: 26),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRailIcon(IconData icon, String appName) {
    final isSelected = _selectedApp == appName;
    return InkWell(
      onTap: () {
        setState(() => _selectedApp = appName);
        if (appName != "Mail" && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
          Navigator.pop(context);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 200),
          tween: ColorTween(
            begin: isSelected ? Colors.white : const Color(0xFF94A3B8),
            end: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
          builder: (context, color, child) {
            return Icon(icon, color: color, size: 26);
          },
        ),
      ),
    );
  }

  Widget _buildFolderSidebar() {
    int unread = _folders["Inbox"]!.where((e) => e['isRead'] == false).length;
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20, 
                  backgroundColor: const Color(0xFFE0E7FF), 
                  child: Text(_userInitials, style: const TextStyle(color: Color(0xFF4338CA), fontWeight: FontWeight.bold))
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        Text(_userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                        Text(_userEmail, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
                     ],
                  ),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              onPressed: _startCompose,
              icon: const Icon(Icons.add),
              label: const Text("New Message", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildFolderItem("Inbox", Icons.inbox_rounded, count: unread.toString()),
                _buildFolderItem("Sent", Icons.send_rounded),
                _buildFolderItem("Drafts", Icons.insert_drive_file_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderItem(String title, IconData icon, {String? count}) {
    final isSelected = _selectedFolder == title && !_isComposing;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, size: 20, color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B)),
          title: Text(title, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF1E293B))),
          trailing: (count != null && count != "0")
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                  child: Text(count, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF64748B)))
                )
              : null,
          onTap: () => _selectFolder(title),
        ),
      ),
    );
  }

  Widget _buildFolderActionItem(String title, IconData icon, VoidCallback onTap) {
     return Material(
        color: Colors.transparent,
        child: ListTile(
           leading: Icon(icon, size: 20, color: const Color(0xFF64748B)),
           title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1E293B))),
           onTap: onTap,
           dense: true,
        ),
     );
  }

  Widget _buildMessageList() {
    final List<Map<String, dynamic>> allEmails = _folders[_selectedFolder] ?? [];
    final List<Map<String, dynamic>> emails = _searchQuery.isEmpty
        ? allEmails
        : allEmails.where((e) {
            final sender = (e['sender'] ?? '').toString().toLowerCase();
            final subject = (e['subject'] ?? '').toString().toLowerCase();
            final snippet = (e['snippet'] ?? '').toString().toLowerCase();
            final query = _searchQuery.toLowerCase();
            return sender.contains(query) || subject.contains(query) || snippet.contains(query);
          }).toList();

    return Column(
      children: [
        Container(padding: const EdgeInsets.all(24), alignment: Alignment.centerLeft, child: Text(_selectedFolder, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const Divider(height: 1),
        Expanded(
          child: _isPasswordMissing
              ? _buildPasswordPrompt()
              : (emails.isEmpty
                  ? const Center(child: Text("No messages"))
                  : ListView.separated(
                      controller: _scrollController,
                      itemCount: emails.length + ((_selectedFolder == "Inbox" ? _isInboxLoadingMore : _isSentLoadingMore) ? 1 : 0),
                      separatorBuilder: (c, i) => const Divider(height: 1, indent: 80),
                      itemBuilder: (context, index) {
                        if (index == emails.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          );
                        }

                        final email = emails[index];
                        final isSelected = allEmails.indexOf(email) == _selectedEmailIndex && !_isComposing;
                        final String sender = email['sender'] ?? 'Unknown';
                        final bool isRead = email['isRead'] == true;

                        return InkWell(
                          onTap: () {
                            final originalIndex = allEmails.indexOf(email);
                            setState(() {
                              _selectedEmailIndex = originalIndex;
                              _isComposing = false;
                              email['isRead'] = true;
                            });
                            _fetchEmailDetails(email, originalIndex);
                          },
                          child: Container(
                            color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                CircleAvatar(child: Text(sender.isNotEmpty ? sender.substring(0, 1).toUpperCase() : "U")),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(sender, style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 13)),
                                      Text(email['subject'] ?? '', style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                                      Text(email['snippet'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    )),
        ),
      ],
    );
  }

  Widget _buildPasswordPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sync_lock_rounded,
                  color: Color(0xFF2563EB),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Sync Mail Server",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "To access your inbox, please provide your mail server password.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              // Password input
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: TextField(
                  controller: _promptPasswordController,
                  obscureText: true,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Mail Server Password",
                    hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    prefixIcon: Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _connectMailServer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          "Connect & Sync",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectMailServer() async {
    final password = _promptPasswordController.text;
    if (password.isEmpty) {
      _showSnackBar("Please enter your password");
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      if (email == null || email.isEmpty) {
        _showSnackBar("Email details not found.");
        setState(() {
          _isConnecting = false;
        });
        return;
      }

      // Check if credentials are valid by logging in/fetching inbox
      final response = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/email/inbox'),
        headers: {'X-Email': email, 'X-Password': password},
      );

      if (response.statusCode == 200) {
        // Correct password! Save password to preferences
        await prefs.setString('mail_password', password);
        
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> emails = data.map((e) => Map<String, dynamic>.from(e)).toList();
        
        setState(() {
          _folders["Inbox"] = emails;
          _isPasswordMissing = false;
          _isConnecting = false;
        });
        _showSnackBar("Mail server synchronized successfully!");
        _promptPasswordController.clear();
      } else {
        _showSnackBar("Authentication failed. Invalid password.");
        setState(() {
          _isConnecting = false;
        });
      }
    } catch (e) {
      _showSnackBar("Failed to connect to mail server: $e");
      setState(() {
        _isConnecting = false;
      });
    }
  }


  Widget _buildComposeView({Key? key}) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      key: key,
      color: Colors.white,
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 40,
        right: isMobile ? 16 : 40,
        top: isMobile ? 16 : 32,    // reduced top on mobile
        bottom: 0,                   // no bottom padding — toolbar handles it
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              if (isMobile) ...[
                IconButton(
                  onPressed: () => setState(() => _isComposing = false),
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                "New Message",
                style: TextStyle(fontSize: isMobile ? 20 : 28, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: -0.5),
              ),
              const Spacer(),
              if (!isMobile) IconButton(
                onPressed: () => setState(() => _isComposing = false),
                icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                hoverColor: Colors.red.shade50,
              ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 32),

          // To field
          _buildStyledInput(
            controller: _toController,
            label: "To",
            hint: "recipient@example.com",
            icon: Icons.person_outline_rounded,
            suffix: !_showCcBcc ? TextButton(
              onPressed: () => setState(() => _showCcBcc = true),
              child: const Text("Cc", style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
            ) : null,
          ),
          if (_showCcBcc) ...[
            const SizedBox(height: 10),
            _buildStyledInput(
              controller: _ccController,
              label: "Cc",
              hint: "carbon.copy@example.com",
              icon: Icons.people_outline_rounded,
              suffix: IconButton(
                icon: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)),
                onPressed: () => setState(() {
                  _showCcBcc = false;
                  _ccController.clear();
                }),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Subject field
          _buildStyledInput(
            controller: _subjectController,
            label: "Subject",
            hint: "Enter message subject",
            icon: Icons.subject_rounded,
          ),
          const SizedBox(height: 16),

          // Message body — Expanded fills remaining space
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                ],
              ),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF334155)),
                decoration: const InputDecoration(
                  hintText: "Write your message here...",
                  hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
          ),

          // Attachments row (if any)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _attachments.isEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  height: 48,
                  margin: const EdgeInsets.only(top: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _attachments.asMap().entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(entry.value.name, style: const TextStyle(fontSize: 12)),
                            onDeleted: () => _removeAttachment(entry.key),
                            deleteIconColor: Colors.red,
                            backgroundColor: const Color(0xFFF1F5F9),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
          ),

          // Bottom toolbar — always pinned at bottom
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B57D0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _sendEmail,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(24),
                              bottomLeft: Radius.circular(24),
                            ),
                          ),
                        ),
                        child: const Text(
                          "Send",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Container(width: 1, height: 22, color: Colors.white.withOpacity(0.3)),
                      IconButton(
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                        onPressed: () {},
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(onPressed: () {}, icon: const Icon(Icons.text_format, color: Color(0xFF444746), size: 20), tooltip: "Formatting"),
                        IconButton(onPressed: _pickAttachments, icon: const Icon(Icons.attach_file, color: Color(0xFF444746), size: 20), tooltip: "Attach"),
                        IconButton(onPressed: () {}, icon: const Icon(Icons.link, color: Color(0xFF444746), size: 20), tooltip: "Link"),
                        IconButton(onPressed: () {}, icon: const Icon(Icons.sentiment_satisfied_alt_outlined, color: Color(0xFF444746), size: 20), tooltip: "Emoji"),
                        IconButton(onPressed: () {}, icon: const Icon(Icons.delete_outline, color: Color(0xFF444746), size: 20), tooltip: "Discard"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildStyledInput({
    required TextEditingController controller, 
    required String label, 
    String? hint, 
    required IconData icon,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildMessageDetail({Key? key}) {
    if (_selectedEmailIndex == null) {
      return Container(
        key: key,
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.email_outlined, size: 64, color: const Color(0xFFCBD5E1)),
              const SizedBox(height: 16),
              const Text("No message selected", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8))),
              const SizedBox(height: 8),
              const Text("Select an email from the list to read it here.", style: TextStyle(color: Color(0xFFCBD5E1))),
            ],
          ),
        ),
      );
    }

    final email = _folders[_selectedFolder]![_selectedEmailIndex!];
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Container(
      key: key,
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: isMobile ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _selectedEmailIndex = null),
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  const Text("Back to list", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  email['subject'] ?? '(No Subject)',
                  style: TextStyle(
                    fontSize: isMobile ? 20 : 24, 
                    fontWeight: FontWeight.bold, 
                    color: const Color(0xFF1E293B),
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              if (!isMobile) ...[
                IconButton(
                  onPressed: () {}, 
                  icon: const Icon(Icons.print_outlined, color: Color(0xFF64748B), size: 20),
                  tooltip: "Print",
                ),
                IconButton(
                  onPressed: () {}, 
                  icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF64748B), size: 18),
                  tooltip: "Open in new window",
                ),
              ]
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  email['sender']?.toString().isNotEmpty == true
                      ? email['sender'].toString().substring(0, 1).toUpperCase()
                      : 'U',
                  style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            email['sender'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            "<${email['email'] ?? 'hidden'}>",
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => setState(() => _showEmailDetails = !_showEmailDetails),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              "To: ${email['toName'] ?? (email['toEmail'] ?? 'me')}",
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                Text(
                  _formatDate(email['date']),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _isStarred = !_isStarred),
                        icon: Icon(
                          _isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: _isStarred ? Colors.orange : const Color(0xFF475569),
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "Flag",
                      ),
                      _buildEmojiButton(context, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), size: 18),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isComposing = false;
                            _isReplyingInline = true;
                            _toController.text = email['email'] ?? email['sender'] ?? '';
                            _subjectController.text = email['subject'] != null 
                                ? (email['subject'].toString().startsWith('Re:') ? email['subject'] : 'Re: ${email['subject']}')
                                : 'Re:';
                            _contentController.clear();
                            _attachments = [];
                          });
                        },
                        icon: const Icon(Icons.reply_rounded, color: const Color(0xFF475569), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "Reply",
                      ),
                      IconButton(
                        onPressed: _deleteSelectedEmail,
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5F56), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "Delete",
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF475569), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: "More actions",
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  email['date'] ?? '',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _isStarred = !_isStarred),
                  icon: Icon(_isStarred ? Icons.star_rounded : Icons.star_outline_rounded, color: _isStarred ? Colors.orange : const Color(0xFF64748B), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isComposing = false;
                      _isReplyingInline = true;
                      _toController.text = email['email'] ?? email['sender'] ?? '';
                      _subjectController.text = email['subject'] != null 
                          ? (email['subject'].toString().startsWith('Re:') ? email['subject'] : 'Re: ${email['subject']}')
                          : 'Re:';
                      _contentController.clear();
                      _attachments = [];
                    });
                  },
                  icon: const Icon(Icons.reply_rounded, color: const Color(0xFF64748B), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _deleteSelectedEmail,
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5F56), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
          if (_showEmailDetails) ...[
             const SizedBox(height: 12),
             Container(
               margin: const EdgeInsets.only(left: 44),
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: const Color(0xFFF8FAFC),
                 borderRadius: BorderRadius.circular(8),
                 border: Border.all(color: const Color(0xFFE2E8F0)),
               ),
               child: Column(
                 children: [
                    _buildDetailRow("from:", "${email['sender']} <${email['email'] ?? ''}>"),
                    _buildDetailRow("to:", (email['toName'] != null && email['toName'].toString().isNotEmpty)
                        ? "${email['toName']} <${email['toEmail'] ?? ''}>"
                        : (_userEmail.isNotEmpty ? _userEmail : "me")),
                    _buildDetailRow("date:", email['date'] ?? ''),
                    _buildDetailRow("subject:", email['subject'] ?? ''),
                 ],
               ),
             ),
          ],
          if (_selectedReaction != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(left: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9), 
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedReaction!, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    const Text("1", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16), 
            child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
          ),
          if (_isReplyingInline) _buildInlineReplyEditor(email),
          Expanded(
            child: _isLoadingDetails
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildContentWidget(email['content'] ?? ''),
                        if (email['attachments'] != null && (email['attachments'] as List).isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Divider(color: Color(0xFFE2E8F0), thickness: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.attach_file, color: Color(0xFF64748B), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                "Attachments (${(email['attachments'] as List).length})",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: (email['attachments'] as List).map<Widget>((att) {
                              final String fileName = att['fileName'] ?? 'Unnamed File';
                              final String contentType = att['contentType'] ?? 'application/octet-stream';
                              final String base64Data = att['base64Data'] ?? '';
                              
                              return InkWell(
                                onTap: () => _fetchAndDownloadAttachment(email, att),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 260),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF4F46E5), size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              fileName,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              contentType.split('/').last.toUpperCase(),
                                              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.download_rounded, color: Color(0xFF64748B), size: 16),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          if (!_isReplyingInline)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _isComposing = false;
                        _isReplyingInline = true;
                        _toController.text = email['email'] ?? email['sender'] ?? '';
                        _subjectController.text = email['subject'] != null 
                            ? (email['subject'].toString().startsWith('Re:') ? email['subject'] : 'Re: ${email['subject']}')
                            : 'Re:';
                        _contentController.clear();
                        _attachments = [];
                      });
                    },
                    icon: const Icon(Icons.reply_rounded, size: 16),
                    label: const Text("Reply"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: const Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.forward_rounded, size: 16),
                    label: const Text("Forward"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      side: const BorderSide(color: const Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInlineReplyEditor(Map<String, dynamic> email) {
    final String sender = email['sender'] ?? 'Unknown';
    final String emailAddress = email['email'] ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inline header
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE0E7FF),
                child: Text(
                  sender.isNotEmpty ? sender.substring(0, 1).toUpperCase() : 'U',
                  style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Reply to $sender",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                    ),
                    if (emailAddress.isNotEmpty)
                      Text(
                        emailAddress,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                onPressed: () {
                  setState(() {
                    _isReplyingInline = false;
                    _contentController.clear();
                    _attachments = [];
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: "Discard",
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Message Body Field
          Container(
            constraints: const BoxConstraints(minHeight: 100, maxHeight: 180),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1).withOpacity(0.7)),
            ),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              autofocus: true,
              style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF334155)),
              decoration: const InputDecoration(
                hintText: "Write your reply here...",
                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),

          // Attachments row (if any)
          if (_attachments.isNotEmpty)
            Container(
              height: 40,
              margin: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _attachments.asMap().entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        label: Text(
                          entry.value.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onDeleted: () => _removeAttachment(entry.key),
                        deleteIconColor: Colors.red,
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: EdgeInsets.zero,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Bottom Toolbar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Send & Attach Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _sendEmail,
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text("Send"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B57D0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF475569), size: 20),
                    onPressed: _pickAttachments,
                    tooltip: "Attach file",
                  ),
                ],
              ),

              // Discard Button
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5F56), size: 20),
                onPressed: () {
                  setState(() {
                    _isReplyingInline = false;
                    _contentController.clear();
                    _attachments = [];
                  });
                },
                tooltip: "Discard",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildEmojiButton(BuildContext context, {EdgeInsetsGeometry? padding, BoxConstraints? constraints, double size = 20}) {
    return IconButton(
      padding: padding,
      constraints: constraints,
      onPressed: () {
        final RenderBox button = context.findRenderObject() as RenderBox;
        final Offset position = button.localToGlobal(Offset.zero);

        showDialog(
          context: context,
          barrierColor: Colors.transparent,
          builder: (context) {
            return Stack(
              children: [
                GestureDetector(
                   onTap: () => Navigator.pop(context),
                   child: Container(color: Colors.transparent, width: double.infinity, height: double.infinity),
                ),
                Positioned(
                  left: position.dx - 300,
                  top: position.dy - 410,
                  child: Material(
                    elevation: 12,
                    shadowColor: Colors.black38,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 320,
                      height: 400,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // Search Bar
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(25)),
                              child: const TextField(
                                decoration: InputDecoration(
                                  hintText: "Search emojis",
                                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                                  border: InputBorder.none,
                                  icon: Icon(Icons.search, size: 16, color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                          ),
                          // Category Icons
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF2563EB)),
                                Icon(Icons.emoji_emotions_outlined, size: 18, color: Color(0xFF64748B)),
                                Icon(Icons.people_outline_rounded, size: 18, color: Color(0xFF64748B)),
                                Icon(Icons.pets_outlined, size: 18, color: Color(0xFF64748B)),
                                Icon(Icons.fastfood_outlined, size: 18, color: Color(0xFF64748B)),
                                Icon(Icons.directions_car_outlined, size: 18, color: Color(0xFF64748B)),
                                Icon(Icons.lightbulb_outline_rounded, size: 18, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                          const Divider(height: 24),
                          // Emoji Grid
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              children: [
                                const Text("RECENTLY USED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                const SizedBox(height: 12),
                                _buildEmojiGrid(["😀", "❤️", "👍", "🔥", "🎉", "😮"]),
                                const SizedBox(height: 20),
                                const Text("SMILEYS AND EMOTIONS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                const SizedBox(height: 12),
                                _buildEmojiGrid(["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🙂", "🙃", "😉", "😊", "😇", "😍", "🤩", "😘", "😗", "😚", "😙", "😋", "😛", "😜", "🤪", "😝"]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      icon: Icon(Icons.add_reaction_outlined, color: const Color(0xFF475569), size: size),
    );
  }


  Widget _buildEmojiGrid(List<String> emojis) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: emojis.map((e) => GestureDetector(
        onTap: () {
          setState(() => _selectedReaction = e);
          Navigator.pop(context);
        },
        child: Text(e, style: const TextStyle(fontSize: 24)),
      )).toList(),
    );
  }

  Widget _buildContentWidget(String content) {
    final String trimmed = content.trim();
    final bool isHtml = trimmed.contains('<html') || 
                        trimmed.contains('<body') || 
                        trimmed.contains('<div') || 
                        trimmed.contains('<p') || 
                        trimmed.contains('<table') || 
                        trimmed.contains('<br') ||
                        trimmed.contains('</');

    String processedContent;
    if (isHtml) {
      processedContent = '<style>'
          'table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 14px; }'
          'th, td { border: 1px solid #CBD5E1; padding: 8px 10px; text-align: left; }'
          'th { background-color: #F1F5F9; font-weight: 600; color: #1E293B; }'
          '</style>' + trimmed;
    } else {
      processedContent = '<div style="white-space: pre-wrap; font-family: sans-serif; font-size: 14px; color: #334155;">${_escapeHtml(trimmed)}</div>';
    }

    return HtmlWidget(
      processedContent,
      textStyle: const TextStyle(
        fontSize: 15,
        height: 1.6,
        color: Color(0xFF334155),
      ),
    );
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    try {
      // Format: "Wed May 27 23:18:16 IST 2026"
      final parts = dateStr.split(' ');
      if (parts.length >= 6) {
        final month = parts[1];
        final day = parts[2];
        final time = parts[3];
        final year = parts[5];
        final timeParts = time.split(':');
        final formattedTime = timeParts.length >= 2 ? "${timeParts[0]}:${timeParts[1]}" : time;
        return "$month $day, $year $formattedTime";
      }
    } catch (_) {}
    return dateStr;
  }

}
