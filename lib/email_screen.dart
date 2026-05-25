import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'calendar_view.dart';
import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;

class EmailHomeScreen extends StatefulWidget {
  const EmailHomeScreen({super.key});

  @override
  State<EmailHomeScreen> createState() => _EmailHomeScreenState();
}

class _EmailHomeScreenState extends State<EmailHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedApp = "Mail";
  String _selectedFolder = "Inbox";
  int? _selectedEmailIndex;
  bool _isComposing = false;
  bool _showEmailDetails = false;
  bool _isStarred = false;
  String? _selectedReaction;

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
  void initState() {
    super.initState();
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
    _loadUserData();
    _fetchInboxFromBackend();
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

  Future<void> _fetchInboxFromBackend() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      String? password = prefs.getString('password');
      if (email == null || password == null) return;

      final response = await http.get(
        Uri.parse('http://localhost:8080/api/email/inbox'),
        headers: {'X-Email': email, 'X-Password': password},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> emails = data.map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _folders["Inbox"] = emails;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch inbox: $e");
    }
  }

  Future<void> _fetchSentFromBackend() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? email = prefs.getString('email');
      String? password = prefs.getString('password');
      if (email == null || password == null) return;

      final response = await http.get(
        Uri.parse('http://localhost:8080/api/email/sent'),
        headers: {'X-Email': email, 'X-Password': password},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<Map<String, dynamic>> emails = data.map((e) => Map<String, dynamic>.from(e)).toList();
        setState(() {
          _folders["Sent"] = emails;
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch sent messages: $e");
    }
  }

  void _selectFolder(String folder) {
    setState(() {
      _selectedFolder = folder;
      _isComposing = false;
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
    final to = _toController.text;
    if (to.isEmpty) return;
    
    final subject = _subjectController.text.isNotEmpty ? _subjectController.text : "(No Subject)";
    final content = _contentController.text;

    List<Map<String, String>> attachmentPayload = [];
    for (var file in _attachments) {
      if (file.bytes != null) {
        attachmentPayload.add({
          'fileName': file.name,
          'base64Content': base64Encode(file.bytes!),
        });
      }
    }

    try {
       SharedPreferences prefs = await SharedPreferences.getInstance();
       String? userEmail = prefs.getString('email');
       String? userPassword = prefs.getString('password');
       if (userEmail == null || userPassword == null) return;

       final response = await http.post(
          Uri.parse('http://localhost:8080/api/email/send'),
          headers: {'Content-Type': 'application/json', 'X-Email': userEmail, 'X-Password': userPassword},
           body: jsonEncode({
              'to': to,
              'cc': _ccController.text,
              'subject': subject,
              'content': content,
              'attachments': attachmentPayload,
           }),
       );
       if (response.statusCode == 200) {
          _showSnackBar("Email Sent successfully!");
          // Wait a moment for the server to sync then refresh
          Future.delayed(const Duration(seconds: 2), () => _fetchSentFromBackend());
       }
    } catch (e) {
       _showSnackBar("API Error: $e");
    }

    setState(() {
      _isComposing = false;
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
                          SharedPreferences prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
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
          mainContent = _buildMessageList();
        }
      } else if (_selectedApp == "Calendar") {
        mainContent = const CalendarView();
      } else {
        mainContent = Center(child: Text("$_selectedApp View"));
      }
    } else {
      mainContent = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop && _selectedApp == "Mail") SizedBox(width: 250, child: _buildFolderSidebar()),
          if (isDesktop && _selectedApp == "Mail") const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          
          if (_selectedApp == "Mail") 
            SizedBox(width: isTablet ? 320 : 360, child: _buildMessageList()),
          if (_selectedApp == "Mail") 
            const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          
          if (_selectedApp == "Mail")
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.01),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _isComposing 
                  ? _buildComposeView(key: const ValueKey('compose')) 
                  : _buildMessageDetail(key: const ValueKey('detail')),
              ),
            )
          else if (_selectedApp == "Calendar")
            const Expanded(child: CalendarView())
          else
            Expanded(child: Center(child: Text("$_selectedApp View"))),
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F172A),
      drawer: isDesktop ? null : Drawer(
        child: Row(
          children: [
            _buildThinRail(),
            Expanded(child: _buildFolderSidebar()),
          ],
        ),
      ),
      body: Column(
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
                      child: mainContent,
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

  Widget _buildAppTopBar(bool isDesktop) {
    return Container(
      height: 48,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isDesktop) ...[
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 16),
          ],
          if (isDesktop) Row(
            children: [
              Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
              const SizedBox(width: 24),
            ],
          ),
          const Flexible(
            child: Text(
              "Botsedge Workspace", 
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          const Icon(Icons.search, size: 18, color: Colors.white54),
          const SizedBox(width: 16),
          const Icon(Icons.notifications_none, size: 20, color: Colors.white70),
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
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          Navigator.pop(context);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF94A3B8), size: 26),
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
    final List<Map<String, dynamic>> emails = _folders[_selectedFolder] ?? [];
    return Column(
      children: [
        Container(padding: const EdgeInsets.all(24), alignment: Alignment.centerLeft, child: Text(_selectedFolder, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const Divider(height: 1),
        Expanded(
          child: emails.isEmpty ? const Center(child: Text("No messages")) : ListView.separated(
            itemCount: emails.length,
            separatorBuilder: (c, i) => const Divider(height: 1, indent: 80),
            itemBuilder: (context, index) {
              final email = emails[index];
              final isSelected = index == _selectedEmailIndex && !_isComposing;
              final String sender = email['sender'] ?? 'Unknown';
              final bool isRead = email['isRead'] == true;

              return InkWell(
                onTap: () => setState(() { _selectedEmailIndex = index; _isComposing = false; email['isRead'] = true; }),
                child: Container(
                  color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      CircleAvatar(child: Text(sender.isNotEmpty ? sender.substring(0,1).toUpperCase() : "U")),
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
          ),
        ),
      ],
    );
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
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 48, vertical: isMobile ? 24 : 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                IconButton(
                  onPressed: () => setState(() => _selectedEmailIndex = null),
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF64748B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  email['subject'] ?? '(No Subject)',
                  style: TextStyle(fontSize: isMobile ? 22 : 28, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), letterSpacing: -0.5),
                ),
              ),
              if (!isMobile) const SizedBox(width: 24),
              if (!isMobile) IconButton(onPressed: () {}, icon: const Icon(Icons.print_outlined, color: Color(0xFF64748B), size: 18)),
              if (!isMobile) IconButton(onPressed: () {}, icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF64748B), size: 18)),
            ],
          ),
          Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _isStarred = !_isStarred),
                icon: Icon(
                  _isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _isStarred ? Colors.orange : const Color(0xFF64748B),
                  size: 20
                ),
              ),
              _buildEmojiButton(context),
              IconButton(onPressed: () => setState(() => _isComposing = true), icon: const Icon(Icons.reply_rounded, color: Color(0xFF64748B), size: 20)),
              IconButton(onPressed: _deleteSelectedEmail, icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20)),
            ],
          ),
          if (_selectedReaction != null) 
            Padding(
               padding: const EdgeInsets.only(top: 8, bottom: 8),
               child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                     Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                        child: Row(
                           children: [
                              Text(_selectedReaction!, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              const Text("1", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                           ],
                        ),
                     )
                  ],
               ),
            ),
          const SizedBox(height: 32),
          // Sender Info Row
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Text(
                  email['sender']?.toString().substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.bold, fontSize: 16),
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
                            email['sender'] ?? 'Unknown',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            "<${email['email'] ?? 'hidden'}>",
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () => setState(() => _showEmailDetails = !_showEmailDetails),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("to me", style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                          Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF64748B)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                email['date'] ?? '',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          // Detail Dropdown (Conditional)
          if (_showEmailDetails) ...[
             const SizedBox(height: 12),
             Container(
               margin: const EdgeInsets.only(left: 56),
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: Colors.white,
                 borderRadius: BorderRadius.circular(12),
                 border: Border.all(color: const Color(0xFFF1F5F9)),
                 boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
               ),
               child: Column(
                 children: [
                    _buildDetailRow("from:", "${email['sender']} <${email['email'] ?? ''}>"),
                    _buildDetailRow(
                      "to:", 
                      (email['toName'] != null && email['toName'].toString().isNotEmpty)
                          ? "${email['toName']} <${email['toEmail'] ?? ''}>"
                          : (_userEmail.isNotEmpty ? _userEmail : "me")
                    ),
                    _buildDetailRow("date:", email['date'] ?? ''),
                    _buildDetailRow("subject:", email['subject'] ?? ''),
                 ],
               ),
             ),
          ],
          const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Divider(color: Color(0xFFF1F5F9), thickness: 1)),
          // Body Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    email['content'] ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: Color(0xFF334155),
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (email['attachments'] != null && (email['attachments'] as List).isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(color: Color(0xFFF1F5F9), thickness: 1),
                    ),
                    const Text(
                      "Attachments",
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
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
                          onTap: () => _downloadAttachment(fileName, contentType, base64Data),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF2563EB), size: 20),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      fileName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      contentType,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.download_rounded, color: Color(0xFF64748B), size: 18),
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
          // Bottom Actions
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: const Text("Reply"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.forward_rounded, size: 18),
                  label: const Text("Forward"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF475569),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
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

  Widget _buildEmojiButton(BuildContext context) {
    return IconButton(
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
      icon: const Icon(Icons.add_reaction_outlined, color: Color(0xFF64748B), size: 20),
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

}
