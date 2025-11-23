// register_caregiver.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class RegisterCaregiverScreen extends StatefulWidget {
  final String patientId;
  const RegisterCaregiverScreen({required this.patientId, super.key});

  @override
  State<RegisterCaregiverScreen> createState() => _RegisterCaregiverScreenState();
}

class _RegisterCaregiverScreenState extends State<RegisterCaregiverScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = false;
  final _db = FirebaseDatabase.instance;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final ref = _db.ref('caregivers').push();
    final id = ref.key ?? '';
    await ref.set({
      'id': id,
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'linkedPatientId': widget.patientId,
      'createdAt': ServerValue.timestamp
    });
    await _db.ref('patients/${widget.patientId}').update({'caregiverId': id, 'updatedAt': ServerValue.timestamp});
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caregiver registered')));
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Caregiver')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _loading ? null : _create, child: _loading ? const CircularProgressIndicator() : const Text('Create'))
        ]),
      ),
    );
  }
}
