// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _logoAnimation;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 3500), // ⏳ smoother
      vsync: this,
    );

    _opacityAnimation =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.1, 0.5, curve: Curves.easeOut),
        ));

    _logoAnimation =
        Tween<double>(begin: 0.7, end: 1.2).animate(CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
        ));

    _controller.forward();

    Timer(const Duration(milliseconds: 3800), checkLogin);
  }

  Future<void> checkLogin() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
      return;
    }

    final role = await AuthService.getUserRole(user.uid);

    if (!mounted) return;
    switch (role?.toLowerCase()) {
      case 'patient':
        Navigator.pushReplacementNamed(context, '/patient');
        break;
      case 'caregiver':
        Navigator.pushReplacementNamed(context, '/caregiver');
        break;
      case 'clinician':
      case 'doctor':
        Navigator.pushReplacementNamed(context, '/clinician');
        break;
      default:
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 1600),
        color: Colors.deepPurple.shade400,
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoAnimation,
              child: Image.asset(
                'assets/images/heal_sphere_logo.png',
                width: size.width * 0.45,  // ⏫ bigger
              ),
            ),
            const SizedBox(height: 32),
            FadeTransition(
              opacity: _opacityAnimation,
              child: Column(
                children: [
                  Text(
                    "HealSphere",
                    style: TextStyle(
                      fontSize: 38, // ⏫ bigger title
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Inclusive Care • Endless Hope",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  Text(
                    "One Healing Circle",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
