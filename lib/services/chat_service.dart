// lib/services/chat_service.dart
import 'package:firebase_database/firebase_database.dart';

class ChatService {
  ChatService._();
  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Get existing 1-1 chat between currentUid and peerUid,
  /// or create a new one if it doesn't exist.
  static Future<String> getOrCreateChat({
    required String currentUid,
    required String peerUid,
    String? currentName,
    String? peerName,
  }) async {
    // 1) Check if chat already exists in userChats/currentUid
    final userChatsRef = _db.ref('userChats/$currentUid');
    final snap = await userChatsRef.get();
    if (snap.value != null) {
      final map = Map<String, dynamic>.from(snap.value as Map);
      String? existingChatId;
      map.forEach((chatId, value) {
        final m = Map<String, dynamic>.from(value as Map);
        if (m['peerId']?.toString() == peerUid) {
          existingChatId = chatId;
        }
      });
      if (existingChatId != null) {
        return existingChatId!;
      }
    }

    // 2) Create new chat
    final chatRef = _db.ref('chats').push();
    final chatId = chatRef.key!;
    final now = ServerValue.timestamp;

    await chatRef.set({
      'id': chatId,
      'createdAt': now,
      'lastMessage': '',
      'lastTimestamp': now,
      'participants': {currentUid: true, peerUid: true},
    });

    // Create entries in userChats for both users
    await _db.ref('userChats/$currentUid/$chatId').set({
      'peerId': peerUid,
      'peerName': peerName ?? '',
      'lastMessage': '',
      'lastTimestamp': now,
    });

    await _db.ref('userChats/$peerUid/$chatId').set({
      'peerId': currentUid,
      'peerName': currentName ?? '',
      'lastMessage': '',
      'lastTimestamp': now,
    });

    return chatId;
  }

  /// Send a text message in a given chat
  static Future<void> sendMessage({
    required String chatId,
    required String senderUid,
    required String text,
  }) async {
    final messagesRef = _db.ref('chats/$chatId/messages').push();
    final msgId = messagesRef.key!;
    final now = ServerValue.timestamp;

    await messagesRef.set({
      'id': msgId,
      'senderId': senderUid,
      'text': text,
      'createdAt': now,
    });

    // Update chat summary
    final chatRef = _db.ref('chats/$chatId');
    await chatRef.update({
      'lastMessage': text,
      'lastTimestamp': now,
    });

    // Optionally: update userChats for all participants (basic version)
    final chatSnap = await chatRef.child('participants').get();
    if (chatSnap.value != null) {
      final participants = Map<String, dynamic>.from(chatSnap.value as Map);
      for (final uid in participants.keys) {
        await _db.ref('userChats/$uid/$chatId').update({
          'lastMessage': text,
          'lastTimestamp': now,
        });
      }
    }
  }
}
