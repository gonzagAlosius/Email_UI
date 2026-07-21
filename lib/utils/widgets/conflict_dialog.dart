import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../config/app_config.dart';

/// Safely parses date-times from various formats (ISO string, Space separated, List/Array, Epoch ms)
DateTime? parseAnyDateTime(dynamic dateVal) {
  if (dateVal == null) return null;
  if (dateVal is List) {
    if (dateVal.length >= 3) {
      int year = dateVal[0] is int ? dateVal[0] : int.parse(dateVal[0].toString());
      int month = dateVal[1] is int ? dateVal[1] : int.parse(dateVal[1].toString());
      int day = dateVal[2] is int ? dateVal[2] : int.parse(dateVal[2].toString());
      int hour = dateVal.length > 3 ? (dateVal[3] is int ? dateVal[3] : int.parse(dateVal[3].toString())) : 0;
      int minute = dateVal.length > 4 ? (dateVal[4] is int ? dateVal[4] : int.parse(dateVal[4].toString())) : 0;
      int second = dateVal.length > 5 ? (dateVal[5] is int ? dateVal[5] : int.parse(dateVal[5].toString())) : 0;
      return DateTime(year, month, day, hour, minute, second);
    }
    return null;
  }
  
  String str = dateVal.toString().trim();
  if (str.isEmpty) return null;

  if (str.contains(' ') && !str.contains('T')) {
    str = str.replaceFirst(' ', 'T');
  }
  
  if (str.contains('.')) {
    final parts = str.split('.');
    str = parts[0];
  }
  
  DateTime? parsed = DateTime.tryParse(str);
  if (parsed != null) {
    return DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second);
  }
  return null;
}

/// Checks if any existing event overlaps with [newStart] and [newEnd].
/// Overlap condition: (newStart < existingEnd) && (newEnd > existingStart).
Future<Map<String, dynamic>?> checkEventConflict(
  Map<String, String> headers,
  DateTime newStart,
  DateTime newEnd, {
  dynamic ignoreEventId,
}) async {
  try {
    final url = '${AppConfig.instance.calendarUrl}/events';
    debugPrint("[ConflictCheck] Fetching events from $url");
    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    debugPrint("[ConflictCheck] HTTP status: ${response.statusCode}");
    if (response.statusCode == 200) {
      final List<dynamic> events = json.decode(response.body);
      debugPrint("[ConflictCheck] Total events fetched: ${events.length}");

      final DateTime nStart = DateTime(newStart.year, newStart.month, newStart.day, newStart.hour, newStart.minute);
      final DateTime nEnd = DateTime(newEnd.year, newEnd.month, newEnd.day, newEnd.hour, newEnd.minute);

      for (var e in events) {
        if (e is! Map<String, dynamic>) continue;
        if (ignoreEventId != null && e['id']?.toString() == ignoreEventId.toString()) continue;

        final eStart = parseAnyDateTime(e['startTime']);
        final eEnd = parseAnyDateTime(e['endTime']);

        debugPrint("[ConflictCheck] Checking event '${e['title']}': parsed start=$eStart, end=$eEnd");

        if (eStart != null && eEnd != null) {
          if (nStart.isBefore(eEnd) && nEnd.isAfter(eStart)) {
            debugPrint("[ConflictCheck] MATCHED CONFLICT: '${e['title']}'");
            return e;
          }
        }
      }
    }
  } catch (e, st) {
    debugPrint("[ConflictCheck] Exception: $e\n$st");
  }
  return null;
}

/// Displays a popup showing details of the conflicting event with "Add to Calendar" and "Cancel" buttons.
Future<bool?> showConflictConfirmationDialog(
  BuildContext context,
  Map<String, dynamic> conflictingEvent,
) {
  final title = conflictingEvent['title'] ?? 'Existing Meeting';
  final startTimeStr = conflictingEvent['startTime'];
  final endTimeStr = conflictingEvent['endTime'];
  final location = conflictingEvent['location'] ?? '';

  String timeFormatted = '';
  final start = parseAnyDateTime(startTimeStr);
  final end = parseAnyDateTime(endTimeStr);
  if (start != null) {
    timeFormatted = DateFormat('MMM d, yyyy • h:mm a').format(start);
    if (end != null) {
      timeFormatted += ' - ${DateFormat('h:mm a').format(end)}';
    }
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 24,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFEE2E2)),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time Slot Already Assigned',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'You already have a meeting scheduled at this time.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (timeFormatted.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              timeFormatted,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              location.toString(),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Add to Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
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
