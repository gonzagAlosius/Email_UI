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
  final Map<DateTime, List<dynamic>> _events = {};
  List<dynamic> _upcomingEvents = [];
  String _currentView = 'Month';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) _fetchEvents(isBackgroundRefresh: true);
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
      final response = await http.get(Uri.parse('${AppConfig.instance.calendarUrl}/events'), headers: headers);
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
                    icon: const Icon(Icons.add_circle, color: Color(0xFF2563EB), size: 32),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const EventCreationDialog(),
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
                      color: const Color(0xFF2563EB).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                    selectedDecoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
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
                              color: Color(0xFF2563EB),
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
                        icon: const Icon(Icons.add_circle, color: Color(0xFF2563EB), size: 32),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const EventCreationDialog(),
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
                          color: const Color(0xFF2563EB).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                        selectedDecoration: const BoxDecoration(
                          color: Color(0xFF2563EB),
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
                                  color: Color(0xFF2563EB),
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
          const Padding(
            padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text("Upcoming Events", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("No upcoming events", style: TextStyle(color: Colors.grey)),
            ),
          ...upcoming.map((event) {
            final startTime = DateTime.tryParse(event['startTime'] ?? '');
            final timeStr = startTime != null ? DateFormat('MMM d, h:mm a').format(startTime) : 'Unknown time';
            return _buildUpcomingEvent(event, timeStr, Colors.blue);
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
          children: [
            Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
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
            foregroundColor: const Color(0xFF2563EB),
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
              foregroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.all(12),
              minimumSize: const Size(0, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: Icon(icon, size: 18),
          );
        }

        Widget navigationGroup = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildNavButton(Icons.chevron_left, () {
              setState(() {
                if (_currentView == 'Day') {
                  _focusedDay = _focusedDay.subtract(const Duration(days: 1));
                } else if (_currentView == 'Week') {
                  _focusedDay = _focusedDay.subtract(const Duration(days: 7));
                } else if (_currentView == 'Month') {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, _focusedDay.day);
                } else if (_currentView == 'Year') {
                  _focusedDay = DateTime(_focusedDay.year - 1, _focusedDay.month, _focusedDay.day);
                }
                _selectedDay = _focusedDay;
              });
            }),
            const SizedBox(width: 8),
            buildNavButton(Icons.chevron_right, () {
              setState(() {
                if (_currentView == 'Day') {
                  _focusedDay = _focusedDay.add(const Duration(days: 1));
                } else if (_currentView == 'Week') {
                  _focusedDay = _focusedDay.add(const Duration(days: 7));
                } else if (_currentView == 'Month') {
                  _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, _focusedDay.day);
                } else if (_currentView == 'Year') {
                  _focusedDay = DateTime(_focusedDay.year + 1, _focusedDay.month, _focusedDay.day);
                }
                _selectedDay = _focusedDay;
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
                                  color: isCurrentSelection ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
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
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
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
    final title = event['title'] ?? 'No Title';
    final startTimeStr = event['startTime'];
    final endTimeStr = event['endTime'];
    final description = event['description'] ?? '';
    final organizer = event['organizerEmail'] ?? event['organizer'] ?? 'Unknown'; 

    String formatMockupTime(String? startStr, String? endStr) {
      if (startStr == null || startStr.isEmpty) return 'Unknown';
      final start = DateTime.tryParse(startStr);
      final end = DateTime.tryParse(endStr ?? '');
      if (start == null) return startStr;
      
      final datePart = DateFormat('EEE dd MMM yyyy').format(start);
      final startVal = DateFormat('hh:mm').format(start);
      final endVal = end != null ? DateFormat('hh:mm a').format(end) : '';
      
      if (endVal.isNotEmpty) {
        return '$datePart  •  $startVal - $endVal';
      } else {
        return '$datePart  •  $startVal';
      }
    }

    String calculateDuration(String? startStr, String? endStr) {
      if (startStr == null || endStr == null) return '';
      final start = DateTime.tryParse(startStr);
      final end = DateTime.tryParse(endStr);
      if (start == null || end == null) return '';
      final diff = end.difference(start);
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes} minutes';
      } else {
        final hours = diff.inHours;
        final mins = diff.inMinutes % 60;
        if (mins == 0) {
          return "$hours hour${hours > 1 ? 's' : ''}";
        } else {
          return "$hours hr $mins min";
        }
      }
    }

    final formattedTime = formatMockupTime(startTimeStr, endTimeStr);
    final durationStr = calculateDuration(startTimeStr, endTimeStr);

    String responseStatus = 'accepted';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Color pillBgColor;
            Color pillTextColor;
            String statusText;
            String statusSubtext;

            if (responseStatus == 'accepted') {
              pillBgColor = const Color(0xFFECFDF5);
              pillTextColor = const Color(0xFF10B981);
              statusText = 'Accepted';
              statusSubtext = 'You accepted this invitation.';
            } else if (responseStatus == 'tentative') {
              pillBgColor = const Color(0xFFEEF2FF);
              pillTextColor = const Color(0xFF4F46E5);
              statusText = 'Tentative';
              statusSubtext = 'You accepted this invitation as tentative.';
            } else {
              pillBgColor = const Color(0xFFFEF2F2);
              pillTextColor = const Color(0xFFEF4444);
              statusText = 'Declined';
              statusSubtext = 'You declined this invitation.';
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 8,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: Container(
                width: 500,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Calendar, Delete, Expand, Close
                      Padding(
                        padding: const EdgeInsets.only(left: 24, right: 16, top: 16, bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Calendar',
                              style: TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFF6B7280), size: 20),
                                  tooltip: 'Delete Event',
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    final id = event['id'];
                                    if (id != null) {
                                      final headers = await _getCalendarHeaders();
                                      try {
                                        final response = await http.delete(
                                          Uri.parse('${AppConfig.instance.calendarUrl}/events/$id'),
                                          headers: headers,
                                        );
                                        if (response.statusCode == 200) {
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event Deleted Successfully!')));
                                          _fetchEvents();
                                        } else {
                                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete event: ${response.statusCode}')));
                                        }
                                      } catch (e) {
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                                      }
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, color: Color(0xFF6B7280), size: 20),
                                  tooltip: 'Expand (Edit)',
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await showDialog(
                                      context: context,
                                      builder: (context) => ElaboratedEventDialog(
                                        event: event,
                                        onEventDeleted: () => _fetchEvents(),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Color(0xFF6B7280), size: 20),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      
                      // Event Title, Date and Duration
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Colors.blue,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          formattedTime,
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563), fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (durationStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 14),
                                      child: Text(
                                        durationStr,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      
                      // Organizer Row
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF2563EB),
                              radius: 18,
                              child: Text(
                                organizer.isNotEmpty ? organizer[0].toUpperCase() : 'U',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${organizer.split('@').first} invited you.',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: pillBgColor,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          statusText,
                                          style: TextStyle(color: pillTextColor, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    statusSubtext,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      
                      // Agenda Row
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.format_list_bulleted, color: Color(0xFF6B7280), size: 20),
                                SizedBox(width: 12),
                                Text(
                                  'Agenda',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                                borderRadius: BorderRadius.circular(8),
                                color: const Color(0xFFF9FAFB),
                              ),
                              child: Text(
                                description.isEmpty || description == 'No description provided.'
                                    ? 'No description provided.'
                                    : description,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      
                      // Footer (RSVP buttons)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    responseStatus = 'accepted';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Response updated to Accepted!')),
                                  );
                                },
                                icon: const Icon(Icons.check, size: 16),
                                label: const Text('Accepted', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: responseStatus == 'accepted' ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                                  backgroundColor: responseStatus == 'accepted' ? const Color(0xFFECFDF5) : Colors.white,
                                  side: BorderSide(color: responseStatus == 'accepted' ? const Color(0xFF10B981) : const Color(0xFFD1D5DB)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    responseStatus = 'tentative';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Response updated to Tentative!')),
                                  );
                                },
                                icon: const Icon(Icons.help_outline, size: 16),
                                label: const Text('Tentative', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: responseStatus == 'tentative' ? const Color(0xFF4F46E5) : const Color(0xFF6B7280),
                                  backgroundColor: responseStatus == 'tentative' ? const Color(0xFFEEF2FF) : Colors.white,
                                  side: BorderSide(color: responseStatus == 'tentative' ? const Color(0xFF4F46E5) : const Color(0xFFD1D5DB)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    responseStatus = 'declined';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Response updated to Declined!')),
                                  );
                                },
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text('Decline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: responseStatus == 'declined' ? const Color(0xFFEF4444) : const Color(0xFF6B7280),
                                  backgroundColor: responseStatus == 'declined' ? const Color(0xFFFEF2F2) : Colors.white,
                                  side: BorderSide(color: responseStatus == 'declined' ? const Color(0xFFEF4444) : const Color(0xFFD1D5DB)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            );
          },
        );
      },
    );
  }

  void _showAllEventsDialog(DateTime date, List<Map<String, dynamic>> events) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMMM d, yyyy').format(date), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final e = events[index];
                      final st = DateTime.tryParse(e['startTime'] ?? '');
                      final timeStr = st != null ? DateFormat('h:mm a').format(st) : '';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e['title'] ?? 'Event', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                        subtitle: Text(timeStr, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        onTap: () {
                          Navigator.pop(context);
                          _showEventDetailsDialog(e);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
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

  Widget _buildMonthCell(DateTime date, {bool isToday = false, bool isOutside = false}) {
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFEFF6FF) : Colors.transparent,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.5),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 8),
      child: isToday
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle),
              child: Text('${date.day}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          : Text('${date.day}', style: TextStyle(color: isOutside ? const Color(0xFF94A3B8) : const Color(0xFF0F172A))),
    );
  }

  Widget _buildMonthView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight - 32 - 48; // 32 for padding, 48 for days of week header
        final calculatedRowHeight = (availableHeight / 6).clamp(40.0, 200.0);
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
            _currentView = 'Day';
          });
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
          selectedBuilder: (context, date, events) => _buildMonthCell(date, isToday: true), // Reuse today styling for selected
          outsideBuilder: (context, date, events) => _buildMonthCell(date, isOutside: true),
          markerBuilder: (context, date, events) {
            if (events.isEmpty) return null;
            return Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...events.take(events.length > 2 ? 1 : events.length).map((e) {
                    final eventMap = e as Map<String, dynamic>;
                    return GestureDetector(
                      onTap: () => _showEventDetailsDialog(eventMap),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          eventMap['title'] ?? 'Event',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A8A)),
                        ),
                      ),
                    );
                  }).toList(),
                  if (events.length > 2)
                    GestureDetector(
                      onTap: () => _showAllEventsDialog(date, events.cast<Map<String, dynamic>>()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '+${events.length - 1} more',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            );
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
                      rowHeight: 26,
                      daysOfWeekHeight: 20,
                      firstDay: DateTime(year, index + 1, 1),
                      lastDay: DateTime(year, index + 2, 0),
                      focusedDay: monthDate,
                      calendarFormat: CalendarFormat.month,
                      headerVisible: false,
                      daysOfWeekStyle: const DaysOfWeekStyle(
                        weekdayStyle: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        weekendStyle: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      ),
                      calendarStyle: const CalendarStyle(
                        defaultTextStyle: TextStyle(fontSize: 12),
                        weekendTextStyle: TextStyle(fontSize: 12),
                        outsideDaysVisible: false,
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
