import 'package:flutter/material.dart';
import 'dart:async';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'utils/widgets/event_creation_dialog.dart';
import 'utils/widgets/elaborated_event_dialog.dart';
import 'utils/widgets/calendar_creation_dialog.dart';

Future<Map<String, String>> _getCalendarHeaders() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? email = prefs.getString('email');
  bool isOAuth = prefs.getBool('is_microsoft_login') == true || prefs.getBool('is_google_login') == true;
  String? password = isOAuth ? prefs.getString('password') : prefs.getString('mail_password');
  
  final Map<String, String> headers = {};
  if (email != null) headers['X-Email'] = email;
  if (password != null) headers['X-Password'] = password;
  return headers;
}

class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  bool _isLoading = true;
  bool _isLoadingCalendars = true;
  final Map<DateTime, List<dynamic>> _events = {};
  List<dynamic> _upcomingEvents = [];
  List<dynamic> _calendars = [];
  Map<String, dynamic>? _selectedCalendar;
  String _currentView = 'Month';
  Timer? _refreshTimer;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
    _fetchEvents();
    _fetchCalendars();
  }

  Future<void> _loadUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userEmail = prefs.getString('email');
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEvents({bool isBackgroundRefresh = false}) async {
    try {
      if (!isBackgroundRefresh) {
        setState(() => _isLoading = true);
      }
      final headers = await _getCalendarHeaders();
      String url = '${AppConfig.instance.calendarUrl}/events';
      if (_selectedCalendar != null) {
        final calid = _selectedCalendar!['calid'];
        final orgcode = _selectedCalendar!['orgcode'];
        url += '?calid=$calid&orgcode=$orgcode';
      }
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final Map<DateTime, List<dynamic>> newEvents = {};
        
        for (var event in data) {
          if (event['startTime'] != null) {
            final DateTime startTime = DateTime.parse(event['startTime']);
            final dateKey = DateTime(startTime.year, startTime.month, startTime.day);
            if (newEvents[dateKey] == null) {
              newEvents[dateKey] = [];
            }
            newEvents[dateKey]!.add(event);
          }
        }
        
        setState(() {
          _events.clear();
          _events.addAll(newEvents);
          _upcomingEvents = data;
          _upcomingEvents.sort((a, b) {
            final aTime = DateTime.tryParse(a['startTime'] ?? '') ?? DateTime.now();
            final bTime = DateTime.tryParse(b['startTime'] ?? '') ?? DateTime.now();
            return aTime.compareTo(bTime);
          });
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching calendar events: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCalendars({bool isBackgroundRefresh = false}) async {
    try {
      if (!isBackgroundRefresh) {
        setState(() => _isLoadingCalendars = true);
      }
      final headers = await _getCalendarHeaders();
      final response = await http.get(Uri.parse('${AppConfig.instance.calendarUrl}/calendars'), headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _calendars = data;
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

  List<dynamic> _getEventsForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _events.entries
        .where((entry) => isSameDay(entry.key, date))
        .map((entry) => entry.value)
        .expand((element) => element)
        .toList();
  }

  void _openEventCreationDialog(DateTime date, {int? hour}) {
    DateTime startTime = date;
    if (hour != null) {
      startTime = DateTime(date.year, date.month, date.day, hour);
    } else {
      final now = DateTime.now();
      startTime = DateTime(date.year, date.month, date.day, now.hour);
    }
    DateTime endTime = startTime.add(const Duration(hours: 1));

    showDialog(
      context: context,
      builder: (context) => EventCreationDialog(
        initialEvent: {
          'startTime': startTime.toIso8601String(),
          'endTime': endTime.toIso8601String(),
        },
        selectedCalendar: _selectedCalendar,
      ),
    ).then((_) => _fetchEvents());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isCompact = screenWidth < 750;

    if (isCompact) {
      return Container(
        color: Colors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Calendar",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.all(8),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white, size: 24),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => EventCreationDialog(selectedCalendar: _selectedCalendar),
                    ).then((_) => _fetchEvents()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                color: Colors.white,
                child: TableCalendar(
                  rowHeight: 34,
                  daysOfWeekHeight: 24,
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    final eventsOnDay = _getEventsForDay(selectedDay);
                    if (eventsOnDay.isNotEmpty) {
                      if (eventsOnDay.length == 1) {
                        _showEventDetailsDialog(eventsOnDay.first as Map<String, dynamic>);
                      } else {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text('Events on ${DateFormat('MMM d, yyyy').format(selectedDay)}'),
                              content: SizedBox(
                                width: 400,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: eventsOnDay.length,
                                  itemBuilder: (context, index) {
                                    final e = eventsOnDay[index] as Map<String, dynamic>;
                                    final startTime = DateTime.tryParse(e['startTime'] ?? '');
                                    final timeStr = startTime != null ? DateFormat('h:mm a').format(startTime) : '';
                                    return ListTile(
                                      title: Text(e['title'] ?? 'Event'),
                                      subtitle: Text(timeStr),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _showEventDetailsDialog(e);
                                      },
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      }
                    }
                  },
                  onFormatChanged: (format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  },
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                    selectedDecoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, date, events) {
                      if (events.isNotEmpty) {
                        return Positioned(
                          bottom: 4,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                  eventLoader: _getEventsForDay,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSidebarEventLists(),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Row(
        children: [
          // Left Sidebar for Calendar and Mini Info
          Container(
            width: 350,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 16.0, bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Calendar",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(8),
                        ),
                        icon: const Icon(Icons.add, color: Colors.white, size: 24),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => EventCreationDialog(selectedCalendar: _selectedCalendar),
                        ).then((_) => _fetchEvents()),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Card(
                    elevation: 12,
                    shadowColor: Colors.black.withOpacity(0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white,
                    child: TableCalendar(
                      rowHeight: 28,
                      daysOfWeekHeight: 20,
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: _calendarFormat,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                        final eventsOnDay = _getEventsForDay(selectedDay);
                        if (eventsOnDay.isNotEmpty) {
                          _showAllEventsDialog(selectedDay, eventsOnDay.cast<Map<String, dynamic>>());
                        }
                      },
                      onFormatChanged: (format) {
                        setState(() {
                          _calendarFormat = format;
                        });
                      },
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        headerPadding: EdgeInsets.symmetric(vertical: 4.0),
                      ),
                      calendarStyle: CalendarStyle(
                        cellMargin: const EdgeInsets.all(4),
                        todayDecoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                        selectedDecoration: const BoxDecoration(
                          color: Color(0xFF8B5CF6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          if (events.isNotEmpty) {
                            return Positioned(
                              bottom: 4,
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                      eventLoader: _getEventsForDay,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildSidebarEventLists(),
              ],
            ),
          ),
          // Main Calendar Area
          Expanded(
            child: Column(
              children: [
                _buildCalendarHeader(),
                Expanded(
                  child: _buildMainViewContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSidebarEventLists() {
    if (_isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    
    final now = DateTime.now();
    final upcoming = _upcomingEvents.where((e) {
      final t = DateTime.tryParse(e['startTime'] ?? '') ?? now;
      return t.isAfter(now) || isSameDay(t, now);
    }).toList();
    
    final finished = _upcomingEvents.where((e) {
      final t = DateTime.tryParse(e['startTime'] ?? '') ?? now;
      return t.isBefore(now) && !isSameDay(t, now);
    }).toList();

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_userEmail != null && _userEmail!.endsWith('@botsuat.com')) ...[
            // My Calendars Section
            Padding(
              padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("My Calendars", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => CalendarCreationDialog(
                          onCalendarCreated: _fetchCalendars,
                        ),
                      );
                    },
                    child: const Icon(Icons.add_circle_outline, color: Color(0xFF8B5CF6), size: 20),
                  ),
                ],
              ),
            ),
            if (_isLoadingCalendars)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_calendars.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("No custom calendars", style: TextStyle(color: Colors.grey, fontSize: 13)),
              )
            else
              ..._calendars.map((cal) {
                final isSelected = _selectedCalendar != null && _selectedCalendar!['calid'] == cal['calid'];
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedCalendar = null;
                      } else {
                        _selectedCalendar = cal as Map<String, dynamic>;
                      }
                    });
                    _fetchEvents();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF8B5CF6).withOpacity(0.1) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month, size: 16, color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cal['calname'] ?? 'Calendar',
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                              color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              
            const SizedBox(height: 24),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Upcoming Events", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                Text("View all", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF8B5CF6))),
              ],
            ),
          ),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("No upcoming events", style: TextStyle(color: Colors.grey)),
            ),
          ...upcoming.map((event) {
            final startTime = DateTime.tryParse(event['startTime'] ?? '');
            final timeStr = startTime != null ? DateFormat('MMM d, h:mm a').format(startTime) : 'Unknown time';
            final color = event['color'] != null ? Color(int.parse(event['color'].replaceFirst('#', '0xFF'))) : const Color(0xFF8B5CF6);
            return _buildUpcomingEvent(event, timeStr, color);
          }).toList(),
          
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text("Finished Events", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (finished.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("No finished events", style: TextStyle(color: Colors.grey)),
            ),
          ...finished.map((event) {
            final startTime = DateTime.tryParse(event['startTime'] ?? '');
            final timeStr = startTime != null ? DateFormat('MMM d, h:mm a').format(startTime) : 'Unknown time';
            return _buildUpcomingEvent(event, timeStr, Colors.grey);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildUpcomingEvent(Map<String, dynamic> event, String time, Color color) {
    final title = event['title'] ?? 'Event';
    return GestureDetector(
      onTap: () => _showEventDetailsDialog(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                  Text(time, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.calendar_today_outlined, color: Color(0xFF64748B), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool useColumn = constraints.maxWidth < 450;
        
        Widget todayButton = TextButton(
          onPressed: () {
            setState(() {
              _focusedDay = DateTime.now();
              _selectedDay = DateTime.now();
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF8B5CF6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          child: const Text("Today"),
        );

        Widget buildNavButton(IconData icon, VoidCallback onPressed) {
          return TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B5CF6),
              padding: const EdgeInsets.all(12),
              minimumSize: const Size(0, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF8B5CF6)),
          );
        }

        Widget navigationGroup = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildNavButton(Icons.chevron_left, () {
              setState(() {
                if (_currentView == 'Day') {
                  _focusedDay = _focusedDay.subtract(const Duration(days: 1));
                  _selectedDay = _focusedDay;
                } else if (_currentView == 'Week') {
                  _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                  _selectedDay = null;
                } else if (_currentView == 'Month') {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, _focusedDay.day);
                  _selectedDay = null;
                } else if (_currentView == 'Year') {
                  _focusedDay = DateTime(_focusedDay.year - 1, _focusedDay.month, _focusedDay.day);
                  _selectedDay = null;
                }
              });
            }),
            const SizedBox(width: 8),
            buildNavButton(Icons.chevron_right, () {
              setState(() {
                if (_currentView == 'Day') {
                  _focusedDay = _focusedDay.add(const Duration(days: 1));
                  _selectedDay = _focusedDay;
                } else if (_currentView == 'Week') {
                  _focusedDay = _focusedDay.add(const Duration(days: 7));
                  _selectedDay = null;
                } else if (_currentView == 'Month') {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, _focusedDay.day);
                  _selectedDay = null;
                } else if (_currentView == 'Year') {
                  _focusedDay = DateTime(_focusedDay.year + 1, _focusedDay.month, _focusedDay.day);
                  _selectedDay = null;
                }
              });
            }),
            const SizedBox(width: 12),
            todayButton,
          ],
        );

        Widget monthPickerButton = InkWell(
          onTap: () async {
            final DateTime? picked = await showDialog<DateTime>(
              context: context,
              builder: (context) {
                int pickerYear = _focusedDay.year;
                return StatefulBuilder(
                  builder: (context, setStateDialog) {
                    return AlertDialog(
                      surfaceTintColor: Colors.transparent,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      titlePadding: const EdgeInsets.only(top: 16, left: 16, right: 16),
                      contentPadding: const EdgeInsets.all(16),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, color: Color(0xFF64748B)),
                            onPressed: () => setStateDialog(() => pickerYear--),
                          ),
                          Text('$pickerYear', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                            onPressed: () => setStateDialog(() => pickerYear++),
                          ),
                        ],
                      ),
                      content: SizedBox(
                        width: 320,
                        height: 180,
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 1.5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, index) {
                            final monthDate = DateTime(pickerYear, index + 1, 1);
                            final bool isCurrentSelection = index + 1 == _focusedDay.month && pickerYear == _focusedDay.year;
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context, DateTime(pickerYear, index + 1, _focusedDay.day));
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isCurrentSelection ? const Color(0xFF8B5CF6) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  DateFormat('MMM').format(monthDate),
                                  style: TextStyle(
                                    color: isCurrentSelection ? Colors.white : const Color(0xFF4B5563),
                                    fontWeight: isCurrentSelection ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }
                );
              },
            );
            if (picked != null) {
              setState(() {
                _focusedDay = picked;
              });
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(_focusedDay),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 24, color: Color(0xFF64748B)),
                  ],
                ),
                Text(
                  DateFormat('EEEE, MMM d, yyyy').format(_selectedDay ?? _focusedDay),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        );

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: useColumn ? 16 : 24,
            vertical: 16,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: useColumn
              ? Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        navigationGroup,
                        monthPickerButton,
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Center(child: _buildViewToggle("Day"))),
                          Expanded(child: Center(child: _buildViewToggle("Week"))),
                          Expanded(child: Center(child: _buildViewToggle("Month"))),
                          Expanded(child: Center(child: _buildViewToggle("Year"))),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: navigationGroup,
                      ),
                    ),
                    monthPickerButton,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildViewToggle("Day"),
                              _buildViewToggle("Week"),
                              _buildViewToggle("Month"),
                              _buildViewToggle("Year"),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildViewToggle(String label) {
    bool isSelected = _currentView == label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _currentView = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildMainViewContent() {
    switch (_currentView) {
      case 'Day':
        return _buildScheduleView();
      case 'Week':
        return _buildWeekView();
      case 'Month':
        return _buildMonthView();
      case 'Year':
        return _buildYearView();
      default:
        return _buildScheduleView();
    }
  }

  Widget _buildScheduleView() {
    final displayDate = _selectedDay ?? _focusedDay;
    final dayEvents = _getEventsForDay(displayDate);

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: 24,
      itemBuilder: (context, index) {
        final hour = index % 12 == 0 ? 12 : index % 12;
        final ampm = index < 12 ? 'AM' : 'PM';
        
        // Find events that start in this hour
        final eventsInHour = dayEvents.where((e) {
          final st = DateTime.tryParse(e['startTime'] ?? '');
          if (st != null) {
            return st.hour == index;
          }
          return false;
        }).toList();

        final now = DateTime.now();
        final isToday = isSameDay(displayDate, now);
        final showCurrentTimeLine = isToday && now.hour == index;

        return Container(
          height: 48,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    "$hour $ampm",
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openEventCreationDialog(displayDate, hour: index),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                    if (eventsInHour.isNotEmpty)
                      Positioned(
                        top: 0, bottom: 0, left: 0, right: 0,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: eventsInHour.map((e) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 2.0),
                                child: _buildEventBlock(e, Colors.blue),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (showCurrentTimeLine)
                      Positioned(
                        top: (now.minute / 60) * 48,
                        left: 0,
                        right: 0,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              transform: Matrix4.translationValues(-4, 0, 0),
                              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            ),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEventBlock(Map<String, dynamic> event, Color color) {
    final title = event['title'] ?? 'Event';
    return GestureDetector(
      onTap: () => _showEventDetailsDialog(event),
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Text(
          title, 
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showEventDetailsDialog(Map<String, dynamic> event) {
    // Use the elaborated dialog widget for detailed event view to match the design
    showDialog(
      context: context,
      builder: (context) => ElaboratedEventDialog(
        event: event,
        onEventDeleted: () => _fetchEvents(),
      ),
    );
  }

  void _showAllEventsDialog(DateTime date, List<Map<String, dynamic>> events) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 360,
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Events on ${DateFormat('MMM d, yyyy').format(date)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final e = events[index];
                      final st = DateTime.tryParse(e['startTime'] ?? '');
                      final timeStr = st != null ? DateFormat('h:mm a').format(st) : '';
                      final color = e['color'] != null 
                          ? Color(int.parse(e['color'].replaceFirst('#', '0xFF'))) 
                          : const Color(0xFF8B5CF6);
                          
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _showEventDetailsDialog(e);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e['title'] ?? 'Event', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                    const SizedBox(height: 2),
                                    Text(timeStr, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8), size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildModernDialogRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF2563EB)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthCell(DateTime date, {bool isToday = false, bool isSelected = false, bool isOutside = false}) {
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFEFF6FF) : (isSelected ? const Color(0xFFF8FAFC) : Colors.transparent),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 8),
      child: isToday
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Color(0xFF8B5CF6), shape: BoxShape.circle),
              child: Text('${date.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : isSelected
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF8B5CF6), width: 1.5),
                  ),
                  child: Text('${date.day}', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                )
              : Text('${date.day}', style: TextStyle(color: isOutside ? const Color(0xFF94A3B8) : const Color(0xFF0F172A))),
    );
  }

  Widget _buildMonthView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight - 32 - 48; // 32 for padding, 48 for days of week header
        final calculatedRowHeight = availableHeight / 6;
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: TableCalendar(
            daysOfWeekHeight: 48,
            rowHeight: calculatedRowHeight,
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        calendarFormat: CalendarFormat.month,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
          final events = _getEventsForDay(selectedDay);
          if (events.isNotEmpty) {
            _showAllEventsDialog(selectedDay, events.cast<Map<String, dynamic>>());
          } else {
            setState(() {
              _currentView = 'Day';
            });
          }
        },
        headerVisible: false,
        daysOfWeekStyle: const DaysOfWeekStyle(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
        ),
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: true,
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, date, events) => _buildMonthCell(date),
          todayBuilder: (context, date, events) => _buildMonthCell(date, isToday: true),
          selectedBuilder: (context, date, events) {
            final bool isActualToday = isSameDay(date, DateTime.now());
            return _buildMonthCell(date, isToday: isActualToday, isSelected: !isActualToday);
          },
          outsideBuilder: (context, date, events) => _buildMonthCell(date, isOutside: true),
          markerBuilder: (context, date, events) {
            if (events.isEmpty) return null;
            return Positioned(
              left: 4,
              right: 4,
              bottom: 2,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (events.length == 1)
                    ...events.map((e) {
                      final eventMap = e as Map<String, dynamic>;
                      final color = eventMap['color'] != null 
                          ? Color(int.parse(eventMap['color'].replaceFirst('#', '0xFF'))) 
                          : const Color(0xFF8B5CF6);
                      return GestureDetector(
                        onTap: () => _showEventDetailsDialog(eventMap),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            eventMap['title'] ?? 'Event',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }).toList()
                  else if (events.length > 1)
                    GestureDetector(
                      onTap: () => _showAllEventsDialog(date, events.cast<Map<String, dynamic>>()),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: events.take(3).map((e) {
                              final eventMap = e as Map<String, dynamic>;
                              final color = eventMap['color'] != null 
                                  ? Color(int.parse(eventMap['color'].replaceFirst('#', '0xFF'))) 
                                  : const Color(0xFF8B5CF6);
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }).toList(),
                          ),
                          if (events.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+${events.length - 3} more',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ));
          },
        ),
        eventLoader: _getEventsForDay,
          ),
        );
      }
    );
  }

  Widget _buildWeekView() {
    final startOfWeek = _focusedDay.subtract(Duration(days: _focusedDay.weekday % 7));
    final weekDays = List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
    
    return Column(
      children: [
        // Week Header
        Row(
          children: [
            const SizedBox(width: 60),
            ...weekDays.map((day) {
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)), right: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Column(
                    children: [
                      Text(DateFormat('E').format(day).toUpperCase(), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSameDay(day, DateTime.now()) ? const Color(0xFF2563EB) : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          day.day.toString(),
                          style: TextStyle(
                            fontSize: 16,
                            color: isSameDay(day, DateTime.now()) ? Colors.white : const Color(0xFF0F172A),
                            fontWeight: isSameDay(day, DateTime.now()) ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
        // Week Grid
        Expanded(
          child: ListView.builder(
            itemCount: 24,
            itemBuilder: (context, index) {
              final hour = index % 12 == 0 ? 12 : index % 12;
              final ampm = index < 12 ? 'AM' : 'PM';
              
              final now = DateTime.now();
              final isCurrentHour = now.hour == index;

              return Container(
                height: 48,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 60,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                        child: Text(
                          "$hour $ampm",
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    ...weekDays.map((day) {
                      final isToday = isSameDay(day, now);
                      final showCurrentTimeLine = isToday && isCurrentHour;
                      
                      final dayEvents = _getEventsForDay(day);
                      final eventsInHour = dayEvents.where((e) {
                        final st = DateTime.tryParse(e['startTime'] ?? '');
                        if (st != null) return st.hour == index;
                        return false;
                      }).toList();

                      return Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(right: BorderSide(color: Color(0xFFF1F5F9))),
                          ),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openEventCreationDialog(day, hour: index),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                              if (eventsInHour.isNotEmpty)
                                Positioned(
                                  top: 0, bottom: 0, left: 0, right: 0,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: eventsInHour.map((e) {
                                      return Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 1.0),
                                          child: _buildEventBlock(e, Colors.blue),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              if (showCurrentTimeLine)
                                Positioned(
                                  top: (now.minute / 60) * 48,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        transform: Matrix4.translationValues(-4, 0, 0),
                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 2,
                                          color: Colors.red,
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
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildYearView() {
    final year = _focusedDay.year;
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.75,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        final monthDate = DateTime(year, index + 1, 1);
        return GestureDetector(
          onTap: () {
            setState(() {
              _focusedDay = monthDate;
              _currentView = 'Month';
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMMM').format(monthDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                const SizedBox(height: 8),
                Expanded(
                  child: IgnorePointer(
                    child: TableCalendar(
                      rowHeight: 24,
                      daysOfWeekHeight: 20,
                      firstDay: DateTime(year, index + 1, 1),
                      lastDay: DateTime(year, index + 2, 0),
                      focusedDay: monthDate,
                      calendarFormat: CalendarFormat.month,
                      headerVisible: false,
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        weekendStyle: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                      calendarStyle: const CalendarStyle(
                        defaultTextStyle: TextStyle(fontSize: 11),
                        weekendTextStyle: TextStyle(fontSize: 11),
                        todayTextStyle: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        outsideDaysVisible: false,
                        cellMargin: EdgeInsets.all(2),
                        cellPadding: EdgeInsets.zero,
                        markersMaxCount: 0,
                        todayDecoration: BoxDecoration(
                          color: Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
