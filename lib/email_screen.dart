import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

class EmailHomeScreen extends StatefulWidget {
  const EmailHomeScreen({super.key});

  @override
  State<EmailHomeScreen> createState() => _EmailHomeScreenState();
}

class _EmailHomeScreenState extends State<EmailHomeScreen> {
  String _selectedApp = "Mail";
  String _selectedFolder = "Inbox";
  int? _selectedEmailIndex;
  bool _isComposing = false;
  bool _showEmailDetails = false;
  bool _isMoreExpanded = false;
  bool _isStarred = false;
  String? _selectedReaction;

  final TextEditingController _toController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  List<PlatformFile> _attachments = [];

  final Map<String, List<Map<String, dynamic>>> _folders = {
    "Inbox": [],
    "Starred": [],
    "Snoozed": [],
    "Sent": [],
    "Drafts": [],
    "Purchases": [],
    "Important": [],
    "Scheduled": [],
    "All Mail": [],
    "Spam": [],
    "Trash": [],
    "Outbox": [],
  };

  @override
  void initState() {
    super.initState();
    _folders["Inbox"]!.add({
      "sender": "Google",
      "email": "no-reply@accounts.google.com",
      "date": "10:53 AM",
      "subject": "Security Alert",
      "snippet": "New sign-in detected...",
      "content": "Hi there, a new device signed into your account. If it wasn't you, secure your account.",
      "isRead": false,
    });
    _fetchInboxFromBackend();
  }

  Future<void> _fetchInboxFromBackend() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:8080/api/email/inbox'));
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
      final response = await http.get(Uri.parse('http://localhost:8080/api/email/sent'));
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
  }

  void _startCompose() {
    setState(() {
      _toController.clear();
      _subjectController.clear();
      _contentController.clear();
      _attachments = [];
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
       final response = await http.post(
          Uri.parse('http://localhost:8080/api/email/send'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
             'to': to,
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
     if (_selectedEmailIndex == null || _selectedFolder == "Trash") return;
     final list = _folders[_selectedFolder]!;
     final emailToDelete = list.removeAt(_selectedEmailIndex!);
     setState(() {
        _folders["Trash"]?.insert(0, emailToDelete);
        _selectedEmailIndex = null;
     });
     _showSnackBar("Moved to Trash");
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), 
      body: Column(
        children: [
          _buildAppTopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildThinRail(),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(24)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
                      child: Row(
                         crossAxisAlignment: CrossAxisAlignment.stretch,
                         children: [
                            if (_selectedApp == "Mail") ...[
                              SizedBox(width: 260, child: _buildFolderSidebar()),
                              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                              SizedBox(width: 380, child: _buildMessageList()),
                              const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                              Expanded(child: _isComposing ? _buildComposeView() : _buildMessageDetail()),
                            ] else ...[
                               Expanded(child: Center(child: Text("$_selectedApp View")))
                            ]
                         ],
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

  Widget _buildAppTopBar() {
    return Container(
      height: 48,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
          const Text("Botsedge Workspace", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Icon(Icons.search, size: 18, color: Colors.white54),
          const SizedBox(width: 20),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRailIcon(IconData icon, String appName) {
    final isSelected = _selectedApp == appName;
    return InkWell(
      onTap: () => setState(() => _selectedApp = appName),
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
                CircleAvatar(radius: 20, backgroundColor: const Color(0xFFE0E7FF), child: const Text("FA", style: TextStyle(color: Color(0xFF4338CA), fontWeight: FontWeight.bold))),
                const SizedBox(width: 12),
                const Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                      Text("Fazil Asharf", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text("Online", style: TextStyle(fontSize: 10, color: Colors.green)),
                   ],
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
                _buildFolderItem("Starred", Icons.star_outline_rounded),
                _buildFolderItem("Snoozed", Icons.access_time_rounded),
                _buildFolderItem("Sent", Icons.send_rounded),
                _buildFolderItem("Drafts", Icons.insert_drive_file_rounded),
                _buildFolderItem("Purchases", Icons.shopping_bag_outlined),
                
                if (!_isMoreExpanded)
                  _buildFolderActionItem("More", Icons.keyboard_arrow_down_rounded, () {
                    setState(() => _isMoreExpanded = true);
                  })
                else ...[
                  _buildFolderActionItem("Less", Icons.keyboard_arrow_up_rounded, () {
                    setState(() => _isMoreExpanded = false);
                  }),
                  _buildFolderItem("Important", Icons.label_important_outline_rounded),
                  _buildFolderItem("Scheduled", Icons.schedule_send_outlined),
                  _buildFolderItem("All Mail", Icons.mail_outline_rounded),
                  _buildFolderItem("Spam", Icons.report_gmailerrorred_rounded, count: "4"),
                  _buildFolderItem("Trash", Icons.delete_outline_rounded),
                  const SizedBox(height: 8),
                  _buildFolderActionItem("Manage subscriptions", Icons.unsubscribe_outlined, () {}),
                  _buildFolderActionItem("Manage labels", Icons.settings_outlined, () {}),
                  _buildFolderActionItem("Create new label", Icons.add_rounded, () {}),
                ],

                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Labels", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
                      Icon(Icons.add, size: 20, color: const Color(0xFF64748B)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildFolderItem("[Imap]/Sent", Icons.label_important_outline_rounded),
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
    );
  }

  Widget _buildFolderActionItem(String title, IconData icon, VoidCallback onTap) {
     return ListTile(
        leading: Icon(icon, size: 20, color: const Color(0xFF64748B)),
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1E293B))),
        onTap: onTap,
        dense: true,
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

  Widget _buildComposeView() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "New Message",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _isComposing = false),
                icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                hoverColor: Colors.red.shade50,
              ),
            ],
          ),
          const SizedBox(height: 32),
          // To Field
          _buildStyledInput(
            controller: _toController,
            label: "To",
            hint: "recipient@example.com",
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 16),
          // Subject Field
          _buildStyledInput(
            controller: _subjectController,
            label: "Subject",
            hint: "Enter message subject",
            icon: Icons.subject_rounded,
          ),
          const SizedBox(height: 24),
          // Attachment Chips
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                children: _attachments.asMap().entries.map((entry) {
                  return Chip(
                    label: Text(entry.value.name, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => _removeAttachment(entry.key),
                    deleteIconColor: Colors.red,
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  );
                }).toList(),
              ),
            ),
          // Message Content
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _contentController,
                maxLines: null,
                style: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFF334155)),
                decoration: const InputDecoration(
                  hintText: "Write your message here...",
                  hintStyle: TextStyle(color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Bottom Bar
          Row(
            children: [
              ElevatedButton(
                onPressed: _sendEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  children: [
                    Text("Send Message", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(width: 8),
                    Icon(Icons.send_rounded, size: 18),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: _pickAttachments,
                icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF64748B)),
                tooltip: "Attach files",
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _isComposing = false),
                child: const Text("Discard", style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStyledInput({required TextEditingController controller, required String label, String? hint, required IconData icon}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
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

  Widget _buildMessageDetail() {
    if (_selectedEmailIndex == null) {
      return Container(
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
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  email['subject'] ?? '(No Subject)',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.5),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(onPressed: () {}, icon: const Icon(Icons.print_outlined, color: Color(0xFF64748B), size: 18)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF64748B), size: 18)),
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
              child: Text(
                email['content'] ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Color(0xFF334155),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          // Bottom Actions
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
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
                const SizedBox(width: 12),
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
