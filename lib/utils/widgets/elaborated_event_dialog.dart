import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../web_helpers.dart';

Future<Map<String, String>> _getDialogHeaders() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? email = prefs.getString('email');
  bool isOAuth = prefs.getBool('is_microsoft_login') == true || prefs.getBool('is_google_login') == true;
  String? password = isOAuth ? prefs.getString('password') : prefs.getString('mail_password');
  
  final Map<String, String> headers = {};
  if (email != null) headers['X-Email'] = email;
  if (password != null) headers['X-Password'] = password;
  return headers;
}

class ElaboratedEventDialog extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback onEventDeleted;

  const ElaboratedEventDialog({
    super.key,
    required this.event,
    required this.onEventDeleted,
  });

  @override
  State<ElaboratedEventDialog> createState() => _ElaboratedEventDialogState();
}

class _ElaboratedEventDialogState extends State<ElaboratedEventDialog> {
  bool _isLoading = false;
  Map<String, dynamic>? _graphData;

  @override
  void initState() {
    super.initState();
    _fetchGraphData();
  }

  Future<void> _fetchGraphData() async {
    final graphId = widget.event['graphEventId'];
    if (graphId == null || graphId.toString().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final headers = await _getDialogHeaders();
      final response = await http.get(
        Uri.parse('${AppConfig.instance.calendarUrl}/events/graph/$graphId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _graphData = jsonDecode(response.body);
          });
        }
      } else {
        debugPrint("Failed to fetch graph data: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error fetching graph data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteEvent() async {
    final id = widget.event['id'];
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: Event ID is null')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final headers = await _getDialogHeaders();
      final calid = widget.event['calid'];
      final orgcode = widget.event['orgcode'];
      
      Uri url;
      if (calid != null && orgcode != null) {
        url = Uri.parse('${AppConfig.instance.calendarUrl}/events/$id?calid=$calid&orgcode=$orgcode');
      } else {
        url = Uri.parse('${AppConfig.instance.calendarUrl}/events/$id');
      }
      
      final response = await http.delete(
        url,
        headers: headers,
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event Deleted Successfully!')),
          );
          widget.onEventDeleted();
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete event: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting event: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTimeFull(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Unknown';
    final dt = DateTime.tryParse(timeStr);
    if (dt == null) return timeStr;
    return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dt);
  }

  String _formatTimeOnly(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    final dt = DateTime.tryParse(timeStr);
    if (dt == null) return '';
    return DateFormat('hh:mm a').format(dt);
  }

  String get _description {
    String desc = _graphData != null && _graphData!['bodyPreview'] != null 
        ? _graphData!['bodyPreview'] 
        : widget.event['description'] ?? '';
    if (desc.startsWith('Agenda:')) {
      desc = desc.substring(7).trim();
    }
    return desc;
  }

  void _copyTeamsLink() async {
    String? teamsLink;
    if (_graphData != null) {
      if (_graphData!['onlineMeetingUrl'] != null) {
        teamsLink = _graphData!['onlineMeetingUrl'].toString();
      } else if (_graphData!['onlineMeeting'] != null && _graphData!['onlineMeeting']['joinUrl'] != null) {
        teamsLink = _graphData!['onlineMeeting']['joinUrl'].toString();
      }
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final String meeturl = widget.event['meeturl'] ?? '';
      if (meeturl.isNotEmpty) {
        teamsLink = meeturl;
      }
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      teamsLink = _extractTeamsLink(_description);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localDesc = widget.event['description'] ?? '';
      teamsLink = _extractTeamsLink(localDesc);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localAgenda = widget.event['agenda'] ?? '';
      teamsLink = _extractTeamsLink(localAgenda);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localLocation = widget.event['location'] ?? '';
      if (localLocation.toString().contains('teams.microsoft.com')) {
        teamsLink = _extractTeamsLink(localLocation.toString());
      }
    }

    if (teamsLink != null && teamsLink.isNotEmpty) {
      teamsLink = teamsLink.trim();
      if (teamsLink.contains('teams.microsoft.com')) {
        final cleanRegExp = RegExp(r'(https://[^\s<>"]*teams\.microsoft\.com[^\s<>"]*)');
        final cleanMatch = cleanRegExp.firstMatch(teamsLink);
        if (cleanMatch != null) {
          teamsLink = cleanMatch.group(0);
        }
      }

      await Clipboard.setData(ClipboardData(text: teamsLink!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Teams link copied to clipboard:\n$teamsLink')),
              ],
            ),
            backgroundColor: Colors.blue.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Teams meeting link found to copy.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String? _extractTeamsLink(String text) {
    if (text.isEmpty) return null;
    final regExp = RegExp(r'(https://[^\s<>"]*teams\.microsoft\.com[^\s<>"]*)');
    final match = regExp.firstMatch(text);
    return match?.group(0);
  }

  void _joinTeamsMeeting() {
    String? teamsLink;
    if (_graphData != null) {
      if (_graphData!['onlineMeetingUrl'] != null) {
        teamsLink = _graphData!['onlineMeetingUrl'].toString();
      } else if (_graphData!['onlineMeeting'] != null && _graphData!['onlineMeeting']['joinUrl'] != null) {
        teamsLink = _graphData!['onlineMeeting']['joinUrl'].toString();
      }
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final String meeturl = widget.event['meeturl'] ?? '';
      if (meeturl.isNotEmpty) {
        teamsLink = meeturl;
      }
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      teamsLink = _extractTeamsLink(_description);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localDesc = widget.event['description'] ?? '';
      teamsLink = _extractTeamsLink(localDesc);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localAgenda = widget.event['agenda'] ?? '';
      teamsLink = _extractTeamsLink(localAgenda);
    }
    if (teamsLink == null || teamsLink.isEmpty) {
      final localLocation = widget.event['location'] ?? '';
      if (localLocation.toString().contains('teams.microsoft.com')) {
        teamsLink = _extractTeamsLink(localLocation.toString());
      }
    }

    if (teamsLink != null && teamsLink.isNotEmpty) {
      teamsLink = teamsLink.trim();
      if (teamsLink.contains('teams.microsoft.com')) {
        final cleanRegExp = RegExp(r'(https://[^\s<>"]*teams\.microsoft\.com[^\s<>"]*)');
        final cleanMatch = cleanRegExp.firstMatch(teamsLink);
        if (cleanMatch != null) {
          teamsLink = cleanMatch.group(0);
        }
      }
      openInNewTab(teamsLink!);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Teams meeting link found to open.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _downloadIcs() {
    final title = widget.event['title'] ?? 'Event';
    final startStr = widget.event['startTime'];
    final endStr = widget.event['endTime'];
    final desc = widget.event['description'] ?? '';
    final location = widget.event['location'] ?? '';
    final organizer = widget.event['organizerEmail'] ?? widget.event['organizer'] ?? 'Unknown';

    String formatIcsDate(String? dt) {
      if (dt == null || dt.isEmpty) return '';
      return dt.replaceAll('-', '').replaceAll(':', '') + 'Z';
    }

    String icsString = "BEGIN:VCALENDAR\n"
        "VERSION:2.0\n"
        "PRODID:-//BotsEdge//Calendar//EN\n"
        "BEGIN:VEVENT\n"
        "UID:${widget.event['id'] ?? DateTime.now().millisecondsSinceEpoch}\n"
        "DTSTAMP:${formatIcsDate(DateTime.now().toUtc().toIso8601String().split('.').first)}\n"
        "DTSTART:${formatIcsDate(startStr)}\n"
        "DTEND:${formatIcsDate(endStr)}\n"
        "SUMMARY:$title\n"
        "DESCRIPTION:${desc.replaceAll('\n', '\\n')}\n"
        "LOCATION:$location\n"
        "ORGANIZER;CN=$organizer:mailto:$organizer\n"
        "END:VEVENT\n"
        "END:VCALENDAR";
    final bytes = utf8.encode(icsString);
    final base64String = base64Encode(bytes);
    downloadFileWeb('${title.replaceAll(' ', '_')}.ics', 'text/calendar', base64String);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.event['title'] ?? 'No Title';
    final startTimeStr = widget.event['startTime'];
    final endTimeStr = widget.event['endTime'];
    final formattedStartFull = _formatTimeFull(startTimeStr);
    final formattedEndOnly = _formatTimeOnly(endTimeStr);

    String durationStr = "";
    if (startTimeStr != null && endTimeStr != null) {
      final startDt = DateTime.tryParse(startTimeStr);
      final endDt = DateTime.tryParse(endTimeStr);
      if (startDt != null && endDt != null) {
        final diff = endDt.difference(startDt);
        if (diff.inMinutes > 0 && diff.inMinutes < 60) {
          durationStr = "(${diff.inMinutes} minutes)";
        } else if (diff.inHours > 0) {
          int hours = diff.inHours;
          int mins = diff.inMinutes % 60;
          if (mins == 0) {
            durationStr = "($hours hour${hours > 1 ? 's' : ''})";
          } else {
            durationStr = "($hours hr $mins min)";
          }
        }
      }
    }

    final organizer = widget.event['organizerEmail'] ?? widget.event['organizer'] ?? 'Unknown';
    List<dynamic> graphAttendees = _graphData != null && _graphData!['attendees'] != null ? _graphData!['attendees'] : [];
    final attendeesCount = graphAttendees.isNotEmpty ? graphAttendees.length : (widget.event['attendees'] as List<dynamic>? ?? []).length;
    final String meeturl = widget.event['meeturl'] ?? '';
    final isTeamsMeeting = _graphData != null ? (_graphData!['isOnlineMeeting'] ?? false) : (widget.event['teamsMeeting'] ?? false);
    final isOnlineMeeting = meeturl.isNotEmpty || isTeamsMeeting;
    final description = _description;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 24,
      backgroundColor: Colors.transparent, // Transparent for Stack overlay
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 800,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 10))
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: _isLoading 
                  ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF8B5CF6))))
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Left Column
                          Expanded(
                            flex: 5,
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Header Area
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Purple Icon Box
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF5F3FF),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: const Color(0xFFEDE9FE)),
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            const Icon(Icons.calendar_today_outlined, color: Color(0xFF8B5CF6), size: 28),
                                            Positioned(
                                              bottom: 14,
                                              right: 14,
                                              child: Container(
                                                width: 8, height: 8,
                                                decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
                                              )
                                            )
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 4),
                                            Text(
                                              title,
                                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.5),
                                            ),
                                            const SizedBox(height: 12),
                                            // Accepted Badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDCFCE7).withOpacity(0.5),
                                                border: Border.all(color: const Color(0xFF86EFAC)),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(Icons.check, color: Color(0xFF16A34A), size: 14),
                                                  SizedBox(width: 4),
                                                  Text('Accepted', style: TextStyle(color: Color(0xFF16A34A), fontSize: 13, fontWeight: FontWeight.w600)),
                                                  SizedBox(width: 4),
                                                  Icon(Icons.keyboard_arrow_down, color: Color(0xFF16A34A), size: 16),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 32),
                                  
                                  // Detail Rows
                                  _buildDetailRow(
                                    icon: Icons.access_time,
                                    title: 'Time',
                                    content: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          startTimeStr != null ? DateFormat('EEE, dd MMM yyyy').format(DateTime.parse(startTimeStr)) : 'Unknown',
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_formatTimeOnly(startTimeStr)} – $formattedEndOnly $durationStr',
                                          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  _buildDetailRow(
                                    icon: Icons.person_outline,
                                    title: 'Organizer',
                                    content: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: const Color(0xFFC4B5FD),
                                          child: Text(
                                            organizer.isNotEmpty ? organizer[0].toUpperCase() : 'U',
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(organizer.split('@').first, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B))),
                                              const SizedBox(height: 2),
                                              Text(organizer, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  _buildDetailRow(
                                    icon: Icons.people_outline,
                                    title: 'Attendees',
                                    content: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.people, size: 16, color: Color(0xFF64748B)),
                                              const SizedBox(width: 8),
                                              Text('$attendeesCount attendee${attendeesCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                                              const SizedBox(width: 6),
                                              const Icon(Icons.chevron_right, size: 16, color: Color(0xFF64748B)),
                                            ],
                                          ),
                                        ),
                                        if (attendeesCount > 0) const SizedBox(height: 12),
                                        if (attendeesCount > 0)
                                          ...((graphAttendees.isNotEmpty ? graphAttendees : (widget.event['attendees'] as List<dynamic>? ?? []))).map((a) {
                                            final name = a['emailAddress'] != null ? (a['emailAddress']['name'] ?? a['emailAddress']['address'] ?? 'Unknown') : 'Unknown';
                                            final role = a['type'] ?? 'Required';
                                            final status = a['status'] != null ? a['status']['response'] ?? 'None' : 'None';
                                            
                                            String initials = "U";
                                            if (name.toString().isNotEmpty) {
                                              List<String> parts = name.toString().split(' ');
                                              if (parts.length > 1 && parts[1].isNotEmpty) {
                                                initials = "${parts[0][0]}${parts[1][0]}".toUpperCase();
                                              } else {
                                                initials = parts[0][0].toUpperCase();
                                              }
                                            }
                                            
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    backgroundColor: const Color(0xFFF5F3FF), 
                                                    radius: 12,
                                                    child: Text(initials, style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 10)),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(name, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.w500)),
                                                        Text('${role.toString().capitalize()} • ${status.toString().capitalize()}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                      ],
                                    ),
                                  ),
                                  
                                  _buildDetailRow(
                                    icon: Icons.videocam_outlined,
                                    title: 'Meeting',
                                    content: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(isOnlineMeeting ? (meeturl.isNotEmpty ? 'Online Meeting' : 'Teams meeting') : 'No online meeting', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                                        if (isOnlineMeeting) const SizedBox(height: 12),
                                        if (isOnlineMeeting)
                                          InkWell(
                                            onTap: _joinTeamsMeeting,
                                            borderRadius: BorderRadius.circular(20),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F3FF),
                                                border: Border.all(color: const Color(0xFFEDE9FE)),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(Icons.group_work, color: Color(0xFF8B5CF6), size: 18), // Placeholder for teams icon
                                                  SizedBox(width: 8),
                                                  Text('Join meeting', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  
                                  _buildDetailRow(
                                    icon: Icons.notifications_none,
                                    title: 'Reminder',
                                    content: const Text('10 minutes before', style: TextStyle(fontSize: 14, color: Color(0xFF475569))),
                                  ),
                                  
                                  _buildDetailRow(
                                    icon: Icons.notes,
                                    title: 'Notes',
                                    content: Text(description.isEmpty ? 'No notes added' : description, style: const TextStyle(fontSize: 14, color: Color(0xFF475569))),
                                    showDivider: false,
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                          
                          // Vertical Divider
                          Container(
                            width: 1,
                            color: const Color(0xFFF1F5F9),
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                          ),
                          
                          // Right Column
                          Expanded(
                            flex: 3,
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                              child: SingleChildScrollView(
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Event actions',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 24),
                                  _buildActionTile(Icons.content_copy, 'Duplicate event', () {}),
                                  _buildActionTile(Icons.mail_outline, 'Email attendees', () {}),
                                  _buildActionTile(Icons.print_outlined, 'Print', () {
                                    String htmlContent = '''
                                      <div style="max-width: 800px; margin: 0 auto; font-family: sans-serif; color: #333;">
                                        <h1 style="color: #0f172a; border-bottom: 1px solid #e2e8f0; padding-bottom: 16px;">$title</h1>
                                        <div style="margin-bottom: 24px; color: #64748b;">
                                          <strong>Time:</strong> $formattedStartFull - $formattedEndOnly $durationStr<br>
                                          <strong>Organizer:</strong> $organizer
                                        </div>
                                        <div style="line-height: 1.6; color: #1e293b; white-space: pre-wrap;">
                                          $description
                                        </div>
                                      </div>
                                    ''';
                                    printHtmlWeb(title, htmlContent);
                                  }),
                                  _buildActionTile(Icons.file_download_outlined, 'Download (.ics)', _downloadIcs),
                                  const SizedBox(height: 16),
                                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                  const SizedBox(height: 16),
                                  _buildActionTile(Icons.delete_outline, 'Delete event', _deleteEvent, isDestructive: true),
                                ],
                              ),
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            
            // Floating Close Button
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 24,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({required IconData icon, required String title, required Widget content, bool showDivider = true}) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF8B5CF6), size: 20),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 10),
                  content,
                ],
              ),
            ),
          ],
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 40, top: 16, bottom: 16),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
      ],
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFEF4444) : const Color(0xFF334155);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 14.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
    String capitalize() {
      if (this.isEmpty) return "";
      return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
    }
}
