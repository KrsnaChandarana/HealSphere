import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/database_service.dart';
import 'caregiver_patient_logs_screen.dart';
import 'chat_screen.dart';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  // Brand accents (match clinician dashboard)
  final Color _purple = const Color(0xFF8E24AA);
  final Color _green = const Color(0xFF43A047);
  final Color _softBg = const Color(0xFFF6F7FB);

  bool _loading = true;
  bool _patientLoading = true;
  Map<String, dynamic>? _caregiverProfile;
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _clinicianProfile;

  StreamSubscription<DatabaseEvent>? _userSub;
  StreamSubscription<DatabaseEvent>? _patientSub;

  @override
  void initState() {
    super.initState();
    _listenCaregiverProfile();
  }

  void _listenCaregiverProfile() {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _patientLoading = false;
      });
      return;
    }

    final ref = _db.ref('users/${user.uid}');
    _userSub = ref.onValue.listen((event) {
      if (event.snapshot.value == null) {
        setState(() {
          _caregiverProfile = null;
          _loading = false;
        });
        return;
      }

      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _caregiverProfile = map;
        _loading = false;
      });

      final patientId = map['linkedPatientId']?.toString();
      if (patientId != null && patientId.isNotEmpty) {
        _listenPatient(patientId);
      } else {
        setState(() {
          _patientData = null;
          _patientLoading = false;
        });
      }
    });
  }

  void _listenPatient(String patientId) {
    _patientSub?.cancel();
    setState(() {
      _patientLoading = true;
      _patientData = null;
    });

    final ref = _db.ref('patients/$patientId');
    _patientSub = ref.onValue.listen((event) {
      if (event.snapshot.value == null) {
        setState(() {
          _patientData = null;
          _patientLoading = false;
        });
        return;
      }
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _patientData = map;
        _patientLoading = false;
      });
      _loadConnections(map);
    });
  }

  Future<void> _loadConnections(Map<String, dynamic> patient) async {
    final clinicianId = patient['clinicianId']?.toString();
    if (clinicianId == null || clinicianId.isEmpty) {
      setState(() {
        _clinicianProfile = null;
      });
      return;
    }

    final clinician = await DatabaseService.getUser(clinicianId);
    if (!mounted) return;
    setState(() {
      _clinicianProfile = clinician;
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _patientSub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  String _formatDateFromMillis(dynamic millis) {
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

  /* ------------------- UI cards ------------------------ */

  Widget _buildPatientOverviewCard() {
    if (_patientLoading) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_patientData == null) {
      return Card(
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No patient linked. Ask your clinician to link you to a patient.',
            style: TextStyle(fontSize: 14),
          ),
        ),
      );
    }

    final p = _patientData!;
    final name = (p['name'] ?? 'Patient').toString();
    final photoUrl = p['photoUrl']?.toString();
    final diagnosisDate = _formatDateFromMillis(p['diagnosisDate']);
    final summary =
    (p['conditionSummary'] ?? p['diagnosis'] ?? '').toString();
    final diagnosis = (p['diagnosis'] ?? 'Diagnosis not set').toString();

    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: _purple.withOpacity(0.08),
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(color: _purple),
              )
                  : null,
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(diagnosis),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: null, // still non-clickable
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Diagnosis: $diagnosisDate'),
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: _purple.withOpacity(0.9),
                    side: BorderSide(color: _purple.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  if (_patientData == null) return;
                  final patientUserUid =
                  _patientData!['patientUserUid']?.toString();
                  if (patientUserUid == null || patientUserUid.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Patient chat is not configured.'),
                      ),
                    );
                    return;
                  }
                  _openChat(patientUserUid,
                      _patientData!['name']?.toString() ?? 'Patient');
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat with Patient'),
                style: TextButton.styleFrom(
                  foregroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summary.isEmpty
                ? 'No condition summary added yet.'
                : summary,
            style: const TextStyle(fontSize: 14),
          )
        ]),
      ),
    );
  }

  Widget _buildChemoScheduleSection(Map<String, dynamic> chemoHistory) {
    if (chemoHistory.isEmpty) {
      return const Text('No chemo schedule available.');
    }

    final entries = chemoHistory.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (a['date'] ?? 0).compareTo(b['date'] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final dateStr = _formatDateFromMillis(e['date']);
        final completed = e['completed'] == true;
        final notes = (e['notes'] ?? '').toString();
        return ListTile(
          dense: true,
          leading: Icon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? _green : Colors.orange,
          ),
          title: Text(dateStr),
          subtitle: notes.isNotEmpty ? Text(notes) : null,
        );
      }).toList(),
    );
  }

  Widget _buildAppointmentsSection(Map<String, dynamic> appointments) {
    if (appointments.isEmpty) {
      return const Text('No appointments yet.');
    }

    final entries = appointments.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (a['datetime'] ?? 0).compareTo(b['datetime'] ?? 0));

    final now = DateTime.now().millisecondsSinceEpoch;
    final upcoming =
    entries.where((e) => (e['datetime'] ?? 0) >= now).toList();
    final past =
    entries.where((e) => (e['datetime'] ?? 0) < now).toList();

    String buildLabel(Map<String, dynamic> a) {
      final d = _formatDateFromMillis(a['datetime']);
      final notes = (a['notes'] ?? '').toString();
      final status = (a['status'] ?? '').toString();
      return '$d • ${status.isEmpty ? "scheduled" : status}'
          '${notes.isEmpty ? "" : " — $notes"}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upcoming',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (upcoming.isEmpty)
          const Text('No upcoming appointments.')
        else
          ...upcoming.map(
                (a) => ListTile(
              dense: true,
              leading: Icon(Icons.event_available, color: _green),
              title: Text(buildLabel(a)),
            ),
          ),
        const SizedBox(height: 10),
        const Text(
          'Past',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (past.isEmpty)
          const Text('No past appointments.')
        else
          ...past.map(
                (a) => ListTile(
              dense: true,
              leading: Icon(Icons.history, color: _purple),
              title: Text(buildLabel(a)),
            ),
          ),
      ],
    );
  }

  Widget _buildActivitiesSection(Map<String, dynamic> activities) {
    if (activities.isEmpty) {
      return const Text('No activities logged yet.');
    }

    final entries = activities.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final dateStr = _formatDateFromMillis(e['date']);
        final desc = (e['description'] ?? '').toString();
        return ListTile(
          dense: true,
          leading: Icon(Icons.check, color: _green),
          title: Text(desc),
          subtitle: Text(dateStr),
        );
      }).toList(),
    );
  }

  Future<void> _addActivityLog() async {
    if (_patientData == null) return;
    final patientId = _patientData!['id']?.toString();
    if (patientId == null || patientId.isEmpty) return;

    final descCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                'Add Activity',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (e.g. Walked, read book)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      'Date: ${selectedDate.toLocal().toString().split(' ')[0]}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final text = descCtrl.text.trim();
                    if (text.isEmpty) return;
                    final ts = DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    ).millisecondsSinceEpoch;
                    await DatabaseService.addActivity(
                      patientId: patientId,
                      description: text,
                      date: ts,
                      createdBy: _auth.currentUser?.uid ?? '',
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    minimumSize: const Size(90, 44),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActivitiesCard() {
    if (_patientLoading) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_patientData == null) {
      return const SizedBox.shrink();
    }

    final chemoHistory = _patientData!['chemoHistory'] != null
        ? Map<String, dynamic>.from(
        _patientData!['chemoHistory'] as Map)
        : <String, dynamic>{};
    final appointments = _patientData!['appointments'] != null
        ? Map<String, dynamic>.from(
        _patientData!['appointments'] as Map)
        : <String, dynamic>{};
    final activities = _patientData!['activities'] != null
        ? Map<String, dynamic>.from(
        _patientData!['activities'] as Map)
        : <String, dynamic>{};

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Patient Activities',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _purple,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chemo Schedule',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          _buildChemoScheduleSection(chemoHistory),
          const SizedBox(height: 12),
          const Text(
            'Appointments',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          _buildAppointmentsSection(appointments),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Activities Log',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextButton.icon(
                onPressed: _addActivityLog,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: _purple,
                ),
              ),
            ],
          ),
          _buildActivitiesSection(activities),
        ]),
      ),
    );
  }

  Widget _buildDailyLogsCard() {
    if (_patientLoading) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_patientData == null) {
      return const SizedBox.shrink();
    }

    final logsMap = (_patientData!['dailyLogs'] is Map)
        ? Map<String, dynamic>.from(
        _patientData!['dailyLogs'] as Map)
        : <String, dynamic>{};

    final patientId = _patientData!['id']?.toString() ?? '';
    final patientName =
        _patientData!['name']?.toString() ?? 'Patient';

    if (logsMap.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'No daily logs recorded yet.',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              TextButton(
                onPressed: patientId.isEmpty
                    ? null
                    : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CaregiverPatientLogsScreen(
                        patientId: patientId,
                        patientName: patientName,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: _purple,
                ),
                child: const Text('View all'),
              ),
            ],
          ),
        ),
      );
    }

    final logs = logsMap.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daily Health Logs',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              TextButton(
                onPressed: patientId.isEmpty
                    ? null
                    : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CaregiverPatientLogsScreen(
                        patientId: patientId,
                        patientName: patientName,
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: _purple,
                ),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Summary of recent logs recorded by the patient.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...logs.take(3).map((log) {
            final dateStr = _formatDateFromMillis(log['date']);
            final eating = log['eating']?.toString() ?? '-';
            final sleep = log['sleepHours']?.toString() ?? '-';
            final feeling = log['feeling']?.toString() ?? '-';
            final activities = (log['activities'] is List)
                ? (log['activities'] as List)
                .map((e) => e.toString())
                .join(', ')
                : '';

            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.today, color: _green),
              title: Text(dateStr),
              subtitle: Text(
                'Eating: $eating  •  Sleep: $sleep h  •  Feeling: $feeling',
                maxLines: 2,
              ),
              trailing: activities.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.info_outline, color: _purple),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Activities on $dateStr'),
                      content: Text(activities),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              )
                  : null,
            );
          }),
        ]),
      ),
    );
  }

  Widget _buildConnectionsCard() {
    if (_patientData == null) {
      return const SizedBox.shrink();
    }

    final clinicianName =
        _clinicianProfile?['name']?.toString() ?? 'Clinician';
    final clinicianPhone =
    _clinicianProfile?['phone']?.toString();
    final clinicianUid = _patientData?['clinicianId']?.toString();
    final patientName =
        _patientData?['name']?.toString() ?? 'Patient';
    final patientUid =
    _patientData?['patientUserUid']?.toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.local_hospital, color: _purple),
            title: Text(clinicianName),
            subtitle: clinicianPhone != null && clinicianPhone.isNotEmpty
                ? Text(clinicianPhone)
                : null,
            trailing: TextButton.icon(
              onPressed: clinicianUid == null || clinicianUid.isEmpty
                  ? null
                  : () => _openChat(clinicianUid, clinicianName),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat'),
              style: TextButton.styleFrom(
                foregroundColor: _purple,
              ),
            ),
          ),
          const Divider(height: 0),
          ListTile(
            leading: Icon(Icons.personal_injury, color: _green),
            title: Text(patientName),
            subtitle: const Text('Primary patient'),
            trailing: TextButton.icon(
              onPressed: patientUid == null || patientUid.isEmpty
                  ? null
                  : () => _openChat(patientUid, patientName),
              icon: const Icon(Icons.chat),
              label: const Text('Chat'),
              style: TextButton.styleFrom(
                foregroundColor: _purple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(String peerUid, String peerName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerUid: peerUid,
          peerName: peerName,
        ),
      ),
    );
  }

  /* ------------------- build ------------------------ */

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        title: const Text('Caregiver Dashboard'),
        backgroundColor: _purple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _caregiverProfile?['name']?.toString() ??
                              (user?.email ?? 'Caregiver'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (user?.email != null) Text(user!.email!),
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Sign out'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _signOut();
                          },
                        )
                      ],
                    ),
                  );
                },
              );
            },
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          _listenCaregiverProfile();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 8),
            _buildPatientOverviewCard(),
            _buildConnectionsCard(),
            _buildDailyLogsCard(),
            _buildActivitiesCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
