
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum AppRole { patient, caregiver, clinician }

extension AppRoleExt on AppRole {
  String get name {
    switch (this) {
      case AppRole.patient:
        return 'Patient';
      case AppRole.caregiver:
        return 'Caregiver';
      case AppRole.clinician:
        return 'Clinician';
    }
  }

  String get key {
    return name.toLowerCase();
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  AppRole? _selectedRole = AppRole.patient;
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );

      final uid = cred.user!.uid;
      final dbRef = FirebaseDatabase.instance.ref('users/$uid');
      final snapshot = await dbRef.get();

      String storedRole = '';
      if (snapshot.exists) {
        final map = Map<String, dynamic>.from(snapshot.value as Map);
        storedRole = (map['role'] ?? '').toString();
      }

      // If storedRole is empty, treat as unknown
      if (storedRole.isEmpty) {
        // Offer to set role? For now, show message and navigate to home
        if (!mounted) return;
        await _showRoleMismatchDialog(
          title: 'Role not set',
          message:
          'Your account does not have a role assigned in database. You can set it from your profile later.',
          proceedLabel: 'Go to Home',
          onProceed: () {
            Navigator.of(context).pushReplacementNamed('/home');
          },
        );
      } else {
        final selected = _selectedRole?.key ?? '';
        if (selected == storedRole.toLowerCase()) {
          // match -> navigate to proper dashboard
          _routeToRole(storedRole.toLowerCase());
        } else {
          // mismatch -> inform user and let them choose: go to DB role or cancel
          if (!mounted) return;
          await _showRoleMismatchDialog(
            title: 'Role mismatch',
            message:
            'You selected "${_selectedRole?.name}" at login, but your account role in the database is "$storedRole".\n\nWhich dashboard would you like to open?',
            proceedLabel: 'Open ${storedRole[0].toUpperCase()}${storedRole.substring(1)} dashboard',
            onProceed: () {
              _routeToRole(storedRole.toLowerCase());
            },
            cancelLabel: 'Cancel',
            onCancel: () {
              // just stay on login screen
            },
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'Unknown error occurred';
      });
    } finally {
      if (mounted) {
        setState(() {
        _loading = false;
      });
      }
    }
  }

  Future<void> _showRoleMismatchDialog({
    required String title,
    required String message,
    required String proceedLabel,
    required VoidCallback onProceed,
    String cancelLabel = 'Use selected role',
    VoidCallback? onCancel,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (onCancel != null) onCancel();
              },
              child: Text(cancelLabel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onProceed();
              },
              child: Text(proceedLabel),
            ),
          ],
        );
      },
    );
  }

  void _routeToRole(String roleKey) {
    // route to role-specific dashboard
    switch (roleKey) {
      case 'patient':
        Navigator.of(context).pushReplacementNamed('/patient');
        break;
      case 'caregiver':
        Navigator.of(context).pushReplacementNamed('/caregiver');
        break;
      case 'clinician':
      case 'doctor':
        Navigator.of(context).pushReplacementNamed('/clinician');
        break;
      default:
        Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Widget _roleDropdown() {
    return DropdownButtonFormField<AppRole>(
      initialValue: _selectedRole,
      decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.person)),
      items: AppRole.values
          .map((r) => DropdownMenuItem<AppRole>(
        value: r,
        child: Text(r.name),
      ))
          .toList(),
      onChanged: (val) {
        setState(() {
          _selectedRole = val;
        });
      },
      validator: (v) => v == null ? 'Select role' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter email';
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Enter valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter password';
                        if (v.length < 6) return 'Password must be at least 6 chars';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _roleDropdown(),
                    const SizedBox(height: 16),
                    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                      },
                      child: const Text("Don't have an account? Register"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed('/awareness');
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('General Awareness'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Colors.deepPurpleAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
