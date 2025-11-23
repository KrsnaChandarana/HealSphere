// lib/screens/clinical_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'chat_screen.dart';
import 'add_patient.dart';
import 'patient_detail.dart';

class ClinicalDashboard extends StatefulWidget {
  const ClinicalDashboard({super.key});

  @override
  State<ClinicalDashboard> createState() => _ClinicalDashboardState();
}

class _ClinicalDashboardState extends State<ClinicalDashboard> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  StreamSubscription<DatabaseEvent>? _patientsSub;
  List<PatientSummary> _patients = [];
  bool _loading = true;
  int _followUpCount = 0; // simple metric for notification badge

  @override
  void initState() {
    super.initState();
    _startListening();
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

    // Query patients that belong to this clinician
    final Query q = _db.ref('patients').orderByChild('clinicianId').equalTo(user.uid);

    _patientsSub?.cancel();
    _patientsSub = q.onValue.listen((event) {
      final snapshot = event.snapshot;
      final List<PatientSummary> tmp = [];
      int followUps = 0;

      if (snapshot.value != null) {
        final map = Map<String, dynamic>.from(snapshot.value as Map);
        map.forEach((key, value) {
          final m = Map<String, dynamic>.from(value as Map);
          final p = PatientSummary.fromMap(m, key);
          tmp.add(p);
          // simple rule: if record has 'needsFollowUp': true, count it
          if (m['needsFollowUp'] == true) followUps += 1;
        });
      }

      tmp.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _patients = tmp;
        _loading = false;
        _followUpCount = followUps;
      });
    }, onError: (err) {
      setState(() {
        _patients = [];
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _patientsSub?.cancel();
    super.dispose();
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _openPatientDetail(String patientId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetail(patientId: patientId)));
  }

  Future<void> _showMakeAppointmentDialog(String patientId, String patientName) async {
    final notesCtrl = TextEditingController();
    DateTime? date;
    TimeOfDay? time;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setState) {
          return AlertDialog(
            title: Text('Make Appointment — $patientName'),
            content: SizedBox(
              width: 320,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                    if (picked != null) setState(() => date = picked);
                  },
                  child: Text(date == null ? 'Pick date' : 'Date: ${date!.toLocal().toString().split(' ')[0]}'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    if (picked != null) setState(() => time = picked);
                  },
                  child: Text(time == null ? 'Pick time' : 'Time: ${time!.format(ctx)}'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (date == null || time == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select date and time')));
                    return;
                  }
                  final dt = DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
                  final ref = _db.ref('patients/$patientId/appointments').push();
                  final id = ref.key ?? '';
                  await ref.set({
                    'id': id,
                    'datetime': dt.millisecondsSinceEpoch,
                    'notes': notesCtrl.text.trim(),
                    'status': 'scheduled',
                    'createdAt': ServerValue.timestamp,
                  });
                  // optionally clear follow-up flag
                  await _db.ref('patients/$patientId').update({'needsFollowUp': false, 'updatedAt': ServerValue.timestamp});
                  if (mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment created')));
                  }
                },
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

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Register Caregiver'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final ref = _db.ref('caregivers').push();
                final id = ref.key ?? '';
                await ref.set({
                  'id': id,
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'linkedPatientId': patientId,
                  'createdAt': ServerValue.timestamp
                });
                // update patient record to link caregiver
                await _db.ref('patients/$patientId').update({'caregiverId': id, 'updatedAt': ServerValue.timestamp});
                if (mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caregiver registered and linked')));
                }
              },
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 2,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.deepPurple.shade50,
          backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty) ? NetworkImage(p.photoUrl!) : null,
          child: (p.photoUrl == null || p.photoUrl!.isEmpty) ? Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?') : null,
        ),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(p.diagnosis ?? 'No diagnosis', maxLines: 2, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          // Chemo progress row
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Chemo progress', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: percent, minHeight: 8),
                const SizedBox(height: 6),
                Text('$chemoCompleted/$chemoTotal sessions completed'),
              ]),
            ),
            const SizedBox(width: 12),
            Column(children: [
              Icon(Icons.calendar_today, color: Colors.deepPurple),
              const SizedBox(height: 6),
              Text(p.nextAppointmentDate ?? '-', style: const TextStyle(fontSize: 12)),
            ])
          ]),
          const SizedBox(height: 12),

          // Follow-up notes preview
          if (p.recentNote != null && p.recentNote!.isNotEmpty) ...[
            Text('Last note:', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(p.recentNote!, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
          ],

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openPatientDetail(p.id),
                icon: const Icon(Icons.person),
                label: const Text('Profile'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showMakeAppointmentDialog(p.id, p.name),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Make Appointment'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final patientUserUid = p.patientUserUid; // we’ll add this in model
                  if (patientUserUid == null || patientUserUid.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('This patient is not linked to a user account yet.')),
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
              ),

              IconButton(
                tooltip: 'Assign caregiver',
                onPressed: () => _registerCaregiver(p.id),
                icon: const Icon(Icons.person_add_alt_1),
              )
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinician Dashboard'),
        actions: [
          // Notification icon with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () {
                  // Open a follow-ups panel or simple list
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => FollowUpsScreen()));
                },
              ),
              if (_followUpCount > 0)
                Positioned(
                  right: 8,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Center(
                      child: Text(
                        _followUpCount > 9 ? '9+' : '$_followUpCount',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
              // show simple profile / logout menu
              showModalBottomSheet(
                context: context,
                builder: (ctx) {
                  final user = _auth.currentUser;
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user?.email ?? 'Profile', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
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
                    ]),
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
          // reattach listeners or just refresh UI
          _startListening();
        },
        child: _patients.isEmpty
            ? ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(child: Text('No patients found. Tap + to add a patient.')),
          ],
        )
            : ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: _patients.length,
          itemBuilder: (context, index) {
            final p = _patients[index];
            return _buildPatientCard(p);
          },
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddPatientScreen()));
        },
        tooltip: 'Add new patient',
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
        if (item['notes'] != null && (recentNote == null || recentNote!.isEmpty)) {
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
        final dt = (item['datetime'] is int) ? item['datetime'] as int : int.tryParse(item['datetime']?.toString() ?? '');
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
      age: (m['age'] is int) ? (m['age'] as int) : (m['age'] != null ? int.tryParse(m['age'].toString()) : null),
      chemoTotal: total,
      chemoCompleted: completed,
      nextAppointmentDate: nextAppDate,
      recentNote: recentNote,
      patientUserUid: m['patientUserUid']?.toString(),
    );

  }
}

/* Placeholder Chat screen: replace with real chat implementation later */
class ChatPlaceholderScreen extends StatelessWidget {
  final String patientId;
  final String patientName;
  const ChatPlaceholderScreen({required this.patientId, required this.patientName, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat — $patientName')),
      body: const Center(child: Text('Chat feature not implemented yet.')),
    );
  }
}

/* Simple FollowUps screen that shows patients flagged with needsFollowUp */
class FollowUpsScreen extends StatelessWidget {
  FollowUpsScreen({super.key});
  final _db = FirebaseDatabase.instance;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // naive: read patients for this clinician and filter by needsFollowUp == true
    final Query q = _db.ref('patients').orderByChild('clinicianId').equalTo(user?.uid ?? '');

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-ups')),
      body: StreamBuilder<DatabaseEvent>(
        stream: q.onValue,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = snap.data!.snapshot;
          final List<Map<String, dynamic>> followList = [];
          if (s.value != null) {
            final map = Map<String, dynamic>.from(s.value as Map);
            map.forEach((k, v) {
              final m = Map<String, dynamic>.from(v as Map);
              if (m['needsFollowUp'] == true) followList.add({'id': m['id'] ?? k, 'name': m['name'] ?? 'Unnamed', 'note': m['followUpNote'] ?? ''});
            });
          }
          if (followList.isEmpty) return const Center(child: Text('No follow-ups at the moment.'));
          return ListView.separated(
            itemCount: followList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final it = followList[idx];
              return ListTile(
                title: Text(it['name'] ?? 'Unnamed'),
                subtitle: Text(it['note'] ?? ''),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PatientDetail(patientId: it['id'])));
                },
              );
            },
          );
        },
      ),
    );
  }
}
