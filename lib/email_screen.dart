import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'calendar_view.dart';
import 'utils/web_helpers.dart';
import 'utils/widgets/elaborated_event_dialog.dart';
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
    bool isOAuth =
        prefs.getBool('is_microsoft_login') == true ||
        prefs.getBool('is_google_login') == true;
    if (isOAuth) {
      return prefs.getString('password');
    } else {
      return prefs.getString('mail_password');
    }
  }

  bool _isPasswordMissing = false;
  bool _isOrgConfigMissing = false;
  bool _isConnecting = false;
  bool _isLoadingInbox = false;
  bool _isLoadingSent = false;
  final TextEditingController _promptPasswordController =
      TextEditingController();
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
  bool _isLoadingDrafts = false;
  bool _isDraftsLoadingMore = false;
  int _draftsPage = 0;
  bool _hasMoreDrafts = true;
  int? _currentDraftUid;
  List<String> _contactSuggestions = [];
  bool _isLoadingSuggestions = false;

  String _selectedFolder = "Inbox";
  int? _selectedEmailIndex;
  bool _isComposing = false;
  bool _isReplyingInline = false;
  bool _isForwardingInline = false;
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
  List<Map<String, dynamic>> _upcomingEvents = [];
  final Set<String> _acknowledgedEventIds = {};
  bool _isNotificationDropdownOpen = false;
  OverlayEntry? _notificationOverlay;
  final GlobalKey _notificationKey = GlobalKey();

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
      "content":
          "Hi there, a new device signed into your account. If it wasn't you, secure your account.",
      "isRead": false,
    });
    _initializeScreen();
    _fetchUpcomingEvents();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted &&
          _selectedApp == "Mail" &&
          _selectedFolder == "Inbox" &&
          !_isPasswordMissing &&
          !_isOrgConfigMissing) {
        _silentFetchInbox();
      }
      if (mounted) {
        _fetchUpcomingEvents();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_selectedFolder == "Inbox") {
        _fetchInboxFromBackend(loadMore: true);
      } else if (_selectedFolder == "Sent") {
        _fetchSentFromBackend(loadMore: true);
      } else if (_selectedFolder == "Drafts") {
        _fetchDraftsFromBackend(loadMore: true);
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
        formattedName = parts
            .map((p) => p.isNotEmpty ? p[0].toUpperCase() + p.substring(1) : "")
            .join(' ');
        if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          initials = parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
        } else if (parts[0].isNotEmpty) {
          initials = parts[0][0].toUpperCase();
        }
      } else {
        formattedName = rawName.isNotEmpty
            ? rawName[0].toUpperCase() + rawName.substring(1)
            : "User";
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

      _fetchSuggestions();
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

  Future<void> _fetchUpcomingEvents() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      bool isOAuth = prefs.getBool('is_microsoft_login') == true || prefs.getBool('is_google_login') == true;
      String? password = isOAuth ? prefs.getString('password') : prefs.getString('mail_password');
      
      final Map<String, String> headers = {};
      if (email != null) headers['X-Email'] = email;
      if (password != null) headers['X-Password'] = password;
      
      final response = await http.get(Uri.parse('${AppConfig.instance.calendarUrl}/events'), headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            final now = DateTime.now();
            _upcomingEvents = data.where((e) {
              final st = DateTime.tryParse(e['startTime'] ?? '');
              final eventKey = e['id']?.toString() ?? '${e['title']}_${e['startTime']}';
              return st != null && st.isAfter(now) && !_acknowledgedEventIds.contains(eventKey);
            }).map((e) => e as Map<String, dynamic>).toList();
            _upcomingEvents.sort((a, b) {
              final aSt = DateTime.tryParse(a['startTime'] ?? '') ?? DateTime(2100);
              final bSt = DateTime.tryParse(b['startTime'] ?? '') ?? DateTime(2100);
              return aSt.compareTo(bSt);
            });
            if (_upcomingEvents.length > 5) {
              _upcomingEvents = _upcomingEvents.sublist(0, 5);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching upcoming events: $e");
    }
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
        checkUrl =
            '${AppConfig.instance.baseUrl}/org-config/check-by-email?email=${Uri.encodeComponent(_userEmail)}';
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
                                color: const Color(
                                  0xFF3B82F6,
                                ).withOpacity(0.15),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Color(0xFFF87171),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFF87171),
                                      fontSize: 12.5,
                                    ),
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
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? "Required"
                                    : null,
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
                                  if (value == null || value.trim().isEmpty)
                                    return "Required";
                                  if (int.tryParse(value) == null)
                                    return "Invalid port";
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
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? "Required"
                                    : null,
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
                                  if (value == null || value.trim().isEmpty)
                                    return "Required";
                                  if (int.tryParse(value) == null)
                                    return "Invalid port";
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
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const LoginScreen(),
                                          ),
                                        );
                                      }
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF94A3B8),
                                side: const BorderSide(
                                  color: Color(0xFF475569),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                "Logout",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                              "imapHost": imapHostController
                                                  .text
                                                  .trim(),
                                              "imapPort": int.parse(
                                                imapPortController.text.trim(),
                                              ),
                                              "imapSecure": true,
                                              "smtpHost": smtpHostController
                                                  .text
                                                  .trim(),
                                              "smtpPort": int.parse(
                                                smtpPortController.text.trim(),
                                              ),
                                              "smtpSecure": true,
                                            };

                                            final saveRes = await http.post(
                                              Uri.parse(
                                                '${AppConfig.instance.baseUrl}/org-config/save',
                                              ),
                                              headers: {
                                                "Content-Type":
                                                    "application/json",
                                              },
                                              body: jsonEncode(body),
                                            );

                                            if (saveRes.statusCode == 200) {
                                              Navigator.of(dialogContext).pop();
                                              this.setState(() {
                                                _isOrgConfigMissing = false;
                                              });
                                              _fetchInboxFromBackend();
                                            } else {
                                              final errBody = jsonDecode(
                                                saveRes.body,
                                              );
                                              setState(() {
                                                errorMessage =
                                                    errBody['error'] ??
                                                    "Failed to save configuration details";
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
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
                                        style: TextStyle(
                                          fontSize: 13.5,
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
              hintStyle: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 13,
              ),
              prefixIcon: Icon(icon, size: 16, color: const Color(0xFF64748B)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
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
        _isLoadingInbox = true;
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
        Uri.parse(
          '${AppConfig.instance.baseUrl}/email/inbox?page=$targetPage&size=50',
        ),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newEmails = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

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
          _isLoadingInbox = false;
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
        final List<Map<String, dynamic>> fetchedEmails = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

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
          final newEmails = fetchedEmails
              .where((e) => !existingUids.contains(e["uid"]))
              .toList();

          if (newEmails.isNotEmpty) {
            currentInbox.insertAll(0, newEmails);
          }

          for (var fetched in fetchedEmails) {
            int idx = currentInbox.indexWhere(
              (e) => e["uid"] == fetched["uid"],
            );
            if (idx != -1) {
              currentInbox[idx]["isRead"] = fetched["isRead"];
            }
          }

          if (selectedUid != null) {
            int newIndex = currentInbox.indexWhere(
              (e) => e["uid"] == selectedUid,
            );
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
        _isLoadingSent = true;
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
        Uri.parse(
          '${AppConfig.instance.baseUrl}/email/sent?page=$targetPage&size=50',
        ),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newEmails = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

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
          _isLoadingSent = false;
        });
      }
    }
  }

  Future<void> _fetchDraftsFromBackend({bool loadMore = false}) async {
    if (loadMore) {
      if (_isDraftsLoadingMore || !_hasMoreDrafts) return;
      setState(() {
        _isDraftsLoadingMore = true;
      });
    } else {
      setState(() {
        _draftsPage = 0;
        _hasMoreDrafts = true;
        _isLoadingDrafts = true;
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

      int targetPage = loadMore ? _draftsPage + 1 : 0;
      final response = await http.get(
        Uri.parse(
          '${AppConfig.instance.baseUrl}/email/drafts?page=$targetPage&size=50',
        ),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> newEmails = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          if (loadMore) {
            _folders["Drafts"]!.addAll(newEmails);
            _draftsPage = targetPage;
          } else {
            _folders["Drafts"] = newEmails;
          }
          if (newEmails.length < 50) {
            _hasMoreDrafts = false;
          }
          _isPasswordMissing = false;
        });
      } else if (response.statusCode == 401) {
        await _handleAuthFailureOrMissing(email);
      }
    } catch (e) {
      debugPrint("Failed to fetch drafts: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDraftsLoadingMore = false;
          _isLoadingDrafts = false;
        });
      }
    }
  }

  Future<void> _fetchSuggestions() async {
    if (_isLoadingSuggestions) return;
    setState(() {
      _isLoadingSuggestions = true;
    });
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.instance.baseUrl}/users'),
      );
      if (res.statusCode == 200) {
        final List<dynamic> users = jsonDecode(res.body);
        setState(() {
          _contactSuggestions = users
              .map((u) => u['emailAddress']?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch suggestions: $e");
    } finally {
      setState(() {
        _isLoadingSuggestions = false;
      });
    }
  }

  Future<void> _fetchEmailDetails(
    Map<String, dynamic> email,
    int index, {
    bool wasUnread = false,
  }) async {
    final bool hasContent =
        email['content'] != null && email['content'].toString().isNotEmpty;
    if (hasContent && !wasUnread) {
      return;
    }
    if (email['uid'] == null) {
      return;
    }

    if (!hasContent) {
      setState(() {
        _isLoadingDetails = true;
      });
    }

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
        Uri.parse(
          '${AppConfig.instance.baseUrl}/email/details?folder=$_selectedFolder&uid=${email['uid']}',
        ),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> details = jsonDecode(response.body);
        setState(() {
          _folders[_selectedFolder]![index]['content'] = details['content'];
          _folders[_selectedFolder]![index]['attachments'] =
              details['attachments'];
          if (details['snippet'] != null &&
              details['snippet'].toString().isNotEmpty) {
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
    final bool isGoogle =
        lowerEmail.endsWith('@gmail.com') || lowerEmail.contains('google');
    final bool isMicrosoft =
        lowerEmail.endsWith('@outlook.com') ||
        lowerEmail.endsWith('@hotmail.com') ||
        lowerEmail.endsWith('@live.com') ||
        lowerEmail.contains('microsoft');

    if (isGoogle) {
      debugPrint("🔄 Auto-triggering Google Sign-In for $email...");
      if (kIsWeb) {
        final redirectUrl = Uri.base
            .toString()
            .split('?')
            .first
            .split('#')
            .first;
        String baseUrl = AppConfig.instance.baseUrl;
        if (baseUrl.endsWith('/api'))
          baseUrl = baseUrl.substring(0, baseUrl.length - 4);
        final backendAuthUrl =
            '$baseUrl/oauth/google/login?redirect=$redirectUrl';
        redirectTo(backendAuthUrl);
        return;
      }
      // Fallback for mobile if needed, though they want it all through backend
      try {
        final GoogleSignIn googleSignIn = GoogleSignIn(
          clientId:
              '497665028004-3d7sq2e5096d1bsacfgmpdje7je8npee.apps.googleusercontent.com',
          scopes: ['email', 'https://mail.google.com/'],
        );

        GoogleSignInAccount? account = await googleSignIn.signInSilently();
        account ??= await googleSignIn.signIn();

        if (account != null) {
          final GoogleSignInAuthentication googleAuth =
              await account.authentication;
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
          scope:
              'openid profile email https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access',
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

  Future<void> _updateCredentialsOnBackendAndLocal(
    String email,
    String tokenOrPassword,
  ) async {
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
        _fetchSuggestions();
        if (_selectedFolder == "Inbox") {
          _fetchInboxFromBackend();
        } else if (_selectedFolder == "Sent") {
          _fetchSentFromBackend();
        } else if (_selectedFolder == "Drafts") {
          _fetchDraftsFromBackend();
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
    if (_isComposing) {
      _exitComposer(discard: false);
    }
    setState(() {
      _selectedFolder = folder;
      _isComposing = false;
      _isReplyingInline = false;
      _isForwardingInline = false;
      _selectedEmailIndex = null;
    });

    if (folder == "Inbox") {
      _fetchInboxFromBackend();
    } else if (folder == "Sent") {
      _fetchSentFromBackend();
    } else if (folder == "Drafts") {
      _fetchDraftsFromBackend();
    }

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _startCompose() {
    if (_isComposing) {
      _exitComposer(discard: false);
    }
    setState(() {
      _toController.clear();
      _ccController.clear();
      _subjectController.clear();
      _contentController.clear();
      _attachments = [];
      _isComposing = true;
      _isReplyingInline = false;
      _isForwardingInline = false;
      _showCcBcc = false;
      _selectedEmailIndex = null;
      _currentDraftUid = null;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  Future<void> _exitComposer({bool discard = false}) async {
    final to = _toController.text.trim();
    final subject = _subjectController.text.trim();
    final content = _contentController.text.trim();
    final draftUid = _currentDraftUid;

    setState(() {
      _isComposing = false;
      _currentDraftUid = null;
      _toController.clear();
      _ccController.clear();
      _subjectController.clear();
      _contentController.clear();
      _attachments = [];
    });

    if (discard) {
      if (draftUid != null) {
        try {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          String? email = prefs.getString('email');
          String? password = _getMailPassword(prefs);
          if (email != null) {
            final Map<String, String> headers = {'X-Email': email};
            if (password != null && password.isNotEmpty) {
              headers['X-Password'] = password;
            }
            await http.delete(
              Uri.parse('${AppConfig.instance.baseUrl}/email/drafts/$draftUid'),
              headers: headers,
            );
          }
        } catch (e) {
          debugPrint("Failed to delete draft: $e");
        }
      }
      _showSnackBar("Draft discarded");
      if (_selectedFolder == "Drafts") {
        _fetchDraftsFromBackend();
      }
    } else {
      if (to.isNotEmpty || subject.isNotEmpty || content.isNotEmpty) {
        _showSnackBar("Saving draft...");
        try {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          String? email = prefs.getString('email');
          String? password = _getMailPassword(prefs);
          if (email != null) {
            final Map<String, dynamic> headers = {
              'Content-Type': 'application/json',
              'X-Email': email
            };
            if (password != null && password.isNotEmpty) {
              headers['X-Password'] = password;
            }

            final Map<String, dynamic> body = {
              'to': to,
              'subject': subject,
              'content': content,
            };
            if (draftUid != null) {
              body['draftUid'] = draftUid;
            }

            final res = await http.post(
              Uri.parse('${AppConfig.instance.baseUrl}/email/drafts'),
              headers: headers.map((k, v) => MapEntry(k, v.toString())),
              body: jsonEncode(body),
            );

            if (res.statusCode == 200) {
              final Map<String, dynamic> resData = jsonDecode(res.body);
              if (resData.containsKey('draftUid')) {
                _currentDraftUid = resData['draftUid'];
              }
              _showSnackBar("Draft saved successfully!");
              if (_selectedFolder == "Drafts") {
                _fetchDraftsFromBackend();
              }
            } else {
              _showSnackBar("Failed to save draft: ${res.body}");
            }
          }
        } catch (e) {
          debugPrint("Failed to autosave draft: $e");
        }
      }
    }
  }

  Future<void> _openDraftForEditing(Map<String, dynamic> email, int originalIndex) async {
    if (email['content'] == null || email['content'].toString().isEmpty) {
      setState(() {
        _isLoadingDetails = true;
      });
      await _fetchEmailDetails(email, originalIndex);
      setState(() {
        _isLoadingDetails = false;
      });
    }

    final updatedEmail = _folders["Drafts"]![originalIndex];

    setState(() {
      _toController.text = updatedEmail['toEmail'] ?? updatedEmail['email'] ?? '';
      _subjectController.text = updatedEmail['subject'] ?? '';
      _contentController.text = updatedEmail['content'] ?? '';
      _currentDraftUid = updatedEmail['uid'];
      _isComposing = true;
      _selectedEmailIndex = null;
    });
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

    final subject = _subjectController.text.isNotEmpty
        ? _subjectController.text
        : "(No Subject)";
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
          if (_currentDraftUid != null) 'draftUid': _currentDraftUid,
        }),
      );
      debugPrint("  Response status: ${response.statusCode}");
      debugPrint("  Response body: ${response.body}");
      if (response.statusCode == 200) {
        _showSnackBar("Email Sent successfully!");
        // Wait a moment for the server to sync then refresh
        Future.delayed(
          const Duration(seconds: 2),
          () {
            _fetchSentFromBackend();
            _fetchDraftsFromBackend();
          },
        );
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
      _isForwardingInline = false;
      _selectedFolder = "Sent";
      _selectedEmailIndex = null;
      _currentDraftUid = null;
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
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _fetchAndDownloadAttachment(
    Map<String, dynamic> email,
    Map<String, dynamic> att,
  ) async {
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
        Uri.parse(
          '${AppConfig.instance.baseUrl}/email/attachment?folder=$_selectedFolder&uid=${email['uid']}&fileName=${Uri.encodeComponent(fileName)}',
        ),
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
        _showSnackBar(
          "Failed to fetch attachment. Status: ${response.statusCode}",
        );
      }
    } catch (e) {
      debugPrint("Failed to fetch attachment: $e");
      _showSnackBar("Failed to download attachment: $e");
    }
  }

  String _htmlToPlainText(String html) {
    if (html.isEmpty) return "";
    String text = html;
    text = text.replaceAll(
      RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
      '',
    );
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</td>', caseSensitive: false), '\t');
    text = text.replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<li>', caseSensitive: false), '\n • ');
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  Future<void> _setupForwardInline(Map<String, dynamic> email) async {
    final originalText = _htmlToPlainText(email['content'] ?? '');
    setState(() {
      _isComposing = false;
      _isReplyingInline = true;
      _isForwardingInline = true;
      _toController.text = '';
      _ccController.clear();
      _subjectController.text = email['subject'] != null
          ? (email['subject'].toString().startsWith('Fwd:')
                ? email['subject']
                : 'Fwd: ${email['subject']}')
          : 'Fwd:';
      _contentController.text =
          "\n\n\n---------- Forwarded message ---------\n"
          "From: ${email['sender']} <${email['email'] ?? ''}>\n"
          "Date: ${email['date'] ?? ''}\n"
          "Subject: ${email['subject'] ?? ''}\n"
          "To: ${email['toName'] ?? (email['toEmail'] ?? '')}\n\n"
          "$originalText";
      _attachments = [];
    });

    if (email['attachments'] != null &&
        (email['attachments'] as List).isNotEmpty) {
      final List attachmentsList = email['attachments'] as List;
      _showSnackBar(
        "Loading ${attachmentsList.length} attachment(s) to forward...",
      );
      for (var att in attachmentsList) {
        final String fileName = att['fileName'] ?? 'Unnamed File';
        final String contentType =
            att['contentType'] ?? 'application/octet-stream';
        String base64Data = att['base64Data'] ?? '';

        if (base64Data.isEmpty && email['uid'] != null) {
          try {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            String? userEmail = prefs.getString('email');
            String? password = _getMailPassword(prefs);
            if (userEmail != null) {
              final Map<String, String> headers = {'X-Email': userEmail};
              if (password != null && password.isNotEmpty) {
                headers['X-Password'] = password;
              }
              final response = await http.get(
                Uri.parse(
                  '${AppConfig.instance.baseUrl}/email/attachment?folder=$_selectedFolder&uid=${email['uid']}&fileName=${Uri.encodeComponent(fileName)}',
                ),
                headers: headers,
              );
              if (response.statusCode == 200) {
                final Map<String, dynamic> resData = jsonDecode(response.body);
                base64Data = resData['base64Data'] ?? '';
                if (base64Data.isNotEmpty) {
                  att['base64Data'] = base64Data;
                }
              }
            }
          } catch (e) {
            debugPrint("Failed to fetch attachment for forward: $e");
          }
        }

        if (base64Data.isNotEmpty) {
          try {
            final bytes = base64Decode(base64Data);
            setState(() {
              _attachments.add(
                PlatformFile(name: fileName, size: bytes.length, bytes: bytes),
              );
            });
          } catch (e) {
            debugPrint("Failed to decode attachment: $e");
          }
        }
      }
    }
  }

  void _downloadAttachment(
    String fileName,
    String contentType,
    String base64Data,
  ) {
    if (base64Data.isEmpty) {
      _showSnackBar("Attachment data is empty.");
      return;
    }
    if (kIsWeb) {
      try {
        downloadFileWeb(fileName, contentType, base64Data);
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
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
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

    final bool showSidebar =
        isDesktop &&
        _selectedApp == "Mail" &&
        ((_selectedEmailIndex == null && !_isComposing) || screenWidth > 1200);

    Widget mainContent;

    if (isMobile) {
      if (_selectedApp == "Mail") {
        if (_isComposing) {
          mainContent = _buildComposeView(key: const ValueKey('compose'));
        } else if (_selectedEmailIndex != null) {
          mainContent = _buildMessageDetail(key: const ValueKey('detail'));
        } else {
          mainContent = KeyedSubtree(
            key: const ValueKey('list'),
            child: _buildMessageList(),
          );
        }
      } else if (_selectedApp == "Calendar") {
        mainContent = const CalendarView(key: ValueKey('calendar'));
      } else {
        mainContent = _buildComingSoonView(_selectedApp);
      }
    } else {
      mainContent = Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 8),
        child: Row(
          key: ValueKey('main-row-$_selectedApp'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: showSidebar ? 212 : 0,
              child: showSidebar
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildFolderSidebar(),
                        ),
                      ),
                    )
                  : const SizedBox(),
            ),

            if (_selectedApp == "Mail") ...[
              Container(
                width: isTablet ? 280 : 300,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildMessageList(),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0.01, 0.0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
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
              ),
            ] else if (_selectedApp == "Calendar") ...[
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: const CalendarView(key: ValueKey('calendar-desktop')),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                key: ValueKey(_selectedApp),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildComingSoonView(_selectedApp),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F172A),
      drawer: (_selectedApp == "Mail" && !showSidebar)
          ? Drawer(width: 250, child: SafeArea(child: _buildFolderSidebar()))
          : null,
      bottomNavigationBar: isMobile
          ? Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: BottomNavigationBar(
                backgroundColor: Colors.white,
                selectedItemColor: const Color(0xFF2563EB),
                unselectedItemColor: const Color(0xFF94A3B8),
                selectedFontSize: 11,
                unselectedFontSize: 11,
                type: BottomNavigationBarType.fixed,
                currentIndex: _selectedApp == "Mail"
                    ? 0
                    : (_selectedApp == "Contacts"
                          ? 1
                          : (_selectedApp == "Calendar" ? 2 : 3)),
                onTap: (index) {
                  setState(() {
                    if (index == 0) _selectedApp = "Mail";
                    if (index == 1) _selectedApp = "Contacts";
                    if (index == 2) _selectedApp = "Calendar";
                    if (index == 3) _selectedApp = "Settings";
                  });
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.mark_email_unread_outlined),
                    activeIcon: Icon(Icons.mark_email_unread),
                    label: "Mail",
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people_outline),
                    activeIcon: Icon(Icons.people),
                    label: "Contacts",
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month_outlined),
                    activeIcon: Icon(Icons.calendar_month),
                    label: "Calendar",
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings_outlined),
                    activeIcon: Icon(Icons.settings),
                    label: "Settings",
                  ),
                ],
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isMobile) _buildThinRail(),
            Expanded(
              child: Container(
                margin: isMobile
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(top: 8, bottom: 8, right: 8),
                decoration: BoxDecoration(
                  color: isMobile ? Colors.white : const Color(0xFFF4F7F9),
                  borderRadius: isMobile
                      ? BorderRadius.zero
                      : BorderRadius.circular(24),
                ),
                child: ClipRRect(
                  borderRadius: isMobile
                      ? BorderRadius.zero
                      : BorderRadius.circular(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAppTopBar(isDesktop, showSidebar),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin: const Offset(0.005, 0.0),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    child: child,
                                  ),
                                );
                              },
                          child: mainContent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
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
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
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
                const Icon(
                  Icons.cloud_queue,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF3B82F6),
                          ),
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

  Widget _buildAppTopBar(bool isDesktop, bool showSidebar) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth < 900;
    final double barHeight = isMobile ? 56 : 72;

    if (isMobile && _isSearching) {
      return Container(
        width: double.infinity,
        height: barHeight,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = "";
                });
              },
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
                decoration: const InputDecoration(
                  hintText: "Search...",
                  hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget leftSection = Container(
      width: showSidebar ? 250 : (isTablet ? 200 : 0),
      padding: const EdgeInsets.only(left: 24),
      child: Row(
        children: [
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF0F172A)),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          Image.asset('assets/images/logo.png', width: 28, height: 28),
          const SizedBox(width: 8),
          const Text(
            "B-Bots Mail",
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );

    Widget middleSection = Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 20, color: Color(0xFF94A3B8)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Search mail, people, or anything...",
                      hintStyle: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Text(
                    "⌘K",
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget rightSection = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMobile)
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF64748B)),
            onPressed: () => setState(() => _isSearching = true),
          ),
        IconButton(
          icon: const Icon(Icons.wb_sunny_outlined, color: Color(0xFF64748B)),
          onPressed: () {},
        ),
        Builder(
          builder: (context) {
            final unreadCount = _folders["Inbox"]!.where((e) => e['isRead'] == false).length;
            final eventCount = _upcomingEvents.length;
            final totalNotifications = unreadCount + eventCount;
            
            return Stack(
              key: _notificationKey,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications_none,
                    color: Color(0xFF64748B),
                  ),
                  onPressed: _toggleNotificationDropdown,
                ),
                if (totalNotifications > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6366F1),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        totalNotifications > 9 ? "9+" : "$totalNotifications",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }
        ),
        const SizedBox(width: 12),
        InkWell(
          onTap: _showProfilePopup,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFA855F7),
            child: Text(
              _userInitials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
      ],
    );

    return Container(
      width: double.infinity,
      height: barHeight,
      color: Colors.white,
      child: Row(
        children: [
          if (!isMobile) leftSection,
          if (isMobile) ...[leftSection, const Expanded(child: SizedBox())],
          if (!isMobile) middleSection,
          rightSection,
        ],
      ),
    );
  }

  Widget _buildThinRail() {
    return Container(
      width: 70,
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF5F56),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFBD2E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFF27C93F),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    _buildRailIcon(
                      Icons.mail_rounded,
                      "Mail",
                      isGradient: true,
                    ),
                    _buildRailIcon(Icons.people_outline, "Contacts"),
                    _buildRailIcon(Icons.calendar_month_outlined, "Calendar"),
                    _buildRailIcon(Icons.task_alt, "Tasks"),
                    const Spacer(),
                    _buildRailIcon(Icons.settings_outlined, "Settings"),
                    const SizedBox(height: 12),
                    _buildRailIcon(Icons.logout_rounded, "Sign out"),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRailIcon(
    IconData icon,
    String label, {
    bool isGradient = false,
  }) {
    final isSelected = _selectedApp == (label == "Sign out" ? "" : label);
    return InkWell(
      onTap: () {
        if (label == "Sign out") {
          _logout();
        } else {
          setState(() => _selectedApp = label);
          if (label != "Mail" &&
              (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
            Navigator.pop(context);
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: isSelected && isGradient
                    ? const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected && !isGradient
                    ? const Color(0xFF1E293B)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected && isGradient
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: isSelected || isGradient
                    ? Colors.white
                    : const Color(0xFF94A3B8),
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComingSoonView(String appName) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/contacts_coming_soon.png',
            width: 250,
            height: 250,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.people_alt_outlined,
                size: 120,
                color: Color(0xFFC4B5FD),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            '$appName is coming soon!',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "We're working hard to bring you a better way\nto connect and manage your ${appName.toLowerCase()}.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none, size: 18),
            label: const Text(
              "Notify me when it's ready",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleNotificationDropdown() {
    if (_isNotificationDropdownOpen) {
      _notificationOverlay?.remove();
      _notificationOverlay = null;
      setState(() => _isNotificationDropdownOpen = false);
    } else {
      _notificationOverlay = _buildNotificationOverlay();
      Overlay.of(context).insert(_notificationOverlay!);
      setState(() => _isNotificationDropdownOpen = true);
    }
  }

  OverlayEntry _buildNotificationOverlay() {
    RenderBox renderBox = _notificationKey.currentContext!.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (overlayContext) {
        final unreadEmails = _folders["Inbox"]!.where((e) => e['isRead'] == false).toList();
        final upcomingEvents = _upcomingEvents;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleNotificationDropdown,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: offset.dy + size.height + 10,
              right: MediaQuery.of(context).size.width - offset.dx - size.width,
              width: 320,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Notifications',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                        ),
                      ),
                      const Divider(height: 1),
                      if (unreadEmails.isEmpty && upcomingEvents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text('No new notifications', style: TextStyle(color: Color(0xFF64748B))),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              if (unreadEmails.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Text('Unread Emails', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                                ),
                                ...unreadEmails.map((email) {
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFE0E7FF),
                                      child: Icon(Icons.email, color: Color(0xFF6366F1), size: 16),
                                    ),
                                    title: Text(email['subject'] ?? 'No Subject', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    subtitle: Text(email['sender'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    onTap: () {
                                      final originalIndex = _folders["Inbox"]!.indexOf(email);
                                      final bool wasUnread = email['isRead'] != true;
                                      _toggleNotificationDropdown();
                                      setState(() {
                                        email['isRead'] = true;
                                        _selectedApp = "Mail";
                                        _selectedFolder = "Inbox";
                                        _selectedEmailIndex = originalIndex;
                                      });
                                      _fetchEmailDetails(email, originalIndex, wasUnread: wasUnread);
                                    },
                                  );
                                }).toList(),
                              ],
                              if (upcomingEvents.isNotEmpty) ...[
                                if (unreadEmails.isNotEmpty) const Divider(height: 1),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Text('Upcoming Events', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                                ),
                                ...upcomingEvents.map((event) {
                                  return ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFF3E8FF),
                                      child: Icon(Icons.event, color: Color(0xFF8B5CF6), size: 16),
                                    ),
                                    title: Text(event['title'] ?? event['subject'] ?? 'No Title', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    subtitle: Text(_formatDate(event['startTime'] ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    onTap: () {
                                      final eventKey = event['id']?.toString() ?? '${event['title']}_${event['startTime']}';
                                      _toggleNotificationDropdown();
                                      setState(() {
                                        _acknowledgedEventIds.add(eventKey);
                                        _upcomingEvents.removeWhere((e) => (e['id']?.toString() ?? '${e['title']}_${e['startTime']}') == eventKey);
                                        _selectedApp = "Calendar";
                                      });
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) => ElaboratedEventDialog(
                                          event: event,
                                          onEventDeleted: () {
                                            _fetchUpcomingEvents();
                                          },
                                        ),
                                      );
                                    },
                                  );
                                }).toList(),
                              ],
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
  }

  Widget _buildFolderSidebar() {
    int unread = _folders["Inbox"]!.where((e) => e['isRead'] == false).length;
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFEDE9FE)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFA855F7),
                    child: Text(
                      _userInitials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _userEmail,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _startCompose,
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                label: const Text(
                  "New Message",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildFolderItem(
                  "Inbox",
                  Icons.inbox_outlined,
                  count: unread.toString(),
                ),
                _buildFolderItem("Sent", Icons.send_outlined),
                _buildFolderItem("Drafts", Icons.insert_drive_file_outlined),
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF5F3FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          minLeadingWidth: 20,
          leading: Icon(
            icon,
            size: 20,
            color: isSelected
                ? const Color(0xFF7C3AED)
                : const Color(0xFF64748B),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF475569),
            ),
          ),
          trailing: (count != null && count != "0")
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    count,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF64748B),
                    ),
                  ),
                )
              : null,
          onTap: () => _selectFolder(title),
        ),
      ),
    );
  }

  Widget _buildFolderActionItem(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icon, size: 20, color: const Color(0xFF64748B)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF1E293B),
          ),
        ),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  Widget _buildMessageList() {
    final List<Map<String, dynamic>> allEmails =
        _folders[_selectedFolder] ?? [];
    final List<Map<String, dynamic>> emails = _searchQuery.isEmpty
        ? allEmails
        : allEmails.where((e) {
            final sender = (e['sender'] ?? '').toString().toLowerCase();
            final subject = (e['subject'] ?? '').toString().toLowerCase();
            final snippet = (e['snippet'] ?? '').toString().toLowerCase();
            final query = _searchQuery.toLowerCase();
            return sender.contains(query) ||
                subject.contains(query) ||
                snippet.contains(query);
          }).toList();

    final bool isLoading = _selectedFolder == "Inbox"
        ? _isLoadingInbox
        : (_selectedFolder == "Sent" ? _isLoadingSent : (_selectedFolder == "Drafts" ? _isLoadingDrafts : false));
    int unreadCount = allEmails.where((e) => e['isRead'] == false).length;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 20, top: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedFolder,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (_selectedFolder == "Inbox") ...[
                        const SizedBox(height: 4),
                        Text(
                          "$unreadCount unread emails",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.filter_list_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.more_horiz_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          Expanded(
            child: _isPasswordMissing
                ? _buildPasswordPrompt()
                : (isLoading
                      ? const SkeletonMessageList()
                      : (emails.isEmpty
                            ? const Center(
                                child: Text(
                                  "No messages",
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                itemCount:
                                    emails.length +
                                    ((_selectedFolder == "Inbox"
                                            ? _isInboxLoadingMore
                                            : (_selectedFolder == "Sent"
                                                ? _isSentLoadingMore
                                                : _isDraftsLoadingMore))
                                        ? 1
                                        : 0),
                                itemBuilder: (context, index) {
                                  if (index == emails.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final email = emails[index];
                                  final isSelected =
                                      allEmails.indexOf(email) ==
                                          _selectedEmailIndex &&
                                      !_isComposing;
                                  final String sender =
                                      email['sender'] ?? 'Unknown';
                                  final bool isRead = email['isRead'] == true;

                                  final initial = sender.isNotEmpty
                                      ? sender.substring(0, 1).toUpperCase()
                                      : "U";
                                  final int colorHash = sender.codeUnits.fold(
                                    0,
                                    (a, b) => a + b,
                                  );
                                  final List<Color> bgColors = [
                                    const Color(0xFFFEE2E2),
                                    const Color(0xFFFEF3C7),
                                    const Color(0xFFD1FAE5),
                                    const Color(0xFFDBEAFE),
                                    const Color(0xFFF3E8FF),
                                  ];
                                  final List<Color> textColors = [
                                    const Color(0xFFEF4444),
                                    const Color(0xFFF59E0B),
                                    const Color(0xFF10B981),
                                    const Color(0xFF3B82F6),
                                    const Color(0xFF8B5CF6),
                                  ];
                                  final colorIdx = colorHash % bgColors.length;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: InkWell(
                                      onTap: () {
                                        final originalIndex = allEmails.indexOf(
                                          email,
                                        );
                                        if (_selectedFolder == "Drafts") {
                                          _openDraftForEditing(email, originalIndex);
                                          return;
                                        }
                                        final bool wasUnread =
                                            email['isRead'] != true;
                                        setState(() {
                                          _selectedEmailIndex = originalIndex;
                                          _isComposing = false;
                                          email['isRead'] = true;
                                        });
                                        _fetchEmailDetails(
                                          email,
                                          originalIndex,
                                          wasUnread: wasUnread,
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFF5F3FF)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: isSelected
                                                ? const Color(0xFFEDE9FE)
                                                : const Color(0xFFF1F5F9),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (!isRead)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  top: 10,
                                                  right: 8,
                                                ),
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF6366F1),
                                                  shape: BoxShape.circle,
                                                ),
                                              )
                                            else
                                              const SizedBox(width: 16),
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor:
                                                  bgColors[colorIdx],
                                              child: Text(
                                                initial,
                                                style: TextStyle(
                                                  color: textColors[colorIdx],
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          sender,
                                                          style: TextStyle(
                                                            fontWeight: isRead
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .bold,
                                                            fontSize: 13,
                                                            color: const Color(
                                                              0xFF0F172A,
                                                            ),
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Text(
                                                        _formatDate(
                                                          email['date'],
                                                        ),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isRead
                                                              ? const Color(
                                                                  0xFF94A3B8,
                                                                )
                                                              : const Color(
                                                                  0xFF6366F1,
                                                                ),
                                                          fontWeight: isRead
                                                              ? FontWeight.w500
                                                              : FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    email['subject'] ?? '',
                                                    style: TextStyle(
                                                      fontWeight: isRead
                                                          ? FontWeight.w500
                                                          : FontWeight.bold,
                                                      fontSize: 13,
                                                      color: isRead
                                                          ? const Color(
                                                              0xFF64748B,
                                                            )
                                                          : const Color(
                                                              0xFF0F172A,
                                                            ),
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          email['snippet'] ??
                                                              '',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color: Color(
                                                                  0xFF94A3B8,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Icon(
                                                        Icons
                                                            .star_border_rounded,
                                                        size: 16,
                                                        color: isSelected
                                                            ? const Color(
                                                                0xFFA78BFA,
                                                              )
                                                            : const Color(
                                                                0xFFCBD5E1,
                                                              ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ))),
          ),
        ],
      ),
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
                    hintStyle: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Color(0xFF64748B),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
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
        final List<Map<String, dynamic>> emails = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

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
        top: isMobile ? 16 : 32, // reduced top on mobile
        bottom: 0, // no bottom padding — toolbar handles it
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
                style: TextStyle(
                  fontSize: isMobile ? 20 : 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (!isMobile)
                IconButton(
                  onPressed: () => _exitComposer(discard: false),
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  hoverColor: Colors.red.shade50,
                ),
            ],
          ),
          SizedBox(height: isMobile ? 16 : 32),

          // To field
          RecipientChipsInput(
            controller: _toController,
            label: "To",
            hint: "recipient@example.com",
            icon: Icons.person_outline_rounded,
            suggestions: _contactSuggestions,
            suffix: !_showCcBcc
                ? TextButton(
                    onPressed: () => setState(() => _showCcBcc = true),
                    child: const Text(
                      "Cc",
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : null,
          ),
          if (_showCcBcc) ...[
            const SizedBox(height: 10),
            RecipientChipsInput(
              controller: _ccController,
              label: "Cc",
              hint: "carbon.copy@example.com",
              icon: Icons.people_outline_rounded,
              suggestions: _contactSuggestions,
              suffix: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
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
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Color(0xFF334155),
                ),
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
                              label: Text(
                                entry.value.name,
                                style: const TextStyle(fontSize: 12),
                              ),
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
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 22,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.white,
                        ),
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
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.text_format,
                            color: Color(0xFF444746),
                            size: 20,
                          ),
                          tooltip: "Formatting",
                        ),
                        IconButton(
                          onPressed: _pickAttachments,
                          icon: const Icon(
                            Icons.attach_file,
                            color: Color(0xFF444746),
                            size: 20,
                          ),
                          tooltip: "Attach",
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.link,
                            color: Color(0xFF444746),
                            size: 20,
                          ),
                          tooltip: "Link",
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_outlined,
                            color: Color(0xFF444746),
                            size: 20,
                          ),
                          tooltip: "Emoji",
                        ),
                        IconButton(
                          onPressed: () => _exitComposer(discard: true),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFF444746),
                            size: 20,
                          ),
                          tooltip: "Discard",
                        ),
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
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
              Icon(
                Icons.email_outlined,
                size: 64,
                color: const Color(0xFFCBD5E1),
              ),
              const SizedBox(height: 16),
              const Text(
                "No message selected",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Select an email from the list to read it here.",
                style: TextStyle(color: Color(0xFFCBD5E1)),
              ),
            ],
          ),
        ),
      );
    }

    final email = _folders[_selectedFolder]![_selectedEmailIndex!];
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    if (_isLoadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    final String sender = email['sender'] ?? 'Unknown';
    final initial = sender.isNotEmpty
        ? sender.substring(0, 1).toUpperCase()
        : "U";
    final int colorHash = sender.codeUnits.fold(0, (a, b) => a + b);
    final List<Color> bgColors = [
      const Color(0xFFFEE2E2),
      const Color(0xFFFEF3C7),
      const Color(0xFFD1FAE5),
      const Color(0xFFDBEAFE),
      const Color(0xFFF3E8FF),
    ];
    final List<Color> textColors = [
      const Color(0xFFEF4444),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
    ];
    final colorIdx = colorHash % bgColors.length;

    return Container(
      key: key,
      color: Colors.white,
      padding: EdgeInsets.only(
        left: isMobile ? 16 : 32,
        right: isMobile ? 16 : 32,
        bottom: isMobile ? 20 : 28,
        top: 0,
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Subject + Action Bar (single row)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedEmailIndex = null),
                icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  email['subject'] ?? '(No Subject)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedFolder,
                  style: const TextStyle(
                    color: Color(0xFF7C3AED),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFF64748B),
                ),
                onPressed: _deleteSelectedEmail,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: Color(0xFF64748B),
                ),
                onPressed: () {
                  setState(() {
                    _folders[_selectedFolder]![_selectedEmailIndex!]['isRead'] = false;
                    _selectedEmailIndex = null;
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: const Icon(
                  Icons.print_outlined,
                  color: Color(0xFF64748B),
                ),
                onPressed: () {
                  final email = _folders[_selectedFolder]![_selectedEmailIndex!];
                  String subject = email['subject'] ?? 'No Subject';
                  String senderName = email['sender'] ?? 'Unknown Sender';
                  String senderEmail = email['email'] ?? '';
                  String body = email['body'] ?? email['bodyPreview'] ?? 'No content';
                  String dateStr = _formatDate(email['date']);
                  
                  String htmlContent = '''
                    <div style="max-width: 800px; margin: 0 auto; font-family: sans-serif; color: #333;">
                      <h1 style="color: #0f172a; border-bottom: 1px solid #e2e8f0; padding-bottom: 16px;">$subject</h1>
                      <div style="margin-bottom: 24px; color: #64748b;">
                        <strong>From:</strong> $senderName &lt;$senderEmail&gt;<br>
                        <strong>Date:</strong> $dateStr
                      </div>
                      <div style="line-height: 1.6; color: #1e293b; white-space: pre-wrap;">
                        $body
                      </div>
                    </div>
                  ''';
                  printHtmlWeb(subject, htmlContent);
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: Color(0xFF64748B),
                ),
                onPressed: () {
                  final email = _folders[_selectedFolder]![_selectedEmailIndex!];
                  String subject = email['subject'] ?? 'No Subject';
                  String senderName = email['sender'] ?? 'Unknown Sender';
                  String senderEmail = email['email'] ?? '';
                  String dateStr = _formatDate(email['date']);
                  String toEmail = (email['toName'] != null &&
                          email['toName'].toString().isNotEmpty)
                      ? "${email['toName']} <${email['toEmail'] ?? ''}>"
                      : (_userEmail.isNotEmpty ? _userEmail : "me");
                  String content = email['content'] ?? email['body'] ?? email['bodyPreview'] ?? 'No content';

                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          width: 800,
                          height: MediaQuery.of(context).size.height * 0.85,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      subject,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                                    onPressed: () => Navigator.of(context).pop(),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFFDBEAFE),
                                    child: Text(
                                      senderName.isNotEmpty ? senderName[0].toUpperCase() : 'U',
                                      style: const TextStyle(
                                        color: Color(0xFF1E40AF),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "$senderName <$senderEmail>",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          "to $toEmail",
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    dateStr,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(color: Color(0xFFE2E8F0), height: 1),
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  physics: const BouncingScrollPhysics(),
                                  child: _buildContentWidget(content),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Sender Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: bgColors[colorIdx],
                child: Text(
                  initial,
                  style: TextStyle(
                    color: textColors[colorIdx],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sender,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => setState(
                        () => _showEmailDetails = !_showEmailDetails,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            "to me",
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: Color(0xFF94A3B8),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatDate(email['date']),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.reply_rounded, color: Color(0xFF64748B)),
                onPressed: () {
                  setState(() {
                    _isComposing = false;
                    _isReplyingInline = true;
                    _isForwardingInline = false;
                    _toController.text =
                        email['email'] ?? email['sender'] ?? '';
                    _subjectController.text = email['subject'] != null
                        ? (email['subject'].toString().startsWith('Re:')
                              ? email['subject']
                              : 'Re: ${email['subject']}')
                        : 'Re:';
                    _contentController.clear();
                    _attachments = [];
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                onPressed: () {},
              ),
            ],
          ),
          if (_showEmailDetails) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.only(left: 60),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildDetailRow("from:", "$sender <${email['email'] ?? ''}>"),
                  _buildDetailRow(
                    "to:",
                    (email['toName'] != null &&
                            email['toName'].toString().isNotEmpty)
                        ? "${email['toName']} <${email['toEmail'] ?? ''}>"
                        : (_userEmail.isNotEmpty ? _userEmail : "me"),
                  ),
                  _buildDetailRow("date:", email['date'] ?? ''),
                  _buildDetailRow("subject:", email['subject'] ?? ''),
                ],
              ),
            ),
          ],
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContentWidget(email['content'] ?? ''),
                  if (email['attachments'] != null &&
                      (email['attachments'] as List).isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.attach_file,
                          color: Color(0xFF64748B),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Attachments (${(email['attachments'] as List).length})",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: (email['attachments'] as List).map<Widget>((
                        att,
                      ) {
                        final String fileName =
                            att['fileName'] ?? 'Unnamed File';
                        final String contentType =
                            att['contentType'] ?? 'application/octet-stream';

                        return InkWell(
                          onTap: () => _fetchAndDownloadAttachment(email, att),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 260),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: Color(0xFF4F46E5),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        fileName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E293B),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        contentType
                                            .split('/')
                                            .last
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF94A3B8),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.download_rounded,
                                  color: Color(0xFF64748B),
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (!_isReplyingInline)
                    Padding(
                      padding: const EdgeInsets.only(top: 40, bottom: 20),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isComposing = false;
                                _isReplyingInline = true;
                                _isForwardingInline = false;
                                _toController.text =
                                    email['email'] ?? email['sender'] ?? '';
                                _subjectController.text =
                                    email['subject'] != null
                                    ? (email['subject'].toString().startsWith(
                                            'Re:',
                                          )
                                          ? email['subject']
                                          : 'Re: ${email['subject']}')
                                    : 'Re:';
                                _contentController.clear();
                                _attachments = [];
                              });
                            },
                            icon: const Icon(Icons.reply_rounded, size: 18),
                            label: const Text(
                              "Reply",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.reply_all_rounded, size: 18),
                            label: const Text(
                              "Reply all",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => _setupForwardInline(email),
                            icon: const Icon(Icons.forward_rounded, size: 18),
                            label: const Text(
                              "Forward",
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF475569),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_isReplyingInline) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    ),
                    _buildInlineReplyEditor(email),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
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
      padding: EdgeInsets.all(_isForwardingInline ? 12 : 16),
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
                  sender.isNotEmpty
                      ? sender.substring(0, 1).toUpperCase()
                      : 'U',
                  style: const TextStyle(
                    color: Color(0xFF4F46E5),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isForwardingInline
                          ? "Forward Message"
                          : "Reply to $sender",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (!_isForwardingInline && emailAddress.isNotEmpty)
                      Text(
                        emailAddress,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
                onPressed: () {
                  setState(() {
                    _isReplyingInline = false;
                    _isForwardingInline = false;
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
          SizedBox(height: _isForwardingInline ? 8 : 12),
          if (_isForwardingInline) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFCBD5E1).withOpacity(0.7),
                ),
              ),
              child: RecipientChipsInput(
                controller: _toController,
                label: "To",
                hint: "recipient@example.com",
                icon: Icons.person_outline_rounded,
                suggestions: _contactSuggestions,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  labelText: "To",
                  prefixIcon: Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ],

          // Message Body Field
          Container(
            constraints: BoxConstraints(
              minHeight: _isForwardingInline ? 60 : 100,
              maxHeight: _isForwardingInline ? 90 : 180,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFCBD5E1).withOpacity(0.7),
              ),
            ),
            child: TextField(
              controller: _contentController,
              maxLines: null,
              autofocus: true,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF334155),
              ),
              decoration: InputDecoration(
                hintText: _isForwardingInline
                    ? "Add comments to forwarded message..."
                    : "Write your reply here...",
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
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

          SizedBox(height: _isForwardingInline ? 8 : 12),

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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.attach_file_rounded,
                      color: Color(0xFF475569),
                      size: 20,
                    ),
                    onPressed: _pickAttachments,
                    tooltip: "Attach file",
                  ),
                ],
              ),

              // Discard Button
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFFF5F56),
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isReplyingInline = false;
                    _isForwardingInline = false;
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
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiButton(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    BoxConstraints? constraints,
    double size = 20,
  }) {
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
                  child: Container(
                    color: Colors.transparent,
                    width: double.infinity,
                    height: double.infinity,
                  ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: const TextField(
                                decoration: InputDecoration(
                                  hintText: "Search emojis",
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  border: InputBorder.none,
                                  icon: Icon(
                                    Icons.search,
                                    size: 16,
                                    color: Color(0xFF94A3B8),
                                  ),
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
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 18,
                                  color: Color(0xFF2563EB),
                                ),
                                Icon(
                                  Icons.emoji_emotions_outlined,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                Icon(
                                  Icons.people_outline_rounded,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                Icon(
                                  Icons.pets_outlined,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                Icon(
                                  Icons.fastfood_outlined,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                Icon(
                                  Icons.directions_car_outlined,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                                Icon(
                                  Icons.lightbulb_outline_rounded,
                                  size: 18,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 24),
                          // Emoji Grid
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              children: [
                                const Text(
                                  "RECENTLY USED",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildEmojiGrid([
                                  "😀",
                                  "❤️",
                                  "👍",
                                  "🔥",
                                  "🎉",
                                  "😮",
                                ]),
                                const SizedBox(height: 20),
                                const Text(
                                  "SMILEYS AND EMOTIONS",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildEmojiGrid([
                                  "😀",
                                  "😃",
                                  "😄",
                                  "😁",
                                  "😆",
                                  "😅",
                                  "😂",
                                  "🤣",
                                  "🙂",
                                  "🙃",
                                  "😉",
                                  "😊",
                                  "😇",
                                  "😍",
                                  "🤩",
                                  "😘",
                                  "😗",
                                  "😚",
                                  "😙",
                                  "😋",
                                  "😛",
                                  "😜",
                                  "🤪",
                                  "😝",
                                ]),
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
      icon: Icon(
        Icons.add_reaction_outlined,
        color: const Color(0xFF475569),
        size: size,
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: emojis
          .map(
            (e) => GestureDetector(
              onTap: () {
                setState(() => _selectedReaction = e);
                Navigator.pop(context);
              },
              child: Text(e, style: const TextStyle(fontSize: 24)),
            ),
          )
          .toList(),
    );
  }

  Widget _buildContentWidget(String content) {
    final String trimmed = content.trim();
    final bool isHtml =
        trimmed.contains('<html') ||
        trimmed.contains('<body') ||
        trimmed.contains('<div') ||
        trimmed.contains('<p') ||
        trimmed.contains('<table') ||
        trimmed.contains('<br') ||
        trimmed.contains('</');

    String processedContent;
    if (isHtml) {
      processedContent =
          '<style>'
              'table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 14px; }'
              'th, td { border: 1px solid #CBD5E1; padding: 8px 10px; text-align: left; }'
              'th { background-color: #F1F5F9; font-weight: 600; color: #1E293B; }'
              '</style>' +
          trimmed;
    } else {
      processedContent =
          '<div style="white-space: pre-wrap; font-family: sans-serif; font-size: 14px; color: #334155;">${_escapeHtml(trimmed)}</div>';
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
        final formattedTime = timeParts.length >= 2
            ? "${timeParts[0]}:${timeParts[1]}"
            : time;
        return "$month $day, $year $formattedTime";
      }
    } catch (_) {}
    return dateStr;
  }
}

class RecipientChipsInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Widget? suffix;
  final InputDecoration? decoration;
  final List<String> suggestions;

  const RecipientChipsInput({
    Key? key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.suffix,
    this.decoration,
    this.suggestions = const [],
  }) : super(key: key);

  @override
  State<RecipientChipsInput> createState() => _RecipientChipsInputState();
}

class _RecipientChipsInputState extends State<RecipientChipsInput> {
  final List<String> _chips = [];
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _parseChipsFromController();
    widget.controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _addEmails(_textController.text);
    }
    setState(() {});
  }

  void _parseChipsFromController() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      _chips.clear();
      _chips.addAll(_parseEmails(text));
    }
  }

  void _onControllerChanged() {
    final currentText = widget.controller.text.trim();
    final List<String> allItems = List.from(_chips);
    final pendingText = _textController.text.trim();
    if (pendingText.isNotEmpty) {
      allItems.add(pendingText);
    }
    final serializedChips = allItems.join(', ');
    if (currentText != serializedChips) {
      setState(() {
        if (currentText.isEmpty) {
          _chips.clear();
          _textController.clear();
        } else {
          _chips.clear();
          _chips.addAll(_parseEmails(currentText));
          _textController.clear();
        }
      });
    }
  }

  void _updateController() {
    final pendingText = _textController.text.trim();
    final List<String> allItems = List.from(_chips);
    if (pendingText.isNotEmpty) {
      allItems.add(pendingText);
    }
    final serialized = allItems.join(', ');
    if (widget.controller.text != serialized) {
      widget.controller.removeListener(_onControllerChanged);
      widget.controller.text = serialized;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  List<String> _parseEmails(String text) {
    if (text.trim().isEmpty) return [];
    final parts = text.split(RegExp(r'[,;\s]+'));
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  void _addEmails(String text) {
    final parsed = _parseEmails(text);
    if (parsed.isNotEmpty) {
      setState(() {
        _chips.addAll(parsed);
        _textController.clear();
        _updateController();
      });
    }
  }

  void _onInputChanged(String val) {
    if (val.contains(',') || val.contains(';') || val.endsWith(' ')) {
      _addEmails(val);
    } else {
      _updateController();
    }
  }

  void _onInputSubmitted(String val) {
    _addEmails(val);
  }

  String _resolveDisplayName(String email) {
    final cleanEmail = email.trim().toLowerCase();
    final Map<String, String> knownContacts = {
      'regis.raj@botsedge.ai': 'Regis Raj',
      'poli.nishithareddy@botsedge.ai': 'Poli Nishitha Reddy',
    };
    if (knownContacts.containsKey(cleanEmail)) {
      return knownContacts[cleanEmail]!;
    }

    final match = RegExp(r'(.*?)\s*<(.*?)>').firstMatch(email);
    if (match != null) {
      String name = match.group(1)!.trim();
      if (name.isNotEmpty) return name;
    }

    if (cleanEmail.contains('@')) {
      final localPart = cleanEmail.split('@').first;
      final parts = localPart.split(RegExp(r'[\._-]'));
      final capitalizedParts = parts
          .map((part) {
            if (part.isEmpty) return '';
            return part[0].toUpperCase() + part.substring(1);
          })
          .where((element) => element.isNotEmpty)
          .toList();

      if (capitalizedParts.isNotEmpty) {
        return capitalizedParts.join(' ');
      }
    }
    return email;
  }

  Widget _buildChip(String email) {
    final displayName = _resolveDisplayName(email);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 6),
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() {
                _chips.remove(email);
                _updateController();
              });
            },
            child: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration effectiveDecoration =
        (widget.decoration ??
                InputDecoration(
                  labelText: widget.label,
                  prefixIcon: Icon(
                    widget.icon,
                    size: 20,
                    color: const Color(0xFF94A3B8),
                  ),
                  suffixIcon: widget.suffix,
                  labelStyle: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF2563EB),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ))
            .copyWith(hintText: _chips.isEmpty ? widget.hint : '');

    final String val = _textController.text.trim().toLowerCase();
    final List<String> matchingSuggestions = widget.suggestions
        .where((s) => s.toLowerCase().contains(val) && !_chips.contains(s))
        .toList();
    final bool showSuggestions = _focusNode.hasFocus && val.isNotEmpty && matchingSuggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: InputDecorator(
            decoration: effectiveDecoration,
            isEmpty: _chips.isEmpty && _textController.text.isEmpty,
            isFocused: _focusNode.hasFocus,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._chips.map((email) => _buildChip(email)),
                    Container(
                      constraints: const BoxConstraints(minWidth: 80),
                      child: IntrinsicWidth(
                        child: Focus(
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.backspace) {
                              if (_textController.text.isEmpty &&
                                  _chips.isNotEmpty) {
                                setState(() {
                                  _chips.removeLast();
                                  _updateController();
                                });
                                return KeyEventResult.handled;
                              }
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            onChanged: _onInputChanged,
                            onSubmitted: _onInputSubmitted,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showSuggestions) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: matchingSuggestions.length,
                itemBuilder: (context, idx) {
                  final sug = matchingSuggestions[idx];
                  return ListTile(
                    dense: true,
                    title: Text(
                      sug,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _chips.add(sug);
                        _textController.clear();
                        _updateController();
                      });
                    },
                    hoverColor: const Color(0xFFF1F5F9),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SkeletonMessageList extends StatefulWidget {
  const SkeletonMessageList({super.key});

  @override
  State<SkeletonMessageList> createState() => _SkeletonMessageListState();
}

class _SkeletonMessageListState extends State<SkeletonMessageList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(
      begin: 0.35,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(opacity: _opacityAnimation.value, child: child);
      },
      child: SingleChildScrollView(
        child: Column(
          children: List.generate(6, (index) => _buildSkeletonItem()),
        ),
      ),
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Circle Avatar Placeholder
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          // Texts Placeholder
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sender Name
                Container(
                  width: 100,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                // Subject
                Container(
                  width: 180,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // Snippet
                Container(
                  width: double.infinity,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
