import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'patient_logs_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  StreamSubscription<DatabaseEvent>? _userSub;
  StreamSubscription<DatabaseEvent>? _patientSub;

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _doctorData;
  Map<String, dynamic>? _caregiverData;

  bool _loadingUser = true;
  bool _loadingPatient = true;
  bool _loadingConnections = false;

  int _scheduleOffset = 0; // for My Schedule arrows

  @override
  void initState() {
    super.initState();
    _listenUserProfile();
  }

  void _listenUserProfile() {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loadingUser = false;
        _loadingPatient = false;
      });
      return;
    }

    final ref = _db.ref('users/${user.uid}');
    _userSub = ref.onValue.listen((event) {
      if (event.snapshot.value == null) {
        setState(() {
          _userProfile = null;
          _loadingUser = false;
        });
        // fallback: assume patientId == uid
        _listenPatient(user.uid);
        return;
      }
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _userProfile = map;
        _loadingUser = false;
      });

      final patientId = map['linkedPatientId']?.toString();
      if (patientId != null && patientId.isNotEmpty) {
        _listenPatient(patientId);
      } else {
        // fallback to uid as patientId
        _listenPatient(user.uid);
      }
    });
  }

  void _listenPatient(String patientId) {
    _patientSub?.cancel();
    setState(() {
      _loadingPatient = true;
      _patientData = null;
      _doctorData = null;
      _caregiverData = null;
    });

    final ref = _db.ref('patients/$patientId');
    _patientSub = ref.onValue.listen((event) async {
      if (event.snapshot.value == null) {
        setState(() {
          _patientData = null;
          _loadingPatient = false;
        });
        return;
      }
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        _patientData = map;
        _loadingPatient = false;
        _scheduleOffset = 0; // reset when changed
      });
      await _loadConnections(map);
    });
  }

  Future<void> _loadConnections(Map<String, dynamic> patient) async {
    setState(() => _loadingConnections = true);
    Map<String, dynamic>? doctor;
    Map<String, dynamic>? caregiver;

    try {
      final clinicianId = patient['clinicianId']?.toString();
      final caregiverId = patient['caregiverId']?.toString(); // optional old linkage

      if (clinicianId != null && clinicianId.isNotEmpty) {
        final snap = await _db.ref('users/$clinicianId').get();
        if (snap.value != null) {
          doctor = Map<String, dynamic>.from(snap.value as Map);
        }
      }

      if (caregiverId != null && caregiverId.isNotEmpty) {
        final snap = await _db.ref('caregivers/$caregiverId').get();
        if (snap.value != null) {
          caregiver = Map<String, dynamic>.from(snap.value as Map);
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _doctorData = doctor;
      _caregiverData = caregiver;
      _loadingConnections = false;
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _patientSub?.cancel();
    super.dispose();
  }

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

  /* ---------------- Top bar actions ---------------- */

  Future<void> _sendFollowUp() async {
    if (_patientData == null) return;
    final patientId = _patientData!['id']?.toString() ?? '';
    if (patientId.isEmpty) return;

    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Request Follow-up'),
          content: TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message for your doctor',
              hintText: 'Describe your concern, symptoms, or questions',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final ref = _db.ref('patients/$patientId');
                await ref.update({
                  'needsFollowUp': true,
                  'followUpNote': noteCtrl.text.trim(),
                  'followUpRequestedAt': ServerValue.timestamp,
                });
                if (mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Follow-up request sent to your doctor')),
                  );
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  /* ---------------- Card 1: My Schedule ---------------- */

  List<_ScheduleItem> _buildScheduleItems() {
    if (_patientData == null) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final List<_ScheduleItem> items = [];

    // Appointments
    if (_patientData!['appointments'] is Map) {
      final apps = Map<String, dynamic>.from(_patientData!['appointments'] as Map);
      apps.forEach((key, value) {
        final m = Map<String, dynamic>.from(value as Map);
        final dt = m['datetime'];
        if (dt != null) {
          int? ms = dt is int ? dt : int.tryParse(dt.toString());
          if (ms != null && ms >= now) {
            items.add(_ScheduleItem(
              type: 'Appointment',
              dateMillis: ms,
              label: m['notes']?.toString() ?? 'Appointment',
              extra: (m['status'] ?? '').toString(),
            ));
          }
        }
      });
    }

    // Chemo sessions
    if (_patientData!['chemoHistory'] is Map) {
      final chemo = Map<String, dynamic>.from(_patientData!['chemoHistory'] as Map);
      chemo.forEach((key, value) {
        final m = Map<String, dynamic>.from(value as Map);
        final dt = m['date'];
        if (dt != null) {
          int? ms = dt is int ? dt : int.tryParse(dt.toString());
          if (ms != null && ms >= now) {
            items.add(_ScheduleItem(
              type: 'Chemo',
              dateMillis: ms,
              label: m['remarks']?.toString() ?? 'Chemo session',
              extra: (m['completed'] == true) ? 'Completed' : 'Planned',
            ));
          }
        }
      });
    }

    // Sort by date
    items.sort((a, b) => a.dateMillis.compareTo(b.dateMillis));
    return items;
  }

  Widget _buildMyScheduleCard() {
    if (_loadingPatient) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_patientData == null) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No schedule available.'),
        ),
      );
    }

    final scheduleItems = _buildScheduleItems();
    final medicines = (_patientData!['medicines'] is Map)
        ? Map<String, dynamic>.from(_patientData!['medicines'] as Map)
        : <String, dynamic>{};

    // For arrows
    final total = scheduleItems.length;
    final canLeft = _scheduleOffset > 0;
    final canRight = _scheduleOffset + 3 < total;

    final visible = scheduleItems.skip(_scheduleOffset).take(3).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'My Schedule',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_left),
                onPressed: canLeft
                    ? () {
                  setState(() {
                    _scheduleOffset = (_scheduleOffset - 1).clamp(0, (total - 1).clamp(0, total));
                  });
                }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right),
                onPressed: canRight
                    ? () {
                  setState(() {
                    _scheduleOffset = (_scheduleOffset + 1).clamp(0, (total - 1).clamp(0, total));
                  });
                }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (visible.isEmpty)
            const Text('No upcoming items.')
          else
            Column(
              children: visible.map((item) {
                final dateStr = _formatDate(item.dateMillis);
                IconData icon;
                Color color;
                if (item.type == 'Chemo') {
                  icon = Icons.local_hospital;
                  color = Colors.purple;
                } else {
                  icon = Icons.event;
                  color = Colors.blue;
                }
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: color),
                  title: Text('${item.type} — $dateStr'),
                  subtitle: Text(item.label),
                  trailing: item.extra.isNotEmpty ? Text(item.extra, style: const TextStyle(fontSize: 12)) : null,
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          if (medicines.isNotEmpty) ...[
            const Divider(),
            const Text('Medicines', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ...medicines.entries.take(3).map((e) {
              final m = Map<String, dynamic>.from(e.value as Map);
              final name = m['name']?.toString() ?? 'Medicine';
              final time = m['time']?.toString() ?? '';
              final freq = m['frequency']?.toString() ?? '';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.medication_outlined),
                title: Text(name),
                subtitle: Text('$time  •  $freq'),
              );
            }),
            if (medicines.length > 3) Text('+ ${medicines.length - 3} more', style: const TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  /* ---------------- Card 2: Logs ---------------- */

  Future<void> _openLogDialog() async {
    if (_patientData == null) return;
    final patientId = _patientData!['id']?.toString() ?? '';
    if (patientId.isEmpty) return;

    String eating = 'Average';
    int sleepHours = 7;
    String feeling = 'Calm';
    DateTime selectedDate = DateTime.now();

    final feelings = ['Happy', 'Calm', 'Anxious', 'Sad', 'Tired', 'In Pain'];
    final activitiesOptions = ['Read Book', 'Meditation', 'Walk', 'Idle', 'Watch Movie', 'Other'];
    final Set<String> selectedActivities = {'Idle'};
    final otherCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Daily Health Log'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date picker
                  const Text('Log date'),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                    icon: const Icon(Icons.today),
                    label: Text(selectedDate.toLocal().toString().split(' ')[0]),
                  ),
                  const SizedBox(height: 12),

                  const Text('Eating habits'),
                  DropdownButton<String>(
                    value: eating,
                    items: ['Poor', 'Average', 'Good']
                        .map((e) => DropdownMenuItem<String>(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => eating = v ?? 'Average'),
                  ),
                  const SizedBox(height: 12),

                  const Text('Sleeping hours'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(() => sleepHours = (sleepHours - 1).clamp(0, 24)),
                      ),
                      Text('$sleepHours h'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => setState(() => sleepHours = (sleepHours + 1).clamp(0, 24)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  const Text('How are you feeling?'),
                  Wrap(
                    spacing: 8,
                    children: feelings.map((f) {
                      final selected = feeling == f;
                      return ChoiceChip(
                        label: Text(f),
                        selected: selected,
                        onSelected: (_) => setState(() => feeling = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  const Text('Extra activities'),
                  Wrap(
                    spacing: 8,
                    children: activitiesOptions.map((act) {
                      final selected = selectedActivities.contains(act);
                      return FilterChip(
                        label: Text(act),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            if (selected) {
                              selectedActivities.remove(act);
                            } else {
                              selectedActivities.add(act);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (selectedActivities.contains('Other')) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: otherCtrl,
                      decoration: const InputDecoration(labelText: 'Other activity'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final List<String> activities = selectedActivities.toList();
                  if (activities.contains('Other')) {
                    final other = otherCtrl.text.trim();
                    if (other.isNotEmpty) activities.add(other);
                  }
                  activities.removeWhere((a) => a == 'Other');

                  final ref = _db.ref('patients/$patientId/dailyLogs').push();
                  final id = ref.key ?? '';
                  await ref.set({
                    'id': id,
                    'date': DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    ).millisecondsSinceEpoch,
                    'eating': eating,
                    'sleepHours': sleepHours,
                    'feeling': feeling,
                    'activities': activities,
                  });
                  if (mounted) Navigator.of(ctx).pop();
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildLogsCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 100,
          child: Center(
            child: _loadingPatient ? const CircularProgressIndicator() : const Text('No logs available.'),
          ),
        ),
      );
    }

    final logsMap = (_patientData!['dailyLogs'] is Map)
        ? Map<String, dynamic>.from(_patientData!['dailyLogs'] as Map)
        : <String, dynamic>{};

    final logs = logsMap.entries.map((e) => Map<String, dynamic>.from(e.value as Map)).toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    final patientId = _patientData!['id']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Logs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  TextButton(
                    onPressed: patientId.isEmpty
                        ? null
                        : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientLogsScreen(patientId: patientId),
                        ),
                      );
                    },
                    child: const Text('View all'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: _openLogDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Log'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            const Text('No logs yet. Start by adding your first daily log.')
          else
            Column(
              children: logs.take(3).map((log) {
                final dateStr = _formatDate(log['date']);
                final eating = log['eating']?.toString() ?? '-';
                final sleep = log['sleepHours']?.toString() ?? '-';
                final feeling = log['feeling']?.toString() ?? '-';
                final activities = (log['activities'] is List)
                    ? (log['activities'] as List).map((e) => e.toString()).join(', ')
                    : '';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.today),
                  title: Text(dateStr),
                  subtitle: Text('Eating: $eating  •  Sleep: $sleep h  •  Feeling: $feeling'),
                  trailing: activities.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Activities on $dateStr'),
                          content: Text(activities),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                          ],
                        ),
                      );
                    },
                  )
                      : null,
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }

  /* ---------------- Card 3: My Journey ---------------- */

  Widget _buildJourneyCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 120,
          child: Center(
            child: _loadingPatient ? const CircularProgressIndicator() : const Text('No journey data yet.'),
          ),
        ),
      );
    }

    final doctorNotes = _patientData!['doctorNotes']?.toString() ?? '';
    final progress = _patientData!['progressSummary']?.toString() ?? '';
    final chemoMap = (_patientData!['chemoHistory'] is Map)
        ? Map<String, dynamic>.from(_patientData!['chemoHistory'] as Map)
        : <String, dynamic>{};

    final chemoList = chemoMap.entries.map((e) => Map<String, dynamic>.from(e.value as Map)).toList()
      ..sort((a, b) => (a['date'] ?? 0).compareTo(b['date'] ?? 0));

    final total = chemoList.length;
    final completed = chemoList.where((c) => c['completed'] == true).length;
    final percent = total == 0 ? 0.0 : (completed / total);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Journey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (doctorNotes.isNotEmpty) ...[
            const Text('Doctor’s notes:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(doctorNotes),
            const SizedBox(height: 8),
          ],
          if (progress.isNotEmpty) ...[
            const Text('Progress summary:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(progress),
            const SizedBox(height: 12),
          ],
          const Text('Chemo Chart (simplified)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: percent, minHeight: 8),
          const SizedBox(height: 4),
          Text('$completed of $total sessions completed'),
          const SizedBox(height: 12),
          const Text('Chemo sessions', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (chemoList.isEmpty)
            const Text('No chemo sessions recorded yet.')
          else
            Column(
              children: chemoList.map((c) {
                final dateStr = _formatDate(c['date']);
                final remarks = c['remarks']?.toString() ?? '';
                final completed = c['completed'] == true;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    completed ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: completed ? Colors.green : Colors.orange,
                  ),
                  title: Text(dateStr),
                  subtitle: remarks.isNotEmpty ? Text(remarks) : null,
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }

  /* ---------------- Card 4: Connections ---------------- */

  Future<void> _callNumber(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start call')));
      }
    }
  }

  Future<void> _messageNumber(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri.parse('sms:$phone');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open messaging app')));
      }
    }
  }

  Widget _buildContactRow({
    required String title,
    required String? name,
    required String? phone,
    required VoidCallback onMessage,
  }) {
    return ListTile(
      leading: const Icon(Icons.person),
      title: Text(title),
      subtitle: Text(name ?? 'Not linked'),
      trailing: (name == null)
          ? null
          : Wrap(
        spacing: 4,
        children: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _callNumber(phone),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: onMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 80,
          child: Center(
            child: _loadingPatient ? const CircularProgressIndicator() : const Text('No connections available.'),
          ),
        ),
      );
    }

    final doctorName = _doctorData?['name']?.toString();
    final doctorPhone = _doctorData?['phone']?.toString();
    final caregiverName = _caregiverData?['name']?.toString();
    final caregiverPhone = _caregiverData?['phone']?.toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
            child: Text('Connections', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          _buildContactRow(
            title: 'Doctor',
            name: doctorName,
            phone: doctorPhone,
            onMessage: () {
              final clinicianUid = _patientData?['clinicianId']?.toString();
              if (clinicianUid == null || clinicianUid.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Doctor chat is not configured')));
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    peerUid: clinicianUid,
                    peerName: doctorName ?? 'Doctor',
                  ),
                ),
              );
            },
          ),
          const Divider(),
          _buildContactRow(
            title: 'Caregiver',
            name: caregiverName,
            phone: caregiverPhone,
            onMessage: () {
              // Prefer patient.caregiverUserUid; fallback to caregiverData.uid
              final caregiverUid =
                  _patientData?['caregiverUserUid']?.toString() ?? _caregiverData?['uid']?.toString();
              if (caregiverUid == null || caregiverUid.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Caregiver chat is not configured')));
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    peerUid: caregiverUid,
                    peerName: caregiverName ?? 'Caregiver',
                  ),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  /* ---------------- build() ---------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Follow-up',
            onPressed: _sendFollowUp,
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              final user = _auth.currentUser;
              showModalBottomSheet(
                context: context,
                builder: (ctx) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userProfile?['name']?.toString() ?? (user?.email ?? 'Patient'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: (_loadingUser && _loadingPatient)
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          _listenUserProfile();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 8),
            _buildMyScheduleCard(),
            _buildLogsCard(),
            _buildJourneyCard(),
            _buildConnectionsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Helper model ---------------- */

class _ScheduleItem {
  final String type; // "Appointment" or "Chemo"
  final int dateMillis;
  final String label;
  final String extra;

  _ScheduleItem({
    required this.type,
    required this.dateMillis,
    required this.label,
    required this.extra,
  });
}
