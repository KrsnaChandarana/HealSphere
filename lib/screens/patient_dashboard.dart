import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'patient_logs_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_screen.dart';
import '../services/database_service.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;
  String? _currentPatientId;
  String? _currentUserId;

  // Brand accents
  final Color _purple = const Color(0xFF8E24AA);
  final Color _green = const Color(0xFF43A047);
  final Color _softBg = const Color(0xFFF6F7FB);

  StreamSubscription<DatabaseEvent>? _userSub;
  StreamSubscription<DatabaseEvent>? _patientSub;

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _patientData;
  Map<String, dynamic>? _doctorData;
  Map<String, dynamic>? _caregiverData;

  bool _loadingUser = true;
  bool _loadingPatient = true;

  int _scheduleOffset = 0;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      _listenUserProfile();
    } else {
      setState(() {
        _loadingUser = false;
        _loadingPatient = false;
      });
    }
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
      if (!mounted) return;

      if (event.snapshot.value == null) {
        setState(() {
          _userProfile = null;
          _loadingUser = false;
        });
        // Try to find patient by user ID
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
        // Try patientId == uid
        _listenPatient(user.uid);
      }
    });
  }

  void _listenPatient(String patientId) {
    _patientSub?.cancel();
    setState(() {
      _currentPatientId = patientId;
      _loadingPatient = true;
      _patientData = null;
      _doctorData = null;
      _caregiverData = null;
    });

    final ref = _db.ref('patients/$patientId');
    _patientSub = ref.onValue.listen((event) async {
      if (!mounted) return;

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
        _scheduleOffset = 0;
      });

      await _loadConnections(map);
    });
  }

  Future<void> _loadConnections(Map<String, dynamic> patient) async {
    Map<String, dynamic>? doctor;
    Map<String, dynamic>? caregiver;

    try {
      final clinicianId = patient['clinicianId']?.toString();
      final caregiverUserUid = patient['caregiverUserUid']?.toString();
      final caregiverId = patient['caregiverId']?.toString();

      if (clinicianId != null && clinicianId.isNotEmpty) {
        final snap = await _db.ref('users/$clinicianId').get();
        if (snap.value != null) {
          doctor = Map<String, dynamic>.from(snap.value as Map);
        }
      }

      if (caregiverUserUid != null && caregiverUserUid.isNotEmpty) {
        final snap = await _db.ref('users/$caregiverUserUid').get();
        if (snap.value != null) {
          caregiver = Map<String, dynamic>.from(snap.value as Map);
        }
      } else if (caregiverId != null && caregiverId.isNotEmpty) {
        final snap = await _db.ref('caregivers/$caregiverId').get();
        if (snap.value != null) {
          caregiver = Map<String, dynamic>.from(snap.value as Map);
        }
      }
    } catch (_) {
      // silent
    }

    if (!mounted) return;
    setState(() {
      _doctorData = doctor;
      _caregiverData = caregiver;
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

  Future<void> _sendFollowUp() async {
    if (_patientData == null || _currentPatientId == null) return;

    final noteCtrl = TextEditingController();
    final patientName = _patientData!['name']?.toString() ?? 'Patient';
    final clinicianId = _patientData!['clinicianId']?.toString();

    if (clinicianId == null || clinicianId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No clinician assigned')),
        );
      }
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Request Follow-up',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _purple,
            ),
          ),
          content: TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message for your doctor',
              hintText: 'Describe your concern, symptoms, or questions',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );

    if (result == true && mounted) {
      final note = noteCtrl.text.trim();
      if (note.isEmpty) return;

      final followUpId = await DatabaseService.createFollowUp(
        clinicianId: clinicianId,
        patientId: _currentPatientId!,
        patientName: patientName,
        note: note,
        createdBy: _currentUserId ?? '',
      );

      if (followUpId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Follow-up request sent to your doctor')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/login', (route) => false);
  }

  List<_ScheduleItem> _buildScheduleItems() {
    if (_patientData == null) return [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final List<_ScheduleItem> items = [];

    // Appointments
    if (_patientData!['appointments'] is Map) {
      final apps = Map<String, dynamic>.from(
          _patientData!['appointments'] as Map);
      apps.forEach((key, value) {
        final m = Map<String, dynamic>.from(value as Map);
        final dt = m['datetime'];
        if (dt != null) {
          int? ms = dt is int ? dt : int.tryParse(dt.toString());
          if (ms != null && ms >= now) {
            items.add(
              _ScheduleItem(
                type: 'Appointment',
                dateMillis: ms,
                label: m['notes']?.toString() ?? 'Appointment',
                extra: (m['status'] ?? '').toString(),
              ),
            );
          }
        }
      });
    }

    // Chemo sessions
    if (_patientData!['chemoHistory'] is Map) {
      final chemo = Map<String, dynamic>.from(
          _patientData!['chemoHistory'] as Map);
      chemo.forEach((key, value) {
        final m = Map<String, dynamic>.from(value as Map);
        final dt = m['date'];
        if (dt != null) {
          int? ms = dt is int ? dt : int.tryParse(dt.toString());
          if (ms != null && ms >= now) {
            items.add(
              _ScheduleItem(
                type: 'Chemo',
                dateMillis: ms,
                label: m['remarks']?.toString() ?? 'Chemo session',
                extra: (m['completed'] == true) ? 'Completed' : 'Planned',
              ),
            );
          }
        }
      });
    }

    items.sort((a, b) => a.dateMillis.compareTo(b.dateMillis));
    return items;
  }

  Widget _buildMyScheduleCard() {
    if (_loadingPatient) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 140,
          child: Center(child: CircularProgressIndicator()),
        ),
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
        ? Map<String, dynamic>.from(
        _patientData!['medicines'] as Map)
        : <String, dynamic>{};

    final total = scheduleItems.length;
    final canLeft = _scheduleOffset > 0;
    final canRight = _scheduleOffset + 3 < total;

    final visible = scheduleItems.skip(_scheduleOffset).take(3).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text(
                'My Schedule',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.arrow_left),
                color: canLeft ? _purple : Colors.grey,
                onPressed: canLeft
                    ? () {
                  setState(() {
                    _scheduleOffset =
                        (_scheduleOffset - 1).clamp(0, total - 1);
                  });
                }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right),
                color: canRight ? _purple : Colors.grey,
                onPressed: canRight
                    ? () {
                  setState(() {
                    _scheduleOffset =
                        (_scheduleOffset + 1).clamp(0, total - 1);
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
                  color = _purple;
                } else {
                  icon = Icons.event;
                  color = _green;
                }
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icon, color: color),
                  title: Text('${item.type} — $dateStr'),
                  subtitle: Text(item.label),
                  trailing: item.extra.isNotEmpty
                      ? Text(
                    item.extra,
                    style: const TextStyle(fontSize: 12),
                  )
                      : null,
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          if (medicines.isNotEmpty) ...[
            const Divider(),
            const Text(
              'Medicines',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...medicines.entries.take(3).map((e) {
              final m = Map<String, dynamic>.from(e.value as Map);
              final name = m['name']?.toString() ?? 'Medicine';
              final time = m['time']?.toString() ?? '';
              final freq = m['frequency']?.toString() ?? '';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.medication_outlined, color: _purple),
                title: Text(name),
                subtitle: Text('$time  •  $freq'),
              );
            }),
            if (medicines.length > 3)
              Text(
                '+ ${medicines.length - 3} more',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _openLogDialog() async {
    if (_patientData == null || _currentPatientId == null) return;

    String eating = 'Average';
    int sleepHours = 7;
    String feeling = 'Happy';
    DateTime selectedDate = DateTime.now();

    final feelings = [
      'Happy',
      'Calm',
      'Anxious',
      'Sad',
      'Tired',
      'In Pain'
    ];
    final activitiesOptions = [
      'Read Book',
      'Meditation',
      'Walk',
      'Idle',
      'Watch Movie',
      'Other'
    ];
    final Set<String> selectedActivities = {'Idle'};
    final otherCtrl = TextEditingController();

    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Daily Health Log',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _purple,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.today),
                    label: Text(
                      selectedDate
                          .toLocal()
                          .toString()
                          .split(' ')[0],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Eating habits'),
                  DropdownButton<String>(
                    value: eating,
                    isExpanded: true,
                    items: ['Poor', 'Average', 'Good']
                        .map(
                          (e) => DropdownMenuItem<String>(
                        value: e,
                        child: Text(e),
                      ),
                    )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => eating = v ?? 'Average'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sleeping hours'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(
                              () => sleepHours =
                              (sleepHours - 1).clamp(0, 24),
                        ),
                      ),
                      Text('$sleepHours h'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => setState(
                              () => sleepHours =
                              (sleepHours + 1).clamp(0, 24),
                        ),
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
                        selectedColor: _purple.withOpacity(0.2),
                        onSelected: (_) => setState(() => feeling = f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('Extra activities'),
                  Wrap(
                    spacing: 8,
                    children: activitiesOptions.map((act) {
                      final selected =
                      selectedActivities.contains(act);
                      return FilterChip(
                        label: Text(act),
                        selected: selected,
                        selectedColor: _green.withOpacity(0.2),
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
                      decoration: const InputDecoration(
                        labelText: 'Other activity',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final List<String> activities =
                  selectedActivities.toList();
                  if (activities.contains('Other')) {
                    final other = otherCtrl.text.trim();
                    if (other.isNotEmpty) activities.add(other);
                  }
                  activities.removeWhere((a) => a == 'Other');

                  final dateMillis = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                  ).millisecondsSinceEpoch;

                  final logId = await DatabaseService.addDailyLog(
                    patientId: _currentPatientId!,
                    date: dateMillis,
                    eating: eating,
                    sleepHours: sleepHours,
                    feeling: feeling,
                    activities: activities,
                  );

                  if (logId != null && mounted) {
                    Navigator.of(ctx).pop(true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _openActivityDialog() async {
    if (_currentPatientId == null || _currentUserId == null) return;

    DateTime selectedDateTime = DateTime.now();
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Activity date'),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDateTime,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDateTime = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.today),
                    label: Text(
                      selectedDateTime
                          .toLocal()
                          .toString()
                          .split(' ')[0],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'e.g. 30 minute walk in the park',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );

    if (result == true && mounted) {
      final desc = descCtrl.text.trim();
      if (desc.isEmpty) return;

      final millis = DateTime(
        selectedDateTime.year,
        selectedDateTime.month,
        selectedDateTime.day,
      ).millisecondsSinceEpoch;

      final actId = await DatabaseService.addActivity(
        patientId: _currentPatientId!,
        date: millis,
        description: desc,
        createdBy: _currentUserId!,
      );

      if (actId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activity saved')),
        );
      }
    }
  }

  Widget _buildLogsCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 100,
          child: Center(
            child: _loadingPatient
                ? const CircularProgressIndicator()
                : const Text('No logs available.'),
          ),
        ),
      );
    }

    final logsMap = (_patientData!['dailyLogs'] is Map)
        ? Map<String, dynamic>.from(
        _patientData!['dailyLogs'] as Map)
        : <String, dynamic>{};

    final logs = logsMap.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    final patientId = _currentPatientId ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Logs',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: patientId.isEmpty
                        ? null
                        : () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientLogsScreen(
                            patientId: patientId,
                          ),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _purple,
                    ),
                    child: const Text('View all'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    onPressed: _openLogDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Log'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (logs.isEmpty)
            const Text(
              'No logs yet. Start by adding your first daily log.',
            )
          else
            Column(
              children: logs.take(3).map((log) {
                final dateStr = _formatDate(log['date']);
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
              }).toList(),
            ),
        ]),
      ),
    );
  }

  Widget _buildJourneyCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 120,
          child: Center(
            child: _loadingPatient
                ? const CircularProgressIndicator()
                : const Text('No journey data yet.'),
          ),
        ),
      );
    }

    final doctorNotes = _patientData!['doctorNotes']?.toString() ?? '';
    final progress =
        _patientData!['progressSummary']?.toString() ?? '';
    final chemoMap = (_patientData!['chemoHistory'] is Map)
        ? Map<String, dynamic>.from(
        _patientData!['chemoHistory'] as Map)
        : <String, dynamic>{};

    final chemoList = chemoMap.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (a['date'] ?? 0).compareTo(b['date'] ?? 0));

    final total = chemoList.length;
    final completed =
        chemoList.where((c) => c['completed'] == true).length;
    final percent = total == 0 ? 0.0 : (completed / total);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'My Journey',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _purple,
            ),
          ),
          const SizedBox(height: 8),
          if (doctorNotes.isNotEmpty) ...[
            const Text(
              "Doctor's notes:",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(doctorNotes),
            const SizedBox(height: 8),
          ],
          if (progress.isNotEmpty) ...[
            const Text(
              'Progress summary:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(progress),
            const SizedBox(height: 12),
          ],
          const Text(
            'Chemo Chart',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: percent,
            minHeight: 8,
            backgroundColor: _purple.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(_green),
          ),
          const SizedBox(height: 4),
          Text('$completed of $total sessions completed'),
          const SizedBox(height: 12),
          const Text(
            'Chemo sessions',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
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
                    completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: completed ? _green : Colors.orange,
                  ),
                  title: Text(dateStr),
                  subtitle:
                  remarks.isNotEmpty ? Text(remarks) : null,
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }

  Widget _buildActivitiesCard() {
    if (_loadingPatient || _patientData == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SizedBox(
          height: 80,
          child: Center(
            child: _loadingPatient
                ? const CircularProgressIndicator()
                : const Text('No activities available.'),
          ),
        ),
      );
    }

    final activitiesMap = (_patientData!['activities'] is Map)
        ? Map<String, dynamic>.from(
        _patientData!['activities'] as Map)
        : <String, dynamic>{};

    final activities = activitiesMap.entries
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Activities',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _purple,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openActivityDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activities.isEmpty)
            const Text(
              'No activities logged yet.',
              style: TextStyle(fontSize: 14),
            )
          else
            Column(
              children: activities.take(5).map((a) {
                final dateStr = _formatDate(a['date']);
                final desc = a['description']?.toString() ?? '';
                final createdBy = a['createdBy']?.toString() ?? '';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline, color: _green),
                  title: Text(desc),
                  subtitle: Text('$dateStr  •  by $createdBy'),
                );
              }).toList(),
            ),
        ]),
      ),
    );
  }

  Future<void> _callNumber(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start call')),
        );
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
            child: _loadingPatient
                ? const CircularProgressIndicator()
                : const Text('No connections available.'),
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
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding:
            EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
            child: Text(
              'Connections',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildContactRow(
            title: 'Doctor',
            name: doctorName,
            phone: doctorPhone,
            onMessage: () {
              final clinicianUid =
              _patientData?['clinicianId']?.toString();
              if (clinicianUid == null || clinicianUid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Doctor chat is not configured')),
                );
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
              final caregiverUid =
                  _patientData?['caregiverUserUid']?.toString() ??
                      _caregiverData?['uid']?.toString();
              if (caregiverUid == null || caregiverUid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                      Text('Caregiver chat is not configured')),
                );
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

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        backgroundColor: _purple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Follow-up',
            onPressed: _sendFollowUp,
          ),
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
                          _userProfile?['name']?.toString() ??
                              (user?.email ?? 'Patient'),
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
            _buildActivitiesCard(),
            _buildConnectionsCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ScheduleItem {
  final String type;
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
