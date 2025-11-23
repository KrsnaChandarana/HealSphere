import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/patient_dashboard.dart';
import 'screens/caregiver_dashboard.dart';
import 'screens/clinician_dashboard.dart';
import 'screens/general_awareness_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // If you used the FlutterFire CLI, firebase_options.dart will be generated.
  await Firebase.initializeApp(
    // If you used FlutterFire CLI: options: DefaultFirebaseOptions.currentPlatform
    // Otherwise it will auto-detect google-services.json on Android.
  );
  runApp(const HealSphereApp());
}

class HealSphereApp extends StatelessWidget {
  const HealSphereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Heal Sphere',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),
        '/patient': (_) => const PatientDashboard(),
        '/caregiver': (_) => const CaregiverDashboard(),
        '/clinician': (_) => const ClinicalDashboard(),
        '/awareness': (_) => const GeneralAwarenessScreen(),
      },
    );
  }
}
