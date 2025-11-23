import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class GeneralAwarenessScreen extends StatefulWidget {
  const GeneralAwarenessScreen({super.key});
  @override
  State<GeneralAwarenessScreen> createState() => _GeneralAwarenessScreenState();
}

class _GeneralAwarenessScreenState extends State<GeneralAwarenessScreen> {
  final _db = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;

  // local caches
  List<NewsItem> carouselItems = [];
  List<EducationItem> educationItems = [];
  List<NewsItem> feedItems = [];
  Set<String> bookmarks = {};

  // subscriptions
  StreamSubscription<DatabaseEvent>? _carouselSub;
  StreamSubscription<DatabaseEvent>? _educationSub;
  StreamSubscription<DatabaseEvent>? _feedSub;
  StreamSubscription<DatabaseEvent>? _bookmarkSub;

  final PageController _pageController = PageController(viewportFraction: 0.88);

  @override
  void initState() {
    super.initState();
    _attachListeners();
    _listenBookmarksIfSignedIn();
    _auth.authStateChanges().listen((user) {
      // when auth state changes, re-listen bookmarks
      _listenBookmarksIfSignedIn();
    });
  }

  void _attachListeners() {
    // carousel
    _carouselSub = _db.ref('awareness/carousel').onValue.listen((evt) {
      final s = evt.snapshot;
      final List<NewsItem> tmp = [];
      if (s.value != null) {
        final map = Map.from(s.value as Map);
        map.forEach((k, v) {
          final m = Map<String, dynamic>.from(v as Map);
          tmp.add(NewsItem.fromMap(m, key: k));
        });
      }
      tmp.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      setState(() => carouselItems = tmp);
    }, onError: (e) {
      // ignore for now
    });

    // education
    _educationSub = _db.ref('awareness/education').onValue.listen((evt) {
      final s = evt.snapshot;
      final List<EducationItem> tmp = [];
      if (s.value != null) {
        final map = Map.from(s.value as Map);
        map.forEach((k, v) {
          final m = Map<String, dynamic>.from(v as Map);
          tmp.add(EducationItem.fromMap(m, key: k));
        });
      }
      tmp.sort((a, b) => a.title.compareTo(b.title));
      setState(() => educationItems = tmp);
    });

    // feed
    _feedSub = _db.ref('awareness/feed').onValue.listen((evt) {
      final s = evt.snapshot;
      final List<NewsItem> tmp = [];
      if (s.value != null) {
        final map = Map.from(s.value as Map);
        map.forEach((k, v) {
          final m = Map<String, dynamic>.from(v as Map);
          tmp.add(NewsItem.fromMap(m, key: k));
        });
      }
      tmp.sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      setState(() => feedItems = tmp);
    });
  }

  void _listenBookmarksIfSignedIn() {
    // clear existing
    _bookmarkSub?.cancel();
    bookmarks.clear();

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {}); // refresh UI (bookmarks empty)
      return;
    }
    final ref = _db.ref('bookmarks/${user.uid}');
    _bookmarkSub = ref.onValue.listen((evt) {
      bookmarks.clear();
      if (evt.snapshot.value != null) {
        final map = Map.from(evt.snapshot.value as Map);
        map.forEach((k, v) {
          // value could be true / timestamp / object
          bookmarks.add(k.toString());
        });
      }
      setState(() {});
    });
  }

  Future<void> _toggleBookmark(NewsItem item) async {
    final user = _auth.currentUser;
    if (user == null) {
      // prompt login
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('You need to sign in to save bookmarks. Would you like to sign in now?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sign in')),
          ],
        ),
      );
      if (go == true) {
        if (!mounted) return;
        Navigator.of(context).pushNamed('/login');
      }
      return;
    }

    final ref = _db.ref('bookmarks/${user.uid}/${item.id}');
    if (bookmarks.contains(item.id)) {
      // remove
      await ref.remove();
    } else {
      await ref.set({'savedAt': ServerValue.timestamp, 'title': item.title, 'link': item.link});
    }
    // database subscription will update UI
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  void dispose() {
    _carouselSub?.cancel();
    _educationSub?.cancel();
    _feedSub?.cancel();
    _bookmarkSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildCarousel() {
    if (carouselItems.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(child: Text('No news available', style: TextStyle(color: Colors.grey.shade700))),
      );
    }
    return SizedBox(
      height: 170,
      child: PageView.builder(
        controller: _pageController,
        itemCount: carouselItems.length,
        itemBuilder: (context, index) {
          final it = carouselItems[index];
          final isBook = bookmarks.contains(it.id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
            child: GestureDetector(
              onTap: () => _openLink(it.link),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Container(
                    width: 120,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                      color: Colors.deepPurple.shade50,
                      image: it.imageUrl != null && it.imageUrl!.isNotEmpty
                          ? DecorationImage(image: NetworkImage(it.imageUrl!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: it.imageUrl == null || it.imageUrl!.isEmpty
                        ? const Center(child: Icon(Icons.article, size: 44, color: Colors.deepPurple))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text(it.description, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const Spacer(),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          IconButton(
                            onPressed: () => _toggleBookmark(it),
                            icon: Icon(isBook ? Icons.bookmark : Icons.bookmark_border, color: Colors.deepPurple),
                          ),
                          TextButton(onPressed: () => _openLink(it.link), child: const Text('Read More')),
                        ])
                      ]),
                    ),
                  )
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEducationAccordion() {
    if (educationItems.isEmpty) {
      return const Text('No education content available.');
    }
    return Column(
      children: educationItems.map((e) {
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: const Icon(Icons.health_and_safety, color: Colors.deepPurple),
            title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(e.short),
            children: [
              Text(e.details, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 8),
              Row(children: [
                ElevatedButton.icon(
                  onPressed: () => _openLink(e.moreLink ?? 'https://www.who.int/health-topics/cancer'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Learn more'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    // optional: bookmark education item too
                    final asNews = NewsItem(
                      id: e.id,
                      title: e.title,
                      description: e.short,
                      link: e.moreLink ?? '',
                      imageUrl: '',
                    );
                    _toggleBookmark(asNews);
                  },
                  icon: const Icon(Icons.bookmark_border),
                  label: const Text('Bookmark'),
                )
              ])
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeedList() {
    if (feedItems.isEmpty) return const Text('No articles in feed.');
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: feedItems.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final it = feedItems[index];
        final isBook = bookmarks.contains(it.id);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          leading: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(8),
              image: it.imageUrl != null && it.imageUrl!.isNotEmpty ? DecorationImage(image: NetworkImage(it.imageUrl!), fit: BoxFit.cover) : null,
            ),
            child: (it.imageUrl == null || it.imageUrl!.isEmpty) ? const Icon(Icons.article, color: Colors.deepPurple) : null,
          ),
          title: Text(it.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(it.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: Icon(isBook ? Icons.bookmark : Icons.bookmark_border, color: Colors.deepPurple), onPressed: () => _toggleBookmark(it)),
            IconButton(icon: const Icon(Icons.launch), onPressed: () => _openLink(it.link)),
          ]),
          onTap: () => _openLink(it.link),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('General Awareness'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            onPressed: () {
              final user = _auth.currentUser;
              if (user != null) {
                Navigator.of(context).pushNamed('/home'); // or bookmarks screen if you create it
              } else {
                Navigator.of(context).pushNamed('/login');
              }
            },
            icon: const Icon(Icons.person),
            tooltip: 'Profile / Home',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // manual refresh: re-attach listeners (data is real-time anyway)
          _attachListeners();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('Latest News', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 8),
            _buildCarousel(),
            const SizedBox(height: 14),
            const Text('Cancer Education', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildEducationAccordion(),
            const SizedBox(height: 12),
            const Text('Research & Articles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildFeedList(),
            const SizedBox(height: 32),
            Center(child: Text('Resources: WHO | American Cancer Society | Local Hospitals', style: TextStyle(color: Colors.grey.shade700), textAlign: TextAlign.center)),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// Models
class NewsItem {
  final String id;
  final String title;
  final String description;
  final String link;
  final String? imageUrl;
  final int? timestamp;
  NewsItem({required this.id, required this.title, required this.description, required this.link, this.imageUrl, this.timestamp});
  factory NewsItem.fromMap(Map<String, dynamic> m, {required String key}) {
    return NewsItem(
      id: m['id']?.toString() ?? key,
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      link: m['link']?.toString() ?? '',
      imageUrl: m['imageUrl']?.toString(),
      timestamp: (m['timestamp'] is int) ? m['timestamp'] as int : (m['timestamp'] is double ? (m['timestamp'] as double).toInt() : null),
    );
  }
}

class EducationItem {
  final String id;
  final String title;
  final String short;
  final String details;
  final String? moreLink;
  EducationItem({required this.id, required this.title, required this.short, required this.details, this.moreLink});
  factory EducationItem.fromMap(Map<String, dynamic> m, {required String key}) {
    return EducationItem(
      id: m['id']?.toString() ?? key,
      title: m['title']?.toString() ?? '',
      short: m['short']?.toString() ?? '',
      details: m['details']?.toString() ?? '',
      moreLink: m['moreLink']?.toString(),
    );
  }
}
