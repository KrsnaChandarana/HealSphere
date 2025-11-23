import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'package:firebase_database/firebase_database.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance;
  User? _user;
  Map<dynamic, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_user == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    final snapshot = await _db.ref('users/${_user!.uid}').get();
    if (snapshot.exists) {
      setState(() {
        _profile = Map<dynamic, dynamic>.from(snapshot.value as Map);
        _loading = false;
      });
    } else {
      setState(() {
        _profile = null;
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final displayName = _profile?['name'] ?? _user?.email ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Heal Sphere'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome, $displayName', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('UID: ${_user?.uid ?? "n/a"}'),
            const SizedBox(height: 18),
            // Placeholder for role or navigation to dashboards
            Text('Role: ${_profile?['role'] ?? "not set"}'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Example: navigate to patient dashboard screen (to be implemented)
              },
              child: const Text('Go to Dashboard (placeholder)'),
            ),
          ],
        ),
      ),
    );
  }
}
