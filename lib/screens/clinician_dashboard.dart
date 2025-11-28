// lib/screens/clinical_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'chat_screen.dart';
import 'add_patient.dart';
import 'patient_detail.dart';
import '../services/database_service.dart';

class ClinicalDashboard extends StatefulWidget {
  const ClinicalDashboard({super.key});

  @override
  State<ClinicalDashboard> createState() => _ClinicalDashboardState();
}

class _ClinicalDashboardState extends State<ClinicalDashboard> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  // Brand accents (aligned with your logo)
  final Color _purple = const Color(0xFF8E24AA);
  final Color _green = const Color(0xFF43A047);
  final Color _softBg = const Color(0xFFF6F7FB);
  final Color _redAccent = const Color(0xFFE53935);

  StreamSubscription<DatabaseEvent>? _patientsSub;
  StreamSubscription<DatabaseEvent>? _followUpsSub;
  List<PatientSummary> _patients = [];
  bool _loading = true;
  int _followUpCount = 0;

  @override
  void initState() {
    super.initState();
    _startListening();
    _listenFollowUps();
  }

  void _listenFollowUps() {
    final user = _auth.currentUser;
    if (user == null) return;

    _followUpsSub =
        DatabaseService.getFollowUpsForClinician(user.uid).listen((event) {
          if (!mounted) return;

          int count = 0;
          if (event.snapshot.value != null) {
            final map = Map<String, dynamic>.from(event.snapshot.value as Map);
            map.forEach((key, value) {
              final m = Map<String, dynamic>.from(value as Map);
              if (m['status']?.toString() == 'pending') {
                count++;
              }
            });
          }

          setState(() {
            _followUpCount = count;
          });
        });
  }

  void _startListening() {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _patients = [];
        _loading = false;
        _followUpCount = 0;
      });
      return;
    }

    // Listen to all patients and filter in Dart
    final ref = _db.ref('patients');

    _patientsSub?.cancel();
    _patientsSub = ref.onValue.listen((event) {
      final snapshot = event.snapshot;
      final List<PatientSummary> tmp = [];
      int followUps = 0;

      if (snapshot.value != null) {
        final raw = snapshot.value as Map; // Map<dynamic, dynamic>
        raw.forEach((key, value) {
          final m = Map<String, dynamic>.from(value as Map);

          // 🔑 Only keep patients where clinicianId == logged in clinician UID
          if (m['clinicianId']?.toString() == user.uid) {
            final p = PatientSummary.fromMap(m, key);
            tmp.add(p);
            if (m['needsFollowUp'] == true) {
              followUps += 1;
            }
          }
        });
      }

      tmp.sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _patients = tmp;
        _loading = false;
        _followUpCount = followUps;
      });
    }, onError: (err) {
      if (!mounted) return;
      setState(() {
        _patients = [];
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _patientsSub?.cancel();
    _followUpsSub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _openPatientDetail(String patientId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PatientDetail(patientId: patientId)),
    );
  }

  Future<void> _showMakeAppointmentDialog(
      String patientId, String patientName) async {
    final notesCtrl = TextEditingController();
    DateTime? date;
    TimeOfDay? time;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Make Appointment — $patientName',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _purple,
              ),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => date = picked);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      date == null
                          ? 'Pick date'
                          : 'Date: ${date!.toLocal().toString().split(' ')[0]}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) setState(() => time = picked);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    icon: const Icon(Icons.access_time),
                    label: Text(
                      time == null ? 'Pick time' : 'Time: ${time!.format(ctx)}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (date == null || time == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Select date and time')),
                    );
                    return;
                  }
                  final dt = DateTime(
                    date!.year,
                    date!.month,
                    date!.day,
                    time!.hour,
                    time!.minute,
                  );

                  final appointmentId = await DatabaseService.addAppointment(
                    patientId: patientId,
                    datetime: dt.millisecondsSinceEpoch,
                    notes: notesCtrl.text.trim(),
                    status: 'scheduled',
                  );

                  if (appointmentId != null) {
                    // Clear follow-up flag
                    await DatabaseService.clearFollowUp(patientId);
                  }

                  if (mounted) {
                    Navigator.of(ctx).pop();
                    if (appointmentId != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Appointment created')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Failed to create appointment')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(96, 44),
                ),
                child: const Text('Create'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _registerCaregiver(String patientId) async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final caregiverUserUidCtrl = TextEditingController(); // NEW

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Register Caregiver',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _purple,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: caregiverUserUidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Caregiver user UID (optional)',
                  helperText:
                  'Link to an existing caregiver login account for dashboard + chat.',
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
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final caregiverUserUid = caregiverUserUidCtrl.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter caregiver name')),
                  );
                  return;
                }

                // 1) Create caregiver record
                final ref = _db.ref('caregivers').push();
                final id = ref.key ?? '';
                await ref.set({
                  'id': id,
                  'name': name,
                  'phone': phone,
                  'linkedPatientId': patientId,
                  'createdAt': ServerValue.timestamp,
                });

                // 2) Update patient with caregiverId
                await _db.ref('patients/$patientId').update({
                  'caregiverId': id,
                  'updatedAt': ServerValue.timestamp,
                });

                // 3) Optionally link caregiver user account (if UID provided)
                if (caregiverUserUid.isNotEmpty) {
                  final caregiverUser =
                  await DatabaseService.getUser(caregiverUserUid);
                  if (caregiverUser == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Caregiver registered, but no user found with UID: $caregiverUserUid',
                          ),
                        ),
                      );
                    }
                  } else {
                    final ok = await DatabaseService.linkCareTeam(
                      patientId: patientId,
                      caregiverUid: caregiverUserUid,
                      caregiverRecordId: id,
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Caregiver saved, but linking to user account failed.',
                          ),
                        ),
                      );
                    }
                  }
                }

                if (mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                      Text('Caregiver registered and linked to patient'),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(96, 44),
              ),
              child: const Text('Register'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPatientCard(PatientSummary p) {
    // compute chemo completion percent
    final chemoTotal = p.chemoTotal ?? 0;
    final chemoCompleted = p.chemoCompleted ?? 0;
    final percent = chemoTotal == 0 ? 0.0 : (chemoCompleted / chemoTotal);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: _purple.withOpacity(0.08),
          backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty)
              ? NetworkImage(p.photoUrl!)
              : null,
          child: (p.photoUrl == null || p.photoUrl!.isEmpty)
              ? Text(
            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
            style: TextStyle(color: _purple),
          )
              : null,
        ),
        title: Text(
          p.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          p.diagnosis ?? 'No diagnosis',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Chemo progress row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chemo progress',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                        AlwaysStoppedAnimation<Color>(_green),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('$chemoCompleted/$chemoTotal sessions completed'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  Icon(Icons.calendar_today, color: _purple),
                  const SizedBox(height: 6),
                  Text(
                    p.nextAppointmentDate ?? '-',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),

          // Follow-up notes preview
          if (p.recentNote != null && p.recentNote!.isNotEmpty) ...[
            Text(
              'Last note:',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              p.recentNote!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],

          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openPatientDetail(p.id),
                icon: const Icon(Icons.person),
                label: const Text('Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showMakeAppointmentDialog(p.id, p.name),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Make Appointment'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _green),
                  foregroundColor: _green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final patientUserUid = p.patientUserUid;
                  if (patientUserUid == null || patientUserUid.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'This patient is not linked to a user account yet.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        peerUid: patientUserUid,
                        peerName: p.name,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _purple),
                  foregroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (p.caregiverUserUid != null &&
                  p.caregiverUserUid!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          peerUid: p.caregiverUserUid!,
                          peerName: p.caregiverName ?? 'Caregiver',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat),
                  label: const Text('Caregiver'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _green),
                    foregroundColor: _green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Assign caregiver',
                onPressed: () => _registerCaregiver(p.id),
                icon: Icon(Icons.person_add_alt_1, color: _purple),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        title: const Text('Clinician Dashboard'),
        backgroundColor: _purple,
        elevation: 0,
        actions: [
          // Notification icon with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FollowUpsScreen(),
                    ),
                  );
                },
              ),
              if (_followUpCount > 0)
                Positioned(
                  right: 8,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _redAccent,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Center(
                      child: Text(
                        _followUpCount > 9 ? '9+' : '$_followUpCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Profile icon
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) {
                  final user = _auth.currentUser;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.email ?? 'Profile',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          leading: const Icon(Icons.settings),
                          title: const Text('Profile & settings'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            // navigate to profile screen if implemented
                          },
                        ),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          _startListening();
        },
        child: _patients.isEmpty
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child:
              Text('No patients found. Tap + to add a patient.'),
            ),
          ],
        )
            : ListView.builder(
          padding:
          const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: _patients.length,
          itemBuilder: (context, index) {
            final p = _patients[index];
            return _buildPatientCard(p);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddPatientScreen()),
          );
        },
        tooltip: 'Add new patient',
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/* ------------------- Supporting models and small placeholder screens ------------------ */

class PatientSummary {
  final String id;
  final String name;
  final String? diagnosis;
  final String? photoUrl;
  final int? age;
  final int? chemoTotal;
  final int? chemoCompleted;
  final String? nextAppointmentDate;
  final String? recentNote;
  final String? patientUserUid;
  final String? caregiverUserUid;
  final String? caregiverName;

  PatientSummary({
    required this.id,
    required this.name,
    this.diagnosis,
    this.photoUrl,
    this.age,
    this.chemoTotal,
    this.chemoCompleted,
    this.nextAppointmentDate,
    this.recentNote,
    this.patientUserUid,
    this.caregiverUserUid,
    this.caregiverName,
  });

  factory PatientSummary.fromMap(Map<String, dynamic> m, String key) {
    // compute chemo totals if chemoHistory exists
    int completed = 0;
    int total = 0;
    String? nextAppDate;
    String? recentNote;

    if (m['chemoHistory'] is Map) {
      final chemo = Map<String, dynamic>.from(m['chemoHistory'] as Map);
      total = chemo.length;
      chemo.forEach((k, v) {
        final item = Map<String, dynamic>.from(v as Map);
        if (item['completed'] == true) completed += 1;
        // optional: compute latest note
        if (item['notes'] != null &&
            (recentNote == null || recentNote!.isEmpty)) {
          recentNote = item['notes'].toString();
        }
      });
    }

    if (m['appointments'] is Map) {
      final apps = Map<String, dynamic>.from(m['appointments'] as Map);
      // find next scheduled appointment (smallest datetime >= now)
      final now = DateTime.now().millisecondsSinceEpoch;
      int? minFuture;
      apps.forEach((k, v) {
        final item = Map<String, dynamic>.from(v as Map);
        final dt = (item['datetime'] is int)
            ? item['datetime'] as int
            : int.tryParse(item['datetime']?.toString() ?? '');
        if (dt != null) {
          if (dt >= now) {
            if (minFuture == null || dt < minFuture!) minFuture = dt;
          }
        }
      });
      if (minFuture != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(minFuture!);
        nextAppDate = dt.toLocal().toString().split(' ')[0];
      }
    }

    return PatientSummary(
      id: m['id']?.toString() ?? key,
      name: m['name']?.toString() ?? 'Unnamed',
      diagnosis: m['diagnosis']?.toString(),
      photoUrl: m['photoUrl']?.toString(),
      age: (m['age'] is int)
          ? (m['age'] as int)
          : (m['age'] != null ? int.tryParse(m['age'].toString()) : null),
      chemoTotal: total,
      chemoCompleted: completed,
      nextAppointmentDate: nextAppDate,
      recentNote: recentNote,
      patientUserUid: m['patientUserUid']?.toString(),
      caregiverUserUid: m['caregiverUserUid']?.toString(),
      caregiverName: m['caregiverName']?.toString(), // optional if you store it
    );
  }
}

/* Placeholder Chat screen: replace with real chat implementation later */
class ChatPlaceholderScreen extends StatelessWidget {
  final String patientId;
  final String patientName;
  const ChatPlaceholderScreen({
    required this.patientId,
    required this.patientName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat — $patientName')),
      body: const Center(child: Text('Chat feature not implemented yet.')),
    );
  }
}

/* FollowUps screen that shows follow-up requests from /followUps */
class FollowUpsScreen extends StatelessWidget {
  const FollowUpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    final Color green = const Color(0xFF43A047);

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: StreamBuilder<DatabaseEvent>(
        stream: DatabaseService.getFollowUpsForClinician(user.uid),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final s = snap.data!.snapshot;
          final List<Map<String, dynamic>> followList = [];

          if (s.value != null) {
            final map = Map<String, dynamic>.from(s.value as Map);
            map.forEach((k, v) {
              final m = Map<String, dynamic>.from(v as Map);
              if (m['status']?.toString() == 'pending') {
                followList.add({
                  'id': m['id'] ?? k,
                  'patientId': m['patientId'] ?? '',
                  'patientName': m['patientName'] ?? 'Unnamed',
                  'note': m['note'] ?? '',
                  'requestedAt': m['requestedAt'],
                });
              }
            });
          }

          if (followList.isEmpty) {
            return const Center(
              child: Text('No follow-ups at the moment.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: followList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final it = followList[idx];
              final requestedAt = it['requestedAt'];
              String dateStr = '';
              if (requestedAt != null) {
                final ms = requestedAt is int
                    ? requestedAt
                    : int.tryParse(requestedAt.toString());
                if (ms != null) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
                  dateStr = dt.toLocal().toString().split(' ')[0];
                }
              }

              return ListTile(
                title: Text(it['patientName'] ?? 'Unnamed'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dateStr.isNotEmpty) Text('Requested: $dateStr'),
                    const SizedBox(height: 4),
                    Text(it['note'] ?? ''),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await DatabaseService.updateFollowUpStatus(
                      clinicianId: user.uid,
                      followUpId: it['id'],
                      status: 'resolved',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(80, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Resolve'),
                ),
                onTap: () {
                  final patientId = it['patientId']?.toString();
                  if (patientId != null && patientId.isNotEmpty) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientDetail(patientId: patientId),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
