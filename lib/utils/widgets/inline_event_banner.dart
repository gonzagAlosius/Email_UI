import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class InlineEventBanner extends StatefulWidget {
  final Map<String, dynamic> email;
  final Map<String, dynamic> attachment;
  final String selectedFolder;
  final void Function(Map<String, dynamic>, String) onRsvp;
  final void Function(DateTime) onCheckCalendar;

  const InlineEventBanner({
    super.key,
    required this.email,
    required this.attachment,
    required this.selectedFolder,
    required this.onRsvp,
    required this.onCheckCalendar,
  });

  @override
  State<InlineEventBanner> createState() => _InlineEventBannerState();
}

class _InlineEventBannerState extends State<InlineEventBanner> {
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic>? _eventDetails;
  String? _rsvpStatus;

  @override
  void initState() {
    super.initState();
    _loadIcsData();
    _loadRsvpStatus();
  }

  Future<void> _loadRsvpStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? status = prefs.getString('rsvp_${widget.email['uid']}');
    if (status != null && mounted) {
      setState(() {
        _rsvpStatus = status;
      });
    }
  }

  String? _getMailPassword(SharedPreferences prefs) {
    bool isOAuth = prefs.getBool('is_microsoft_login') == true ||
        prefs.getBool('is_google_login') == true;
    if (isOAuth) {
      return prefs.getString('password');
    } else {
      return prefs.getString('mail_password');
    }
  }

  Future<void> _loadIcsData() async {
    String base64Data = widget.attachment['base64Data'] ?? '';
    
    if (base64Data.isEmpty) {
      // Need to fetch it
      try {
        final String fileName = widget.attachment['fileName'] ?? 'Unnamed File';
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? userEmail = prefs.getString('email');
        String? password = _getMailPassword(prefs);
        if (userEmail == null) {
          setState(() {
            _error = 'User not logged in';
            _isLoading = false;
          });
          return;
        }

        final Map<String, String> headers = {'X-Email': userEmail};
        if (password != null && password.isNotEmpty) {
          headers['X-Password'] = password;
        }

        final response = await http.get(
          Uri.parse(
            '${AppConfig.instance.baseUrl}/email/attachment?folder=${widget.selectedFolder}&uid=${widget.email['uid']}&fileName=${Uri.encodeComponent(fileName)}',
          ),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> resData = jsonDecode(response.body);
          base64Data = resData['base64Data'] ?? '';
          if (base64Data.isNotEmpty) {
            widget.attachment['base64Data'] = base64Data; // Cache it
          } else {
            setState(() {
              _error = 'Empty ICS data received';
              _isLoading = false;
            });
            return;
          }
        } else {
          setState(() {
            _error = 'Failed to fetch attachment (HTTP ${response.statusCode})';
            _isLoading = false;
          });
          return;
        }
      } catch (e) {
        setState(() {
          _error = 'Error fetching ICS: $e';
          _isLoading = false;
        });
        return;
      }
    }

    // Now parse base64Data
    try {
      String icsContent = utf8.decode(base64Decode(base64Data));
      _parseIcsContent(icsContent);
    } catch (e) {
      setState(() {
        _error = 'Error parsing ICS data: $e';
        _isLoading = false;
      });
    }
  }

  void _parseIcsContent(String icsContent) {
    String? title;
    String? dtStartStr;
    String? dtEndStr;
    String? location;
    String? meeturl;
    bool isCancelled = false;

    List<String> lines = icsContent.split('\n');
    for (String line in lines) {
      line = line.trim();
      if (line.startsWith('SUMMARY:')) {
        title = line.substring(8);
      } else if (line.startsWith('DTSTART')) {
        int colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          dtStartStr = line.substring(colonIdx + 1);
        }
      } else if (line.startsWith('DTEND')) {
        int colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          dtEndStr = line.substring(colonIdx + 1);
        }
      } else if (line.startsWith('LOCATION:')) {
        location = line.substring(9).replaceAll('\\,', ',');
      } else if (line.startsWith('X-GOOGLE-CONFERENCE:')) {
        meeturl = line.substring(20);
      } else if (line.startsWith('METHOD:CANCEL') || line.startsWith('STATUS:CANCELLED')) {
        isCancelled = true;
      }
    }

    if (meeturl == null && location != null && (location.startsWith('http://') || location.startsWith('https://'))) {
      meeturl = location;
      location = "Online Meeting";
    }

    DateTime startTime = DateTime.now();
    if (dtStartStr != null) {
      String clean = dtStartStr.replaceAll(RegExp(r'[^0-9T]'), '');
      if (clean.length >= 15) {
        startTime = DateTime(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
          int.parse(clean.substring(9, 11)),
          int.parse(clean.substring(11, 13)),
          int.parse(clean.substring(13, 15)),
        );
      } else if (clean.length == 8) {
        startTime = DateTime(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
        );
      }
    }

    DateTime endTime = startTime.add(const Duration(hours: 1));
    if (dtEndStr != null) {
      String clean = dtEndStr.replaceAll(RegExp(r'[^0-9T]'), '');
      if (clean.length >= 15) {
        endTime = DateTime(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
          int.parse(clean.substring(9, 11)),
          int.parse(clean.substring(11, 13)),
          int.parse(clean.substring(13, 15)),
        );
      } else if (clean.length == 8) {
        endTime = DateTime(
          int.parse(clean.substring(0, 4)),
          int.parse(clean.substring(4, 6)),
          int.parse(clean.substring(6, 8)),
        );
      }
    }

    setState(() {
      _eventDetails = {
        'title': title ?? 'Event Invitation',
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location ?? '',
        'meeturl': meeturl ?? '',
        'isCancelled': isCancelled,
      };
      _isLoading = false;
    });
  }

  void _handleRsvpAction(String action) async {
    setState(() {
      _rsvpStatus = action;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('rsvp_${widget.email['uid']}', action);
  }

  void _handleRsvp(String status, String backendStatus) {
    _handleRsvpAction(status.toLowerCase());
    widget.onRsvp(_eventDetails!, backendStatus);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF9C4), // Light yellow
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFF59D)),
        ),
        child: const Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text("Loading event invitation...", style: TextStyle(color: Color(0xFF333333))),
          ],
        ),
      );
    }

    if (_error.isNotEmpty) {
      return const SizedBox.shrink(); // Hide silently on error, or show error if preferred
    }

    final title = _eventDetails!['title'];
    final startTime = DateTime.parse(_eventDetails!['startTime']);
    final endTime = DateTime.parse(_eventDetails!['endTime']);
    final location = _eventDetails!['location'];
    final meeturl = _eventDetails!['meeturl'];

    String formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(startTime);
    formattedDate += ' - ${DateFormat('HH:mm').format(endTime)}';
    
    // Attempt to get timezone if possible, else default to local
    formattedDate += ' (${DateTime.now().timeZoneName})';

    String displayLocation = location.toString();
    if (meeturl.toString().isNotEmpty) {
      displayLocation = meeturl;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4), // Classic Roundcube yellow
        border: Border.all(color: const Color(0xFFFBC02D).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Column(
                  children: [
                    Container(
                      color: Colors.red.shade400,
                      height: 8,
                      width: 24,
                      margin: const EdgeInsets.only(bottom: 2),
                    ),
                    Text(
                      startTime.day.toString().padLeft(2, '0'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow("Invitation to", title),
                    const SizedBox(height: 4),
                    _buildDetailRow("Date", formattedDate),
                    if (displayLocation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildDetailRow("Location", displayLocation),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_eventDetails!['isCancelled'] == true)
            Row(
              children: [
                Icon(Icons.cancel, color: Colors.red.shade600, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "This event has been cancelled",
                  style: TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            )
          else if (_rsvpStatus != null)
            Row(
              children: [
                Icon(
                  _rsvpStatus == 'accepted' 
                      ? Icons.check_circle 
                      : (_rsvpStatus == 'declined' ? Icons.cancel : Icons.info),
                  color: _rsvpStatus == 'accepted' 
                      ? Colors.green.shade600 
                      : (_rsvpStatus == 'declined' ? Colors.red.shade600 : Colors.blue.shade600),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  "You have $_rsvpStatus this invitation",
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 15,
                  ),
                ),
              ],
            )
          else ...[
            const Text("Do you accept this invitation?", style: TextStyle(color: Color(0xFF333333))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRsvpButton("Accept", () => _handleRsvp("accepted", "ACCEPTED")),
                _buildRsvpButton("Maybe", () => _handleRsvp("tentatively accepted", "TENTATIVE")),
                _buildRsvpButton("Decline", () => _handleRsvp("declined", "DECLINED")),
                _buildRsvpButton("Delegate", () => _handleRsvp("delegated", "DELEGATED")),
                _buildRsvpButton("Check Calendar", () => widget.onCheckCalendar(startTime)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFFFF176)),
          const SizedBox(height: 8),
          Text(
            "Agenda ${DateFormat('yyyy-MM-dd').format(startTime)}",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text("No earlier events", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                "${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text("No later events", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF333333)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Color(0xFF333333)),
          ),
        ),
      ],
    );
  }

  Widget _buildRsvpButton(String text, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        side: BorderSide(color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
