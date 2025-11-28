// lib/screens/chat_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String peerUid;
  final String peerName;

  const ChatScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _msgCtrl = TextEditingController();
  String? _chatId;
  StreamSubscription<DatabaseEvent>? _msgSub;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in';
      });
      return;
    }

    try {
      final chatId = await ChatService.getOrCreateChat(
        currentUid: user.uid,
        peerUid: widget.peerUid,
      );

      if (!mounted) return;

      setState(() {
        _chatId = chatId;
        _loading = false;
      });

      _listenMessages(chatId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to open chat: $e';
      });
    }
  }



  void _listenMessages(String chatId) {
    _msgSub?.cancel();
    _msgSub = ChatService.getMessagesStream(chatId).listen((event) {
      final snap = event.snapshot;
      final List<Map<String, dynamic>> tmp = [];
      if (snap.value != null) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        map.forEach((key, value) {
          tmp.add(Map<String, dynamic>.from(value as Map));
        });
        tmp.sort((a, b) {
          final aT = a['timestamp'];
          final bT = b['timestamp'];
          final aMillis = aT is int ? aT : int.tryParse(aT?.toString() ?? '');
          final bMillis = bT is int ? bT : int.tryParse(bT?.toString() ?? '');
          return (aMillis ?? 0).compareTo(bMillis ?? 0);
        });
      }
      if (!mounted) return;
      setState(() {
        _messages = tmp;
        _loading = false; // make sure spinner is hidden once we got a response
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading messages: $e';
      });
    });
  }


  @override
  void dispose() {
    _msgCtrl.dispose();
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    final user = _auth.currentUser;
    if (user == null || _chatId == null) return;
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    _msgCtrl.clear();
    try {
      await ChatService.sendMessage(
        chatId: _chatId!,
        senderUid: user.uid,
        text: text,
      );
    } catch (_) {
      setState(() {
        _error = 'Failed to send message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.peerName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('No messages yet. Say hi!'))
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isMe = m['senderId'] == user?.uid;
                final text = m['text']?.toString() ?? '';
                final Color bubbleTextColor = isMe ? Colors.white : Colors.black87;
                final tsValue = m['timestamp'];
                DateTime? sentAt;
                if (tsValue is int) {
                  sentAt = DateTime.fromMillisecondsSinceEpoch(tsValue);
                } else if (tsValue is double) {
                  sentAt = DateTime.fromMillisecondsSinceEpoch(tsValue.toInt());
                }
                final timeLabel = sentAt != null
                    ? TimeOfDay.fromDateTime(sentAt.toLocal()).format(context)
                    : null;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blueAccent : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          style: TextStyle(
                            color: bubbleTextColor,
                          ),
                        ),
                        if (timeLabel != null)
                          Text(
                            timeLabel,
                            style: TextStyle(
                              color: bubbleTextColor.withValues(alpha: 0.7),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: const Border(top: BorderSide(color: Colors.grey)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
