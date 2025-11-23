// patient_detail.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class PatientDetail extends StatefulWidget {
  final String patientId;
  const PatientDetail({required this.patientId, super.key});

  @override
  State<PatientDetail> createState() => _PatientDetailState();
}

class _PatientDetailState extends State<PatientDetail> {
  final _db = FirebaseDatabase.instance;
  bool _loading = true;
  Map<String, dynamic>? _patient;
  Stream<DatabaseEvent>? _patientStream;

  @override
  void initState() {
    super.initState();
    _listenPatient();
  }

  void _listenPatient() {
    final ref = _db.ref('patients/${widget.patientId}');
    _patientStream = ref.onValue;
    _patientStream!.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          _patient = Map<String, dynamic>.from(event.snapshot.value as Map);
          _loading = false;
        });
      } else {
        setState(() {
          _patient = null;
          _loading = false;
        });
      }
    });
  }

  Future<void> _addChemoEntry() async {
    final notesCtrl = TextEditingController();
    DateTime? date;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add Chemo entry'),
          content: StatefulBuilder(builder: (c, setState) {
            return SizedBox(
              width: 300,
              child: Form(
                key: formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (picked != null) setState(() => date = picked);
                    },
                    child: Text(date == null ? 'Pick date' : 'Date: ${date!.toLocal().toString().split(' ')[0]}'),
                  ),
                ]),
              ),
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                // save
                final ref = _db.ref('patients/${widget.patientId}/chemoHistory').push();
                final id = ref.key ?? '';
                await ref.set({
                  'id': id,
                  'date': date != null ? date!.millisecondsSinceEpoch : DateTime.now().millisecondsSinceEpoch,
                  'completed': true,
                  'notes': notesCtrl.text.trim(),
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            )
          ],
        );
      },
    );
  }

  Future<void> _makeAppointment() async {
    final notesCtrl = TextEditingController();
    DateTime? date;
    TimeOfDay? time;
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Make Appointment'),
          content: StatefulBuilder(builder: (c, setState) {
            return SizedBox(
              width: 320,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes')),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                    if (picked != null) setState(() => date = picked);
                  },
                  child: Text(date == null ? 'Pick date' : 'Date: ${date!.toLocal().toString().split(' ')[0]}'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (picked != null) setState(() => time = picked);
                  },
                  child: Text(time == null ? 'Pick time' : 'Time: ${time!.format(context)}'),
                ),
              ]),
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (date == null || time == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick date and time')));
                  return;
                }
                final dt = DateTime(date!.year, date!.month, date!.day, time!.hour, time!.minute);
                final ref = _db.ref('patients/${widget.patientId}/appointments').push();
                final id = ref.key ?? '';
                await ref.set({
                  'id': id,
                  'datetime': dt.millisecondsSinceEpoch,
                  'notes': notesCtrl.text.trim(),
                  'status': 'scheduled'
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Create'),
            )
          ],
        );
      },
    );
  }

  Future<void> _assignCaregiver() async {
    // route to register caregiver page or show a simple form inline
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    await showDialog(
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
                  'linkedPatientId': widget.patientId,
                  'createdAt': ServerValue.timestamp
                });
                // update patient
                await _db.ref('patients/${widget.patientId}').update({'caregiverId': id, 'updatedAt': ServerValue.timestamp});
                Navigator.of(ctx).pop();
              },
              child: const Text('Register'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_patient == null) return const Scaffold(body: Center(child: Text('Patient not found')));

    final chemoMap = _patient!['chemoHistory'] != null ? Map<String, dynamic>.from(_patient!['chemoHistory'] as Map) : {};
    final chemoList = chemoMap.entries.map((e) {
      final m = Map<String, dynamic>.from(e.value as Map);
      return m;
    }).toList()
      ..sort((a, b) => (b['date'] ?? 0).compareTo(a['date'] ?? 0));

    final appointmentsMap = _patient!['appointments'] != null ? Map<String, dynamic>.from(_patient!['appointments'] as Map) : {};
    final appointmentsList = appointmentsMap.entries.map((e) => Map<String, dynamic>.from(e.value as Map)).toList()
      ..sort((a, b) => (a['datetime'] ?? 0).compareTo(b['datetime'] ?? 0));

    return Scaffold(
      appBar: AppBar(title: Text(_patient!['name'] ?? 'Patient')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((_patient!['name'] ?? ''), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Age: ${_patient!['age'] ?? 'N/A'} • Gender: ${_patient!['gender'] ?? 'N/A'}'),
          const SizedBox(height: 8),
          Text('Diagnosis: ${_patient!['diagnosis'] ?? 'Not set'}'),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(onPressed: _addChemoEntry, icon: const Icon(Icons.local_hospital), label: const Text('Add Chemo')),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: _makeAppointment, icon: const Icon(Icons.calendar_today), label: const Text('Make Appointment')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _assignCaregiver, icon: const Icon(Icons.person_add), label: const Text('Assign Caregiver')),
          ]),
          const SizedBox(height: 18),
          const Text('Chemo History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          chemoList.isEmpty
              ? const Text('No chemo history')
              : Column(
            children: chemoList.map((m) {
              final dt = DateTime.fromMillisecondsSinceEpoch((m['date'] ?? 0) as int);
              return Card(
                child: ListTile(
                  title: Text('Date: ${dt.toLocal().toString().split(' ')[0]}'),
                  subtitle: Text(m['notes'] ?? ''),
                  trailing: Icon(m['completed'] == true ? Icons.check_circle : Icons.pending, color: m['completed'] == true ? Colors.green : Colors.orange),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text('Appointments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          appointmentsList.isEmpty
              ? const Text('No appointments')
              : Column(children: appointmentsList.map((a) {
            final dt = DateTime.fromMillisecondsSinceEpoch((a['datetime'] ?? 0) as int);
            return Card(
              child: ListTile(
                title: Text('${dt.toLocal()}'),
                subtitle: Text(a['notes'] ?? ''),
                trailing: Text(a['status'] ?? ''),
              ),
            );
          }).toList())
        ]),
      ),
    );
  }
}
