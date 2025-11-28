import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseDatabase _db = FirebaseDatabase.instance;
  static const List<String> _allowedRoles = ['patient', 'caregiver', 'clinician'];

  /// Sign in with email & password
  static Future<User?> signInWithEmail(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return userCredential.user;
  }

  /// Register a user with profile
  static Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String name,
    required String role,
    String? phone,
  }) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    
    final user = userCredential.user;
    if (user != null) {
      final normalizedRole = _normalizeRole(role);
      // Create user profile in database
      await _db.ref('users/${user.uid}').set({
        'uid': user.uid,
        'name': name,
        'email': email,
        'role': normalizedRole,
        'phone': phone ?? '',
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });
    }
    
    return user;
  }

  /// Get user role from database
  static Future<String?> getUserRole(String uid) async {
    try {
      final snapshot = await _db.ref('users/$uid/role').get();
      final role = snapshot.value?.toString();
      return role?.toLowerCase();
    } catch (e) {
      return null;
    }
  }

  /// Get user profile
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final snapshot = await _db.ref('users/$uid').get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update user profile
  static Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? phone,
    String? photoUrl,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': ServerValue.timestamp,
    };
    
    if (name != null) updates['name'] = name;
    if (phone != null) updates['phone'] = phone;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    
    await _db.ref('users/$uid').update(updates);
  }

  /// Link patient to user account
  static Future<void> linkPatientToUser({
    required String userId,
    required String patientId,
  }) async {
    await _db.ref('users/$userId').update({
      'linkedPatientId': patientId,
      'updatedAt': ServerValue.timestamp,
    });
    await _db.ref('patients/$patientId').update({
      'patientUserUid': userId,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Link caregiver to user account
  static Future<void> linkCaregiverToUser({
    required String userId,
    required String caregiverId,
    String? patientId,
  }) async {
    await _db.ref('users/$userId').update({
      'linkedPatientId': patientId ?? '',
      'updatedAt': ServerValue.timestamp,
    });
    if (patientId != null) {
      await _db.ref('caregivers/$caregiverId').update({
        'uid': userId,
        'updatedAt': ServerValue.timestamp,
      });
      await _db.ref('patients/$patientId').update({
        'caregiverUserUid': userId,
        'updatedAt': ServerValue.timestamp,
      });
    }
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static User? currentUser() => _auth.currentUser;

  /// Stream of auth state changes
  static Stream<User?> authStateChanges() => _auth.authStateChanges();

  static String _normalizeRole(String? role) {
    final normalized = role?.toLowerCase() ?? '';
    if (_allowedRoles.contains(normalized)) return normalized;
    return _allowedRoles.first;
  }
}