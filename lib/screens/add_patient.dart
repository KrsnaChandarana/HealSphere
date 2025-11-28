import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

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
  final _conditionSummaryController = TextEditingController();
  final _patientUserUidController = TextEditingController(); // NEW

  String _gender = 'Female';

  bool _loading = false;
  String? _errorText;

  final _auth = FirebaseAuth.instance;

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

      // Check role
      final role = await AuthService.getUserRole(user.uid);
      if (role == null ||
          (role.toLowerCase() != 'clinician' &&
              role.toLowerCase() != 'doctor')) {
        throw Exception(
            'Only clinicians can add patients. Current role: $role');
      }

      final int? age = _ageController.text.trim().isEmpty
          ? null
          : int.tryParse(_ageController.text.trim());

      // 1) Create patient record
      final patientId = await DatabaseService.createPatient(
        clinicianId: user.uid,
        name: _nameController.text.trim(),
        age: age,
        gender: _gender,
        diagnosis: _diagnosisController.text.trim(),
        conditionSummary: _conditionSummaryController.text.trim(),
      );

      if (patientId == null) {
        throw Exception('Failed to create patient');
      }

      // 2) Optionally link to a patient user account (for chat + dashboard)
      final patientUserUid = _patientUserUidController.text.trim();
      if (patientUserUid.isNotEmpty) {
        final patientUser = await DatabaseService.getUser(patientUserUid);
        if (patientUser == null) {
          throw Exception(
              'Patient created, but no user found with UID: $patientUserUid');
        }

        // This will set:
        //  - patients/<patientId>/patientUserUid
        //  - users/<patientUserUid>/linkedPatientId
        //  - patients/<patientId>/clinicianId (already set, but harmless)
        final ok = await DatabaseService.linkCareTeam(
          patientId: patientId,
          patientUserUid: patientUserUid,
          clinicianUid: user.uid,
        );

        if (!ok) {
          throw Exception(
              'Patient created, but linking to user account failed.');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient added successfully')),
      );
      Navigator.of(context).pop();
    } catch (e) {
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
    _conditionSummaryController.dispose();
    _patientUserUidController.dispose(); // NEW
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conditionSummaryController,
                  decoration: const InputDecoration(
                    labelText: 'Condition Summary (optional)',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // NEW: optional link to a patient user account
                TextFormField(
                  controller: _patientUserUidController,
                  decoration: const InputDecoration(
                    labelText: 'Patient user UID (optional)',
                    prefixIcon: Icon(Icons.account_circle),
                    helperText:
                    'Link to an existing patient login account so they can use the app and chat.',
                  ),
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
