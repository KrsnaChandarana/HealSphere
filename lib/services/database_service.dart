// // lib/services/database_service.dart
// import 'package:firebase_database/firebase_database.dart';
//
// class DatabaseService {
//   DatabaseService._();
//
//   static final FirebaseDatabase _db = FirebaseDatabase.instance;
//
//   /// Create a follow-up request under:
//   /// /followUps/{clinicianId}/{followUpId}
//   static Future<String?> createFollowUp({
//     required String clinicianId,
//     required String patientId,
//     required String patientName,
//     required String note,
//     required String createdBy,
//   }) async {
//     try {
//       final ref = _db.ref('followUps/$clinicianId').push();
//       final id = ref.key!;
//       await ref.set({
//         'id': id,
//         'patientId': patientId,
//         'patientName': patientName,
//         'note': note,
//         'createdBy': createdBy,
//         'status': 'open',
//         'createdAt': ServerValue.timestamp,
//         'updatedAt': ServerValue.timestamp,
//       });
//
//       // Also flag the patient node (optional, but nice)
//       await _db.ref('patients/$patientId').update({
//         'needsFollowUp': true,
//         'followUpNote': note,
//         'followUpRequestedAt': ServerValue.timestamp,
//       });
//
//       return id;
//     } catch (_) {
//       return null;
//     }
//   }
//
//   /// Add / overwrite a daily log so it looks like:
//   /// "dailyLogs": {
//   ///   "log_20240101": { ... }
//   /// }
//   static Future<String?> addDailyLog({
//     required String patientId,
//     required int date,          // millis at midnight (you already pass this from PatientDashboard)
//     required String eating,
//     required int sleepHours,
//     required String feeling,
//     required List<String> activities,
//   }) async {
//     try {
//       // Build key like "log_20240101"
//       final dt = DateTime.fromMillisecondsSinceEpoch(date);
//       final y = dt.year.toString().padLeft(4, '0');
//       final m = dt.month.toString().padLeft(2, '0');
//       final d = dt.day.toString().padLeft(2, '0');
//       final logId = 'log_${y}${m}${d}';
//
//       final ref = _db.ref('patients/$patientId/dailyLogs/$logId');
//
//       await ref.set({
//         'id': logId,
//         'date': date,
//         'eating': eating,
//         'sleepHours': sleepHours,
//         'feeling': feeling,
//         'activities': activities,
//       });
//
//       return logId;
//     } catch (e) {
//       return null;
//     }
//   }
//
//
//   /// Add a high-level activity:
//   /// "activities": {
//   ///   "act_1704067200000": { ... }
//   /// }
//   static Future<String?> addActivity({
//     required String patientId,
//     required int date,          // millis at midnight or exact time
//     required String description,
//     required String createdBy,  // uid of patient or caregiver
//   }) async {
//     try {
//       final actId = 'act_$date'; // simple deterministic id
//       final ref = _db.ref('patients/$patientId/activities/$actId');
//       await ref.set({
//         'id': actId,
//         'description': description,
//         'date': date,
//         'createdBy': createdBy,
//       });
//       return actId;
//     } catch (_) {
//       return null;
//     }
//   }
// }


import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

/// Centralized service for Firebase Realtime Database operations.
class DatabaseService {
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ==================== USERS ====================

  /// Stream a single user profile (used for role-based routing).
  static Stream<Map<String, dynamic>?> userProfileStream(String uid) {
    return _db.ref('users/$uid').onValue.map((event) {
      if (event.snapshot.value == null) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  /// Fetch a user profile once.
  static Future<Map<String, dynamic>?> getUser(String uid) async {
    try {
      final snapshot = await _db.ref('users/$uid').get();
      if (snapshot.value == null) return null;
      return Map<String, dynamic>.from(snapshot.value as Map);
    } catch (_) {
      return null;
    }
  }

  // ==================== PATIENTS ====================

  /// Get patient by ID
  static Future<Map<String, dynamic>?> getPatient(String patientId) async {
    try {
      final snapshot = await _db.ref('patients/$patientId').get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Listen to a patient record in real-time.
  static Stream<Map<String, dynamic>?> patientStream(String patientId) {
    return _db.ref('patients/$patientId').onValue.map((event) {
      if (event.snapshot.value == null) return null;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      data['id'] ??= patientId;
      return data;
    });
  }

  /// Listen to a patient record using the linked patient user uid.
  static Stream<Map<String, dynamic>?> patientByUserUidStream(String userUid) {
    final query = _db
        .ref('patients')
        .orderByChild('patientUserUid')
        .equalTo(userUid);

    return query.onValue.map((event) {
      if (event.snapshot.value == null) return null;
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      if (map.isEmpty) return null;
      final entry = map.entries.first;
      final data = Map<String, dynamic>.from(entry.value as Map);
      data['id'] ??= entry.key;
      return data;
    });
  }

  /// Get patients for a clinician
  static Stream<DatabaseEvent> getPatientsForClinician(String clinicianId) {
    return _db.ref('patients')
        .orderByChild('clinicianId')
        .equalTo(clinicianId)
        .onValue;
  }

  /// Create patient (clinician only)
  static Future<String?> createPatient({
    required String clinicianId,
    required String name,
    int? age,
    String? gender,
    String? diagnosis,
    String? conditionSummary,
    String? photoUrl,
  }) async {
    try {
      final ref = _db.ref('patients').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'name': name,
        'age': age,
        'gender': gender ?? 'Other',
        'diagnosis': diagnosis ?? '',
        'conditionSummary': conditionSummary ?? '',
        'photoUrl': photoUrl ?? '',
        'clinicianId': clinicianId,
        'needsFollowUp': false,
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      return id;
    } catch (e) {
      return null;
    }
  }

  /// Update patient
  static Future<bool> updatePatient({
    required String patientId,
    Map<String, dynamic>? updates,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': ServerValue.timestamp,
      };
      if (updates != null) {
        updateData.addAll(updates);
      }
      await _db.ref('patients/$patientId').update(updateData);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Link patient ↔ caregiver ↔ clinician metadata in one call.
  static Future<bool> linkCareTeam({
    required String patientId,
    String? patientUserUid,
    String? clinicianUid,
    String? caregiverUid,
    String? caregiverRecordId,
  }) async {
    try {
      final patientUpdates = <String, dynamic>{
        'updatedAt': ServerValue.timestamp,
      };
      if (patientUserUid != null && patientUserUid.isNotEmpty) {
        patientUpdates['patientUserUid'] = patientUserUid;
      }
      if (clinicianUid != null && clinicianUid.isNotEmpty) {
        patientUpdates['clinicianId'] = clinicianUid;
      }
      if (caregiverRecordId != null && caregiverRecordId.isNotEmpty) {
        patientUpdates['caregiverId'] = caregiverRecordId;
      }
      if (caregiverUid != null && caregiverUid.isNotEmpty) {
        patientUpdates['caregiverUserUid'] = caregiverUid;
      }

      await _db.ref('patients/$patientId').update(patientUpdates);

      final List<Future<void>> linkOps = [];
      if (patientUserUid != null && patientUserUid.isNotEmpty) {
        linkOps.add(
          _db.ref('users/$patientUserUid').update({
            'linkedPatientId': patientId,
            'updatedAt': ServerValue.timestamp,
          }),
        );
      }
      if (caregiverUid != null && caregiverUid.isNotEmpty) {
        linkOps.add(
          _db.ref('users/$caregiverUid').update({
            'linkedPatientId': patientId,
            'updatedAt': ServerValue.timestamp,
          }),
        );
      }
      if (caregiverRecordId != null && caregiverRecordId.isNotEmpty) {
        linkOps.add(
          _db.ref('caregivers/$caregiverRecordId').update({
            'linkedPatientId': patientId,
            'updatedAt': ServerValue.timestamp,
          }),
        );
      }
      await Future.wait(linkOps);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add chemo entry
  static Future<String?> addChemoEntry({
    required String patientId,
    required int date,
    bool completed = false,
    String? remarks,
    String? notes,
  }) async {
    try {
      final ref = _db.ref('patients/$patientId/chemoHistory').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'date': date,
        'completed': completed,
        'remarks': remarks ?? '',
        'notes': notes ?? '',
      });

      return id;
    } catch (e) {
      return null;
    }
  }

  /// Update chemo entry.
  static Future<bool> updateChemoEntry({
    required String patientId,
    required String chemoId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _db.ref('patients/$patientId/chemoHistory/$chemoId').update(updates);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete chemo entry.
  static Future<bool> deleteChemoEntry({
    required String patientId,
    required String chemoId,
  }) async {
    try {
      await _db.ref('patients/$patientId/chemoHistory/$chemoId').remove();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add appointment
  static Future<String?> addAppointment({
    required String patientId,
    required int datetime,
    String? notes,
    String status = 'scheduled',
  }) async {
    try {
      final ref = _db.ref('patients/$patientId/appointments').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'datetime': datetime,
        'notes': notes ?? '',
        'status': status,
        'createdAt': ServerValue.timestamp,
      });

      return id;
    } catch (e) {
      return null;
    }
  }

  /// Update appointment details.
  static Future<bool> updateAppointment({
    required String patientId,
    required String appointmentId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _db.ref('patients/$patientId/appointments/$appointmentId').update(updates);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete an appointment.
  static Future<bool> deleteAppointment({
    required String patientId,
    required String appointmentId,
  }) async {
    try {
      await _db.ref('patients/$patientId/appointments/$appointmentId').remove();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Add daily log
  static Future<String?> addDailyLog({
    required String patientId,
    required int date,          // millis at midnight (you already pass this from PatientDashboard)
    required String eating,
    required int sleepHours,
    required String feeling,
    required List<String> activities,
  }) async {
    try {
      // Build key like "log_20240101"
      final dt = DateTime.fromMillisecondsSinceEpoch(date);
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final logId = 'log_${y}${m}${d}';

      final ref = _db.ref('patients/$patientId/dailyLogs/$logId');

      await ref.set({
        'id': logId,
        'date': date,
        'eating': eating,
        'sleepHours': sleepHours,
        'feeling': feeling,
        'activities': activities,
      });

      return logId;
    } catch (e) {
      return null;
    }
  }


  /// Update a daily log entry.
  static Future<bool> updateDailyLog({
    required String patientId,
    required String logId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _db.ref('patients/$patientId/dailyLogs/$logId').update(updates);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete a daily log entry.
  static Future<bool> deleteDailyLog({
    required String patientId,
    required String logId,
  }) async {
    try {
      await _db.ref('patients/$patientId/dailyLogs/$logId').remove();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Request follow-up
  static Future<bool> requestFollowUp({
    required String patientId,
    required String note,
  }) async {
    try {
      await _db.ref('patients/$patientId').update({
        'needsFollowUp': true,
        'followUpNote': note,
        'followUpRequestedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear follow-up flag
  static Future<bool> clearFollowUp(String patientId) async {
    try {
      await _db.ref('patients/$patientId').update({
        'needsFollowUp': false,
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== CAREGIVERS ====================

  /// Create caregiver (clinician only)
  static Future<String?> createCaregiver({
    required String name,
    required String phone,
    String? email,
    String? linkedPatientId,
  }) async {
    try {
      final ref = _db.ref('caregivers').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'name': name,
        'phone': phone,
        'email': email ?? '',
        'linkedPatientId': linkedPatientId ?? '',
        'createdAt': ServerValue.timestamp,
        'updatedAt': ServerValue.timestamp,
      });

      if (linkedPatientId != null) {
        await _db.ref('patients/$linkedPatientId').update({
          'caregiverId': id,
          'updatedAt': ServerValue.timestamp,
        });
      }

      return id;
    } catch (e) {
      return null;
    }
  }

  /// Get caregiver by ID
  static Future<Map<String, dynamic>?> getCaregiver(String caregiverId) async {
    try {
      final snapshot = await _db.ref('caregivers/$caregiverId').get();
      if (snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ==================== AWARENESS ====================

  /// Get awareness carousel items
  static Stream<DatabaseEvent> getAwarenessCarousel() {
    return _db.ref('awareness/carousel').onValue;
  }

  /// Get awareness education items
  static Stream<DatabaseEvent> getAwarenessEducation() {
    return _db.ref('awareness/education').onValue;
  }

  /// Get awareness feed items
  static Stream<DatabaseEvent> getAwarenessFeed() {
    return _db.ref('awareness/feed').onValue;
  }

  // ==================== BOOKMARKS ====================

  /// Add bookmark
  static Future<bool> addBookmark({
    required String uid,
    required String itemId,
    required String title,
    required String link,
    String? type,
  }) async {
    try {
      await _db.ref('bookmarks/$uid/$itemId').set({
        'savedAt': ServerValue.timestamp,
        'title': title,
        'link': link,
        'type': type ?? 'news',
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove bookmark
  static Future<bool> removeBookmark({
    required String uid,
    required String itemId,
  }) async {
    try {
      await _db.ref('bookmarks/$uid/$itemId').remove();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get user bookmarks
  static Stream<DatabaseEvent> getUserBookmarks(String uid) {
    return _db.ref('bookmarks/$uid').onValue;
  }

  // ==================== ACTIVITIES ====================

  /// Add activity log
  static Future<String?> addActivity({
    required String patientId,
    required String description,
    required int date,
    required String createdBy,
  }) async {
    try {
      final ref = _db.ref('patients/$patientId/activities').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'description': description,
        'date': date,
        'createdBy': createdBy,
      });

      return id;
    } catch (e) {
      return null;
    }
  }

  // ==================== FOLLOW-UPS ====================

  /// Create follow-up request
  static Future<String?> createFollowUp({
    required String clinicianId,
    required String patientId,
    required String patientName,
    required String note,
    required String createdBy,
  }) async {
    try {
      final ref = _db.ref('followUps/$clinicianId').push();
      final id = ref.key ?? '';

      await ref.set({
        'id': id,
        'patientId': patientId,
        'patientName': patientName,
        'note': note,
        'requestedAt': ServerValue.timestamp,
        'status': 'pending',
        'createdBy': createdBy,
      });

      // Also update patient record
      await _db.ref('patients/$patientId').update({
        'needsFollowUp': true,
        'followUpNote': note,
        'followUpRequestedAt': ServerValue.timestamp,
      });

      return id;
    } catch (e) {
      return null;
    }
  }

  /// Get follow-ups for clinician
  static Stream<DatabaseEvent> getFollowUpsForClinician(String clinicianId) {
    return _db.ref('followUps/$clinicianId')
        .orderByChild('requestedAt')
        .onValue;
  }

  /// Update follow-up status
  static Future<bool> updateFollowUpStatus({
    required String clinicianId,
    required String followUpId,
    required String status,
  }) async {
    try {
      await _db.ref('followUps/$clinicianId/$followUpId').update({
        'status': status,
        'updatedAt': ServerValue.timestamp,
      });
      return true;
    } catch (e) {
      return false;
    }
  }


  // ==================== UTILITIES ====================

  /// Get reference to a path
  static DatabaseReference ref(String path) {
    return _db.ref(path);
  }

  /// Get stream for a path
  static Stream<DatabaseEvent> stream(String path) {
    return _db.ref(path).onValue;
  }
}

