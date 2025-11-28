import 'package:firebase_database/firebase_database.dart';

class ChatService {
  ChatService._();

  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Get existing 1-1 chat or create a new one using the canonical schema.
  static Future<String> getOrCreateChat({
    required String currentUid,
    required String peerUid,
  }) async {
    final existingChat = await _findExistingChatId(currentUid, peerUid);
    if (existingChat != null) return existingChat;

    final chatRef = _db.ref('chats').push();
    final chatId = chatRef.key;
    if (chatId == null || chatId.isEmpty) {
      throw Exception('Failed to create chat id');
    }

    final now = ServerValue.timestamp;
    final currentProfile = await _getUserProfile(currentUid);
    final peerProfile = await _getUserProfile(peerUid);

    await chatRef.set({
      'chatId': chatId,
      'participants': {currentUid: true, peerUid: true},
      'lastMessage': '',
      'lastUpdated': now,
    });

    final currentEntry = _buildUserChatEntry(
      chatId: chatId,
      otherUserId: peerUid,
      otherUserName: peerProfile['name'] ?? peerProfile['email'] ?? '',
      otherUserRole: peerProfile['role'] ?? '',
      lastMessage: '',
      lastUpdated: now,
    );
    final peerEntry = _buildUserChatEntry(
      chatId: chatId,
      otherUserId: currentUid,
      otherUserName: currentProfile['name'] ?? currentProfile['email'] ?? '',
      otherUserRole: currentProfile['role'] ?? '',
      lastMessage: '',
      lastUpdated: now,
    );

    await Future.wait([
      _db.ref('userChats/$currentUid/$chatId').set(currentEntry),
      _db.ref('userChats/$peerUid/$chatId').set(peerEntry),
    ]);

    return chatId;
  }

  /// Helper to create clinician ↔ patient chats.
  static Future<String> createClinicianPatientChat({
    required String clinicianUid,
    required String patientUid,
  }) =>
      getOrCreateChat(currentUid: clinicianUid, peerUid: patientUid);

  /// Helper to create clinician ↔ caregiver chats.
  static Future<String> createClinicianCaregiverChat({
    required String clinicianUid,
    required String caregiverUid,
  }) =>
      getOrCreateChat(currentUid: clinicianUid, peerUid: caregiverUid);

  /// Helper to create caregiver ↔ patient chats.
  static Future<String> createCaregiverPatientChat({
    required String caregiverUid,
    required String patientUid,
  }) =>
      getOrCreateChat(currentUid: caregiverUid, peerUid: patientUid);

  static Map<String, dynamic> _buildUserChatEntry({
    required String chatId,
    required String otherUserId,
    required String otherUserName,
    required String otherUserRole,
    required String lastMessage,
    required Object lastUpdated,
  }) {
    return {
      'chatId': chatId,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'otherUserRole': otherUserRole,
      'lastMessage': lastMessage,
      'lastUpdated': lastUpdated,
    };
  }

  static Future<String?> _findExistingChatId(String currentUid, String peerUid) async {
    final snapshot = await _db.ref('userChats/$currentUid').get();
    if (snapshot.value == null) return null;
    final map = Map<String, dynamic>.from(snapshot.value as Map);
    for (final entry in map.entries) {
      final value = Map<String, dynamic>.from(entry.value as Map);
      if (value['otherUserId']?.toString() == peerUid) {
        return entry.key;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>> _getUserProfile(String uid) async {
    final snapshot = await _db.ref('users/$uid').get();
    if (snapshot.value == null) {
      return {
        'uid': uid,
        'name': '',
        'role': '',
      };
    }
    final map = Map<String, dynamic>.from(snapshot.value as Map);
    map['uid'] ??= uid;
    return map;
  }

  /// Expose a stream of messages ordered by timestamp for chat builders.
  static Stream<DatabaseEvent> getMessagesStream(String chatId) {
    return _db
        .ref('chats/$chatId/messages')
        .orderByChild('timestamp')
        .onValue;
  }

  /// Send message and keep chat summaries in sync.
  static Future<void> sendMessage({
    required String chatId,
    required String senderUid,
    required String text,
    String type = 'text',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('Message cannot be empty');
    }

    final messageRef = _db.ref('chats/$chatId/messages').push();
    final messageId = messageRef.key;
    if (messageId == null || messageId.isEmpty) {
      throw Exception('Failed to create message id');
    }
    final now = ServerValue.timestamp;
    await messageRef.set({
      'messageId': messageId,
      'senderId': senderUid,
      'text': trimmed,
      'timestamp': now,
      'type': type,
    });

    final chatRef = _db.ref('chats/$chatId');
    await chatRef.update({
      'lastMessage': trimmed,
      'lastUpdated': now,
    });

    final participantsSnap = await chatRef.child('participants').get();
    if (participantsSnap.value == null) return;
    final participants = Map<String, dynamic>.from(participantsSnap.value as Map);
    await Future.wait(participants.keys.map((uid) {
      return _db.ref('userChats/$uid/$chatId').update({
        'lastMessage': trimmed,
        'lastUpdated': now,
      });
    }));
  }

  /// Expose chats per user (for inbox style UIs).
  static Stream<DatabaseEvent> getUserChats(String uid) {
    return _db.ref('userChats/$uid').orderByChild('lastUpdated').onValue;
  }

  /// Stream helper used by chat detail screens.
  static Stream<DatabaseEvent> messagesStream(String chatId) => getMessagesStream(chatId);
}
