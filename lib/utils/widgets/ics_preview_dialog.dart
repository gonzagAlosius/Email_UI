import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class IcsPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> eventDetails;
  final VoidCallback onAddToCalendar;

  const IcsPreviewDialog({
    super.key,
    required this.eventDetails,
    required this.onAddToCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final title = eventDetails['title'] ?? 'Imported Event';
    final description = eventDetails['description'] ?? '';
    final location = eventDetails['location'] ?? '';
    final startTimeStr = eventDetails['startTime'];
    final endTimeStr = eventDetails['endTime'];

    String formattedDate = 'Unknown Date';
    String formattedTime = 'Unknown Time';

    if (startTimeStr != null) {
      final start = DateTime.parse(startTimeStr);
      formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(start);
      formattedTime = DateFormat('h:mm a').format(start);
      if (endTimeStr != null) {
        final end = DateTime.parse(endTimeStr);
        formattedTime += ' - ${DateFormat('h:mm a').format(end)}';
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 24,
      backgroundColor: Colors.white,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Event Preview',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(context).pop(),
                  splashRadius: 24,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event, color: Color(0xFF8B5CF6), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 8),
                          Text(
                            '$formattedDate • $formattedTime',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16, color: Color(0xFF64748B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Description',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  description,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAddToCalendar();
                },
                icon: const Icon(Icons.add_task),
                label: const Text('Add to Calendar', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
