import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class PatientLogsScreen extends StatelessWidget {
  final String patientId;
  PatientLogsScreen({super.key, required this.patientId});

  final _db = FirebaseDatabase.instance;

  String _formatDate(dynamic millis) {
    if (millis == null) return '-';
    int? ms;
    if (millis is int) {
      ms = millis;
    } else {
      ms = int.tryParse(millis.toString());
    }
    if (ms == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return dt.toLocal().toString().split(' ')[0];
  }

  @override
  Widget build(BuildContext context) {
    final ref = _db.ref('patients/$patientId/dailyLogs');

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Daily Logs'),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final snap = snapshot.data!.snapshot;
          if (snap.value == null) {
            return const Center(child: Text('No logs yet.'));
          }

          final map = Map<String, dynamic>.from(snap.value as Map);
          final logs = map.entries.map((e) => Map<String, dynamic>.from(e.value as Map)).toList()
            ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

          if (logs.isEmpty) {
            return const Center(child: Text('No logs yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final log = logs[index];
              final dateStr = _formatDate(log['date']);
              final eating = log['eating']?.toString() ?? '-';
              final sleep = log['sleepHours']?.toString() ?? '-';
              final feeling = log['feeling']?.toString() ?? '-';
              final activities = (log['activities'] is List)
                  ? (log['activities'] as List).map((e) => e.toString()).join(', ')
                  : '';

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dateStr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (feeling.isNotEmpty)
                          Chip(
                            label: Text(feeling),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Eating: $eating'),
                    Text('Sleep: $sleep h'),
                    if (activities.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text('Activities:', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(activities),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
