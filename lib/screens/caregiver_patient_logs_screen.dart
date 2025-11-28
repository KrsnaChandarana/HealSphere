import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';


class CaregiverPatientLogsScreen extends StatelessWidget {
  final String patientId;
  final String patientName;

  const CaregiverPatientLogsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

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
    final db = FirebaseDatabase.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text('Logs — $patientName'),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: db.ref('patients/$patientId/dailyLogs').onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(
              child: Text('No daily logs recorded yet.'),
            );
          }

          final raw = snapshot.data!.snapshot.value as Map;
          final logsMap = Map<String, dynamic>.from(raw);

          final logs = logsMap.entries
              .map((e) => Map<String, dynamic>.from(e.value as Map))
              .toList()
            ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0)); // latest first

          if (logs.isEmpty) {
            return const Center(
              child: Text('No daily logs recorded yet.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildSleepChartCard(logs),
              const SizedBox(height: 12),
              const Text(
                'All Daily Logs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...List.generate(logs.length, (index) {
                final log = logs[index];
                final dateStr = _formatDate(log['date']);
                final eating = log['eating']?.toString() ?? '-';
                final sleep = log['sleepHours']?.toString() ?? '-';
                final feeling = log['feeling']?.toString() ?? '-';
                final activities = (log['activities'] is List)
                    ? (log['activities'] as List)
                    .map((e) => e.toString())
                    .join(', ')
                    : '';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.today),
                    title: Text(dateStr),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Eating: $eating'),
                        Text('Sleep: $sleep h'),
                        Text('Feeling: $feeling'),
                        if (activities.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Activities: $activities'),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
  Widget _buildSleepChartCard(List<Map<String, dynamic>> logs) {
    // Reverse to show oldest on left, newest on right
    final reversed = logs.reversed.toList();

    final spots = <FlSpot>[];
    double maxY = 0;
    double minY = 24;

    for (int i = 0; i < reversed.length; i++) {
      final log = reversed[i];
      final sleep = log['sleepHours'];
      if (sleep is int || sleep is double || sleep is String) {
        final val = double.tryParse(sleep.toString()) ?? 0;
        spots.add(FlSpot(i.toDouble(), val));
        if (val > maxY) maxY = val;
        if (val < minY) minY = val;
      }
    }

    if (spots.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('No sleep data available for chart.'),
        ),
      );
    }

    // Some padding for axis
    maxY = (maxY + 1).clamp(0, 24);
    minY = (minY - 1).clamp(0, maxY);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sleep Trend',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hours of sleep over recent days',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: spots.length > 1 ? (spots.length - 1).toDouble() : 1,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}h',
                              style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= reversed.length) {
                            return const SizedBox.shrink();
                          }
                          final log = reversed[idx];
                          final dateStr = _formatDate(log['date']);
                          // show just day part
                          final short = dateStr.split('-').length == 3
                              ? dateStr.split('-').last
                              : dateStr;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              short,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      spots: spots,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
// TODO Implement this library.