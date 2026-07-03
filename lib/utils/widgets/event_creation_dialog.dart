import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

Future<Map<String, String>> _getDialogHeaders() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? email = prefs.getString('email');
  bool isOAuth = prefs.getBool('is_microsoft_login') == true || prefs.getBool('is_google_login') == true;
  String? password = isOAuth ? prefs.getString('password') : prefs.getString('mail_password');
  
  final Map<String, String> headers = {"Content-Type": "application/json"};
  if (email != null) headers['X-Email'] = email;
  if (password != null) headers['X-Password'] = password;
  return headers;
}

class EventCreationDialog extends StatefulWidget {
  final Map<String, dynamic>? initialEvent;
  const EventCreationDialog({super.key, this.initialEvent});

  @override
  State<EventCreationDialog> createState() => _EventCreationDialogState();
}

class _EventCreationDialogState extends State<EventCreationDialog> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _requiredAttendeesController = TextEditingController();
  final TextEditingController _optionalAttendeesController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _agendaController = TextEditingController();
  final TextEditingController _categoriesController = TextEditingController();
  final TextEditingController _organizerController = TextEditingController();

  // Date and Time State
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  
  // Booleans (Switches/Checkboxes)
  bool _isAllDay = false;
  bool _isTeamsMeeting = true;
  bool _responseRequested = true;
  bool _allowForwarding = true;

  // Dropdown Values
  String _timeZone = 'UTC';
  String _showAs = 'Busy';
  String _reminder = '15 minutes before';
  String _recurrence = 'None';
  String _sensitivity = 'Normal';
  String _importance = 'Normal';
  String _onlineProvider = 'Microsoft Teams';
  String _availability = 'Working Elsewhere';

  // Dropdown Options
  final List<String> _showAsOptions = ['Free', 'Tentative', 'Busy', 'Out of Office', 'Working Elsewhere'];
  final List<String> _sensitivityOptions = ['Normal', 'Personal', 'Private', 'Confidential'];
  final List<String> _importanceOptions = ['Low', 'Normal', 'High'];
  final List<String> _recurrenceOptions = ['None', 'Daily', 'Weekly', 'Monthly', 'Yearly'];
  final List<String> _reminderOptions = ['None', '5 minutes before', '15 minutes before', '30 minutes before', '1 hour before', '1 day before'];
  
  // Org Users from Backend
  List<String> _orgUsers = [];
  bool _isLoadingUsers = false;

  @override
  void initState() {
    super.initState();
    _fetchOrgUsers();
    
    if (widget.initialEvent != null) {
      final e = widget.initialEvent!;
      _titleController.text = e['title'] ?? '';
      _locationController.text = e['location'] ?? '';
      _descriptionController.text = e['description'] ?? '';
      _agendaController.text = e['agenda'] ?? '';
      _categoriesController.text = e['categories'] ?? '';
      _organizerController.text = e['organizerEmail'] ?? '';
      
      if (e['startTime'] != null) {
        final dt = DateTime.tryParse(e['startTime']);
        if (dt != null) {
          _startDate = dt;
          _startTime = TimeOfDay.fromDateTime(dt);
        }
      }
      if (e['endTime'] != null) {
        final dt = DateTime.tryParse(e['endTime']);
        if (dt != null) {
          _endDate = dt;
          _endTime = TimeOfDay.fromDateTime(dt);
        }
      }
      
      _isAllDay = e['allDay'] ?? false;
      _isTeamsMeeting = e['teamsMeeting'] ?? false;
      _timeZone = e['timeZone'] ?? 'UTC';
      _showAs = e['showAs'] ?? 'Busy';
      _reminder = e['reminder'] ?? '15 minutes before';
      _recurrence = e['recurrence'] ?? 'None';
      _sensitivity = e['sensitivity'] ?? 'Normal';
      _importance = e['importance'] ?? 'Normal';
    }
  }

  Future<void> _fetchOrgUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final headers = await _getDialogHeaders();
      headers.remove("Content-Type"); // GET requests might not need it, but it's fine.
      final response = await http.get(Uri.parse('${AppConfig.instance.calendarUrl}/users'), headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _orgUsers = data.map((e) => e.toString()).toList();
          _isLoadingUsers = false;
        });
      } else {
        setState(() => _isLoadingUsers = false);
      }
    } catch (e) {
      debugPrint("Error fetching users: $e");
      setState(() => _isLoadingUsers = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _requiredAttendeesController.dispose();
    _optionalAttendeesController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _agendaController.dispose();
    _categoriesController.dispose();
    _organizerController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    if (_isAllDay) return;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _showAttendeesPopup(TextEditingController controller) async {
    List<String> selectedEmails = controller.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            return AlertDialog(
              title: const Text('Select Attendees'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: SizedBox(
                width: 400,
                child: _isLoadingUsers 
                    ? const Center(child: CircularProgressIndicator())
                    : _orgUsers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No users found in organization.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _orgUsers.length,
                            itemBuilder: (context, index) {
                    final email = _orgUsers[index];
                    final isSelected = selectedEmails.contains(email);
                    return CheckboxListTile(
                      title: Text(email, style: const TextStyle(fontSize: 14)),
                      value: isSelected,
                      dense: true,
                      onChanged: (val) {
                        setPopupState(() {
                          if (val == true) {
                            selectedEmails.add(email);
                          } else {
                            selectedEmails.remove(email);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
    
    setState(() {
      controller.text = selectedEmails.join(', ');
    });
  }

  Future<void> _saveEvent() async {
    if (_formKey.currentState!.validate()) {
      
      final String startTimeStr = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute).toIso8601String();
      final String endTimeStr = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute).toIso8601String();

      final List<String> requiredAttendees = _requiredAttendeesController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final List<String> optionalAttendees = _optionalAttendeesController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      final Map<String, dynamic> body = {
        "title": _titleController.text,
        "description": _descriptionController.text,
        "location": _locationController.text,
        "startTime": startTimeStr,
        "endTime": endTimeStr,
        "attendees": requiredAttendees,
        "optionalAttendees": optionalAttendees,
        "isAllDay": _isAllDay,
        "isTeamsMeeting": _isTeamsMeeting,
        "agenda": _agendaController.text,
        "categories": _categoriesController.text,
        "reminder": _reminder,
        "sensitivity": _sensitivity,
        "importance": _importance,
        "timeZone": _timeZone,
        "showAs": _showAs,
        "recurrence": _recurrence,
      };

      try {
        http.Response response;
        final headers = await _getDialogHeaders();
        
        final bool isEditing = widget.initialEvent != null && widget.initialEvent!['id'] != null;
        if (isEditing) {
          final id = widget.initialEvent!['id'];
          response = await http.put(
            Uri.parse('${AppConfig.instance.calendarUrl}/events/$id'),
            headers: headers,
            body: json.encode(body),
          );
        } else {
          response = await http.post(
            Uri.parse('${AppConfig.instance.calendarUrl}/events'),
            headers: headers,
            body: json.encode(body),
          );
        }

        if (response.statusCode == 200) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(isEditing ? 'Event Updated Successfully!' : 'Event Created Successfully and Synced!')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save event: ${response.statusCode}')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialEvent != null && widget.initialEvent!['id'] != null;
    final bool isWide = MediaQuery.of(context).size.width > 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 800,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.calendar_today, color: Colors.blue, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          isEditing ? 'Edit Event' : 'Create Event',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Color(0xFF4B5563), size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(height: 24),
                
                _buildTextField('Title', _titleController, isRequired: true),
                const SizedBox(height: 16),
                
                if (isWide) 
                  Row(
                    children: [
                      Expanded(child: _buildTextField('Required Attendees', _requiredAttendeesController, onTap: () => _showAttendeesPopup(_requiredAttendeesController))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField('Optional Attendees', _optionalAttendeesController, onTap: () => _showAttendeesPopup(_optionalAttendeesController))),
                    ],
                  )
                else ...[
                  _buildTextField('Required Attendees', _requiredAttendeesController, onTap: () => _showAttendeesPopup(_requiredAttendeesController)),
                  const SizedBox(height: 16),
                  _buildTextField('Optional Attendees', _optionalAttendeesController, onTap: () => _showAttendeesPopup(_optionalAttendeesController)),
                ],
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Switch(
                      value: _isAllDay,
                      onChanged: (val) => setState(() => _isAllDay = val),
                      activeColor: Colors.blue,
                    ),
                    const Text('All Day Event'),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Date & Time Row
                Row(
                  children: [
                    Expanded(
                      child: _buildDateTimePicker(
                        label: 'Start Date',
                        text: DateFormat('MMM d, yyyy').format(_startDate),
                        icon: Icons.calendar_today,
                        onTap: () => _selectDate(context, true),
                      ),
                    ),
                    if (!_isAllDay) const SizedBox(width: 16),
                    if (!_isAllDay)
                      Expanded(
                        child: _buildDateTimePicker(
                          label: 'Start Time',
                          text: _startTime.format(context),
                          icon: Icons.access_time,
                          onTap: () => _selectTime(context, true),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: _buildDateTimePicker(
                        label: 'End Date',
                        text: DateFormat('MMM d, yyyy').format(_endDate),
                        icon: Icons.calendar_today,
                        onTap: () => _selectDate(context, false),
                      ),
                    ),
                    if (!_isAllDay) const SizedBox(width: 16),
                    if (!_isAllDay)
                      Expanded(
                        child: _buildDateTimePicker(
                          label: 'End Time',
                          text: _endTime.format(context),
                          icon: Icons.access_time,
                          onTap: () => _selectTime(context, false),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('Time Zone', ['UTC', 'EST', 'PST', 'IST', 'GMT'], _timeZone, (v) => setState(() => _timeZone = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Show As', _showAsOptions, _showAs, (v) => setState(() => _showAs = v!))),
                    ],
                  )
                else ...[
                  _buildDropdown('Time Zone', ['UTC', 'EST', 'PST', 'IST', 'GMT'], _timeZone, (v) => setState(() => _timeZone = v!)),
                  const SizedBox(height: 16),
                  _buildDropdown('Show As', _showAsOptions, _showAs, (v) => setState(() => _showAs = v!)),
                ],
                const SizedBox(height: 16),
                
                _buildTextField('Location / Room', _locationController),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.video_camera_front, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Teams Meeting', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Switch(
                            value: _isTeamsMeeting,
                            onChanged: (val) => setState(() => _isTeamsMeeting = val),
                            activeColor: Colors.blue,
                          ),
                        ],
                      ),
                      if (_isTeamsMeeting) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(const ClipboardData(text: 'https://teams.microsoft.com/l/meetup-join/...'));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link copied!')),
                              );
                            }
                          },
                          child: const Text(
                            'Meeting Link: https://teams.microsoft.com/l/meetup-join/...',
                            style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildTextField('Description / Body', _descriptionController, maxLines: 4),
                const SizedBox(height: 16),
                _buildTextField('Agenda', _agendaController, maxLines: 3),
                const SizedBox(height: 16),

                ElevatedButton.icon(
                  onPressed: () {}, 
                  icon: const Icon(Icons.attach_file), 
                  label: const Text('Add Attachments'),
                ),
                const SizedBox(height: 16),

                _buildTextField('Categories', _categoriesController),
                const SizedBox(height: 16),

                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('Reminder', _reminderOptions, _reminder, (v) => setState(() => _reminder = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Recurrence', _recurrenceOptions, _recurrence, (v) => setState(() => _recurrence = v!))),
                    ],
                  )
                else ...[
                  _buildDropdown('Reminder', _reminderOptions, _reminder, (v) => setState(() => _reminder = v!)),
                  const SizedBox(height: 16),
                  _buildDropdown('Recurrence', _recurrenceOptions, _recurrence, (v) => setState(() => _recurrence = v!)),
                ],
                const SizedBox(height: 16),

                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('Sensitivity', _sensitivityOptions, _sensitivity, (v) => setState(() => _sensitivity = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Importance', _importanceOptions, _importance, (v) => setState(() => _importance = v!))),
                    ],
                  )
                else ...[
                  _buildDropdown('Sensitivity', _sensitivityOptions, _sensitivity, (v) => setState(() => _sensitivity = v!)),
                  const SizedBox(height: 16),
                  _buildDropdown('Importance', _importanceOptions, _importance, (v) => setState(() => _importance = v!)),
                ],
                const SizedBox(height: 16),

                _buildTextField('Organizer', _organizerController),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Response Requested'),
                        value: _responseRequested,
                        onChanged: (val) => setState(() => _responseRequested = val!),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Allow Forwarding'),
                        value: _allowForwarding,
                        onChanged: (val) => setState(() => _allowForwarding = val!),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                const SizedBox(height: 24),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                      child: const Text('Save Draft', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _saveEvent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          ),
                          child: Text(isEditing ? 'Save' : 'Create', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isRequired = false, int maxLines = 1, VoidCallback? onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: onTap != null,
          onTap: onTap,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          validator: isRequired ? (value) {
            if (value == null || value.isEmpty) {
              return 'This field is required';
            }
            return null;
          } : null,
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, List<String> options, String currentValue, void Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: currentValue,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt, style: const TextStyle(fontSize: 14)))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDateTimePicker({required String label, required String text, required IconData icon, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(text, style: const TextStyle(fontSize: 14)),
                Icon(icon, size: 18, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
