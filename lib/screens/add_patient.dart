import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _diagnosisController = TextEditingController();
  String _gender = 'Female';

  bool _loading = false;
  String? _errorText;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User is not logged in');
      }

      // Check role from /users/<uid>/role
      final roleSnap = await _db.ref('users/${user.uid}/role').get();
      final role = roleSnap.value?.toString() ?? '';
      if (role.toLowerCase() != 'clinician' && role.toLowerCase() != 'doctor') {
        throw Exception('Only clinicians can add patients. Current role: $role');
      }

      final patientsRef = _db.ref('patients');
      final newRef = patientsRef.push();
      final id = newRef.key ?? '';

      final int? age = _ageController.text.trim().isEmpty
          ? null
          : int.tryParse(_ageController.text.trim());

      final data = <String, dynamic>{
        'id': id,
        'name': _nameController.text.trim(),
        'age': age,
        'gender': _gender,
        'diagnosis': _diagnosisController.text.trim(),
        'clinicianId': user.uid,
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
        'needsFollowUp': false,
      };

      await newRef.set(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      // SHOW the actual error on screen
      setState(() {
        _errorText = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _diagnosisController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Patient')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Patient name',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter patient name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ageController,
                  decoration: const InputDecoration(
                    labelText: 'Age (optional)',
                    prefixIcon: Icon(Icons.cake),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    prefixIcon: Icon(Icons.wc),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    setState(() => _gender = val ?? 'Female');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _diagnosisController,
                  decoration: const InputDecoration(
                    labelText: 'Diagnosis',
                    prefixIcon: Icon(Icons.local_hospital),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Add Patient'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
