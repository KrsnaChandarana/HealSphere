import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'general_awareness_screen.dart';
import 'patient_dashboard.dart';
import 'caregiver_dashboard.dart';
import 'clinician_dashboard.dart';

/// Wrapper widget that reacts to auth + role changes and surfaces the right UI.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;
        if (user == null) {
          return const GeneralAwarenessScreen(showAuthCtas: true);
        }

        return StreamBuilder<Map<String, dynamic>?>(
          stream: DatabaseService.userProfileStream(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final profile = profileSnapshot.data;
            final role = profile?['role']?.toString().toLowerCase() ?? '';
            switch (role) {
              case 'patient':
                return const PatientDashboard();
              case 'caregiver':
                return const CaregiverDashboard();
              case 'clinician':
              case 'doctor':
                return const ClinicalDashboard();
              default:
                return _UnknownRoleScreen(role: role, email: user.email);
            }
          },
        );
      },
    );
  }
}

class _UnknownRoleScreen extends StatelessWidget {
  const _UnknownRoleScreen({required this.role, required this.email});

  final String role;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heal Sphere'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService.signOut();
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'We could not determine your dashboard${role.isNotEmpty ? ' for role "$role"' : ''}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Account: ${email ?? 'Unknown email'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/awareness'),
                child: const Text('Back to Awareness'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
