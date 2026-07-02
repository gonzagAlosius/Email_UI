import 'package:flutter/material.dart';
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
    List<dynamic> graphAttendees = _graphData != null && _graphData!['attendees'] != null 
        ? _graphData!['attendees'] 
        : [];
        
    final attendeesCount = graphAttendees.isNotEmpty ? graphAttendees.length : (widget.event['attendees'] as List<dynamic>? ?? []).length;
    final isTeamsMeeting = _graphData != null ? (_graphData!['isOnlineMeeting'] ?? false) : (widget.event['teamsMeeting'] ?? false);
    String description = _graphData != null && _graphData!['bodyPreview'] != null 
        ? _graphData!['bodyPreview'] 
        : widget.event['description'] ?? '';
        
    if (description.startsWith('Agenda:')) {
      description = description.substring(7).trim();
    }
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 1000,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              _buildHeader(title),
              const SizedBox(height: 24),
            _isLoading 
              ? const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildLeftItem(
                              icon: Icons.access_time, 
                              title: 'Time', 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$formattedStartFull – $formattedEndOnly', style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                                  const SizedBox(height: 4),
                                  Text(durationStr, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.people_outline, 
                              title: 'Organizer', 
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF93C5FD),
                                    child: Text(
                                      organizer.isNotEmpty ? organizer[0].toUpperCase() : 'U',
                                      style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(organizer.split('@').first, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151))),
                                      Text(organizer, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.group_outlined, 
                              title: 'Attendees', 
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('$attendeesCount attendee${attendeesCount == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right, size: 16, color: Color(0xFF9CA3AF)),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.videocam_outlined, 
                              title: 'Meeting', 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(isTeamsMeeting ? 'Teams meeting' : 'No online meeting', style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                                  if (isTeamsMeeting) const SizedBox(height: 8),
                                  if (isTeamsMeeting)
                                    InkWell(
                                      onTap: () {}, 
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: const Color(0xFFBFDBFE)),
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Text('Join meeting', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                                            SizedBox(width: 6),
                                            Icon(Icons.group_work, color: Colors.blue, size: 16),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.notes, 
                              title: 'Agenda', 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Agenda:', style: TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFE5E7EB)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(description.isEmpty ? 'Agenda:' : description, style: const TextStyle(fontSize: 14, color: Color(0xFF374151))),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.notifications_none, 
                              title: 'Reminder', 
                              child: const Text('10 minutes before', style: TextStyle(fontSize: 14, color: Color(0xFF4B5563))),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                            
                            _buildLeftItem(
                              icon: Icons.event_available, 
                              title: 'Status', 
                              child: Row(
                                children: [
                                  const Icon(Icons.check, color: Colors.green, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('Accepted', style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
                                  const SizedBox(width: 16),
                                  InkWell(
                                    onTap: () {},
                                    child: const Text('Change', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 32),
                      
                      // Right Column
                      Expanded(
                        flex: 4,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTrackingCard(organizer, graphAttendees),
                            const SizedBox(height: 16),
                            _buildEventActionsCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big Icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF), // Light blue background
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(Icons.event_available_outlined, color: Colors.blue, size: 32),
          ),
        ),
        const SizedBox(width: 24),
        
        // Title & Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check, color: Colors.blue, size: 14),
                    SizedBox(width: 4),
                    Text('Accepted', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down, color: Colors.blue, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Actions
        Row(
          children: [
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.open_in_new, size: 18, color: Color(0xFF6B7280)),
              label: const Text('Open in new', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF6B7280)),
              label: const Text('Edit', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              label: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Color(0xFF4B5563), size: 24),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeftItem({required IconData icon, required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(String organizer, List<dynamic> attendeesList) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.insert_chart_outlined, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
                  ],
                ),
                const Icon(Icons.keyboard_arrow_up, color: Color(0xFF6B7280), size: 18),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Organizer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF93C5FD),
                      radius: 16,
                      child: Text(
                        organizer.isNotEmpty ? organizer[0].toUpperCase() : 'U',
                        style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(organizer.split('@').first, style: const TextStyle(color: Color(0xFF374151), fontSize: 13, fontWeight: FontWeight.w500)),
                          const Text('Sent on Mon, 29 Jun 2026 at 01:21 PM', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 16),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Attendees', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151))),
                const SizedBox(height: 4),
                const Text('Responses tracking', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.group_outlined, color: Color(0xFF6B7280), size: 16),
                          const SizedBox(width: 8),
                          Text('Total: ${attendeesList.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F2937))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      ...attendeesList.map((a) {
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
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFFE9D5FF), 
                                radius: 14,
                                child: Text(initials, style: const TextStyle(color: Color(0xFF6B21A8), fontWeight: FontWeight.bold, fontSize: 10)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 13, fontWeight: FontWeight.w500)),
                                    Text('${role.toString().capitalize()} • ${status.toString().capitalize()}', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      if (attendeesList.isEmpty)
                         const Text('No attendees listed.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEventActionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.bolt_outlined, color: Color(0xFF6B7280), size: 18),
                    SizedBox(width: 8),
                    Text('Event actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1F2937))),
                  ],
                ),
                const Icon(Icons.keyboard_arrow_up, color: Color(0xFF6B7280), size: 18),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              children: [
                _buildActionTile(Icons.content_copy, 'Duplicate event', () {}),
                _buildActionTile(Icons.email_outlined, 'Email attendees', () {}),
                _buildActionTile(Icons.print_outlined, 'Print', () {}),
                _buildActionTile(Icons.file_download_outlined, 'Download (.ics)', _downloadIcs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF4B5563), size: 18),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF374151))),
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
