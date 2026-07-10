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
  final Map<String, dynamic>? selectedCalendar;
  const EventCreationDialog({super.key, this.initialEvent, this.selectedCalendar});

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

  // Calendars
  List<dynamic> _calendars = [];
  int? _selectedCalId;
  bool _isLoadingCalendars = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchOrgUsers();
    
    if (widget.selectedCalendar != null) {
      _selectedCalId = widget.selectedCalendar!['calid'];
    }
    _fetchCalendars();
    
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

  Future<void> _fetchCalendars() async {
    setState(() => _isLoadingCalendars = true);
    try {
      final headers = await _getDialogHeaders();
      headers.remove("Content-Type");
      final response = await http.get(Uri.parse('${AppConfig.instance.calendarUrl}/calendars'), headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _calendars = data;
          if (_selectedCalId == null && _calendars.isNotEmpty) {
            _selectedCalId = _calendars.first['calid'];
          }
          _isLoadingCalendars = false;
        });
      } else {
        setState(() => _isLoadingCalendars = false);
      }
    } catch (e) {
      debugPrint("Error fetching calendars: $e");
      setState(() => _isLoadingCalendars = false);
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

  Future<void> _saveEvent() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      
      final String startTimeStr = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute).toIso8601String();
      final String endTimeStr = DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute).toIso8601String();

      final emailRegex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$");
      final List<String> requiredAttendees = _requiredAttendeesController.text.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => emailRegex.hasMatch(e)).toList();
      final List<String> optionalAttendees = _optionalAttendeesController.text.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => emailRegex.hasMatch(e)).toList();

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

      if (_selectedCalId != null) {
        body['calid'] = _selectedCalId;
        final selectedCal = _calendars.firstWhere((c) => c['calid'] == _selectedCalId, orElse: () => null);
        if (selectedCal != null && selectedCal['orgcode'] != null) {
          body['orgcode'] = selectedCal['orgcode'];
        }
      }

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
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialEvent != null && widget.initialEvent!['id'] != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 24,
      backgroundColor: Colors.transparent, // For Stack overlay
      surfaceTintColor: Colors.transparent,
      child: Container(
        width: 1000,
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
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Column: Main Details
                      Expanded(
                        flex: 5,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F3FF),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFEDE9FE)),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.edit_calendar, color: Color(0xFF8B5CF6), size: 28),
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 12),
                                        Text(
                                          isEditing ? 'Edit Event' : 'Create Event',
                                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),

                              if (_calendars.isNotEmpty) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Calendar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<int>(
                                      value: _selectedCalId,
                                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                                      icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B), size: 20),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5)),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                      items: _calendars.map((cal) => DropdownMenuItem<int>(
                                        value: cal['calid'] as int,
                                        child: Text(cal['calname'] ?? 'Calendar'),
                                      )).toList(),
                                      onChanged: (val) {
                                        setState(() => _selectedCalId = val);
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],

                              _buildTextField('Event Title', _titleController, isRequired: true),
                              const SizedBox(height: 20),

                              Row(
                                children: [
                                  Switch(
                                    value: _isAllDay,
                                    onChanged: (val) => setState(() => _isAllDay = val),
                                    activeColor: const Color(0xFF8B5CF6),
                                    activeTrackColor: const Color(0xFFC4B5FD),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('All Day Event', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF334155))),
                                ],
                              ),
                              const SizedBox(height: 20),

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
                              const SizedBox(height: 20),

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
                              const SizedBox(height: 20),

                              _buildTextField('Location / Room', _locationController),
                              const SizedBox(height: 20),

                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3FF).withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFEDE9FE)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: const [
                                            Icon(Icons.video_camera_front, color: Color(0xFF8B5CF6)),
                                            SizedBox(width: 8),
                                            Text('Teams Meeting', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4C1D95))),
                                          ],
                                        ),
                                        Switch(
                                          value: _isTeamsMeeting,
                                          onChanged: (val) => setState(() => _isTeamsMeeting = val),
                                          activeColor: const Color(0xFF8B5CF6),
                                          activeTrackColor: const Color(0xFFC4B5FD),
                                        ),
                                      ],
                                    ),
                                    if (_isTeamsMeeting) ...[
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        onTap: () async {
                                          await Clipboard.setData(const ClipboardData(text: 'https://teams.microsoft.com/l/meetup-join/...'));
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!')));
                                          }
                                        },
                                        child: const Text(
                                          'Meeting Link: https://teams.microsoft.com/l/meetup-join/...',
                                          style: TextStyle(color: Color(0xFF8B5CF6), decoration: TextDecoration.underline, fontSize: 13),
                                        ),
                                      ),
                                    ]
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              _buildTextField('Description / Body', _descriptionController, maxLines: 4),
                              const SizedBox(height: 20),
                              _buildTextField('Agenda', _agendaController, maxLines: 3),
                              const SizedBox(height: 20),

                              InkWell(
                                onTap: () {},
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(8),
                                    color: const Color(0xFFF8FAFC),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.attach_file, color: Color(0xFF64748B), size: 18),
                                      SizedBox(width: 8),
                                      Text('Add Attachments', style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600, fontSize: 14)),
                                    ],
                                  ),
                                ),
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
                      
                      // Right Column: Settings & Attendees
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                                child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Attendees & Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                    const SizedBox(height: 24),
                                    
                                    InlineAttendeeSearchField(
                                      label: 'Required Attendees', 
                                      controller: _requiredAttendeesController, 
                                      orgUsers: _orgUsers
                                    ),
                                    const SizedBox(height: 16),
                                    InlineAttendeeSearchField(
                                      label: 'Optional Attendees', 
                                      controller: _optionalAttendeesController, 
                                      orgUsers: _orgUsers
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    Row(
                                      children: [
                                        Expanded(child: _buildDropdown('Time Zone', ['UTC', 'EST', 'PST', 'IST', 'GMT'], _timeZone, (v) => setState(() => _timeZone = v!))),
                                        const SizedBox(width: 16),
                                        Expanded(child: _buildDropdown('Show As', _showAsOptions, _showAs, (v) => setState(() => _showAs = v!))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    _buildTextField('Categories', _categoriesController),
                                    const SizedBox(height: 16),
                                    
                                    Row(
                                      children: [
                                        Expanded(child: _buildDropdown('Reminder', _reminderOptions, _reminder, (v) => setState(() => _reminder = v!))),
                                        const SizedBox(width: 16),
                                        Expanded(child: _buildDropdown('Recurrence', _recurrenceOptions, _recurrence, (v) => setState(() => _recurrence = v!))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    Row(
                                      children: [
                                        Expanded(child: _buildDropdown('Sensitivity', _sensitivityOptions, _sensitivity, (v) => setState(() => _sensitivity = v!))),
                                        const SizedBox(width: 16),
                                        Expanded(child: _buildDropdown('Importance', _importanceOptions, _importance, (v) => setState(() => _importance = v!))),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    _buildTextField('Organizer', _organizerController),
                                    const SizedBox(height: 24),
                                    
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: _responseRequested,
                                                  onChanged: (val) => setState(() => _responseRequested = val!),
                                                  activeColor: const Color(0xFF8B5CF6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Expanded(child: Text('Response Requested', style: TextStyle(fontSize: 13, color: Color(0xFF334155)))),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: Checkbox(
                                                  value: _allowForwarding,
                                                  onChanged: (val) => setState(() => _allowForwarding = val!),
                                                  activeColor: const Color(0xFF8B5CF6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Expanded(child: Text('Allow Forwarding', style: TextStyle(fontSize: 13, color: Color(0xFF334155)))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 32),
                                  ],
                                ),
                              ),
                            ),
                            ),
                            
                            // Bottom Action Buttons
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                                    ),
                                    Row(
                                      children: [
                                        ElevatedButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFF1F5F9),
                                            foregroundColor: const Color(0xFF334155),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                          ),
                                          child: const Text('Save Draft', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 12),
                                        ElevatedButton(
                                          onPressed: _isSaving ? null : _saveEvent,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF8B5CF6),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                          ),
                                          child: Text(isEditing ? 'Save Changes' : 'Create Event', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
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
            ),
            
            // Floating Close Button
            Positioned(
              top: 24,
              right: 24,
              child: IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                splashRadius: 24,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),

            // Loading Overlay
            if (_isSaving)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isRequired = false, int maxLines = 1, VoidCallback? onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          readOnly: onTap != null,
          onTap: onTap,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5)),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: isRequired ? (value) {
            if (value == null || value.isEmpty) return 'This field is required';
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: currentValue,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B), size: 20),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5)),
            filled: true,
            fillColor: Colors.white,
          ),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDateTimePicker({required String label, required String text, required IconData icon, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A))),
                Icon(icon, size: 18, color: const Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class InlineAttendeeSearchField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final List<String> orgUsers;

  const InlineAttendeeSearchField({Key? key, required this.label, required this.controller, required this.orgUsers}) : super(key: key);

  @override
  _InlineAttendeeSearchFieldState createState() => _InlineAttendeeSearchFieldState();
}

class _InlineAttendeeSearchFieldState extends State<InlineAttendeeSearchField> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _selectedEmails = [];
  bool _showDropdown = false;

  @override
  void initState() {
    super.initState();
    _updateSelectedFromController();
    _searchController.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        setState(() => _showDropdown = true);
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showDropdown = false);
        });
      }
    });
  }
  
  @override
  void didUpdateWidget(InlineAttendeeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.text != widget.controller.text && !_focusNode.hasFocus) {
       _updateSelectedFromController();
    }
  }

  void _updateSelectedFromController() {
    _selectedEmails = widget.controller.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  void _updateControllerFromSelected() {
    widget.controller.text = _selectedEmails.join(', ');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final showDropdown = _showDropdown;
    
    List<String> filteredUsers = widget.orgUsers
        .where((u) => u.toLowerCase().contains(query) && !_selectedEmails.contains(u))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _focusNode.hasFocus ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0), width: _focusNode.hasFocus ? 1.5 : 1.0),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedEmails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedEmails.map((email) => Chip(
                      label: Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF4C1D95))),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedEmails.remove(email);
                          _updateControllerFromSelected();
                        });
                      },
                      backgroundColor: const Color(0xFFEDE9FE),
                      deleteIconColor: const Color(0xFF8B5CF6),
                      side: BorderSide.none,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )).toList(),
                  ),
                ),
              TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: _selectedEmails.isEmpty ? 'Search attendees...' : 'Add more...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty && !_selectedEmails.contains(val.trim())) {
                    setState(() {
                      _selectedEmails.add(val.trim());
                      _searchController.clear();
                      _updateControllerFromSelected();
                      _focusNode.requestFocus();
                    });
                  }
                },
              ),
            ],
          ),
        ),
        if (showDropdown && (filteredUsers.isNotEmpty || widget.orgUsers.isEmpty || query.isNotEmpty))
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: (widget.orgUsers.isEmpty && query.isEmpty)
                ? const Padding(padding: EdgeInsets.all(12), child: Text('No users found. Type to add manually.', style: TextStyle(color: Color(0xFF64748B))))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...filteredUsers.map((user) {
                          return MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Listener(
                              onPointerDown: (_) {
                                setState(() {
                                  _selectedEmails.add(user);
                                  _searchController.clear();
                                  _updateControllerFromSelected();
                                  _focusNode.requestFocus();
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                color: Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(user, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                              ),
                            ),
                          );
                        }).toList(),
                        if (query.isNotEmpty && !filteredUsers.contains(query) && !_selectedEmails.contains(query))
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Listener(
                              onPointerDown: (_) {
                                setState(() {
                                  _selectedEmails.add(query.trim());
                                  _searchController.clear();
                                  _updateControllerFromSelected();
                                  _focusNode.requestFocus();
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                color: const Color(0xFFF5F3FF),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF8B5CF6)),
                                    const SizedBox(width: 8),
                                    Text('Add "$query"', style: const TextStyle(fontSize: 13, color: Color(0xFF4C1D95), fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

