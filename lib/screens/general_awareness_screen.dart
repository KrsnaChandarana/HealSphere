import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';

class GeneralAwarenessScreen extends StatefulWidget {
  const GeneralAwarenessScreen({super.key, this.showAuthCtas = false});

  final bool showAuthCtas;

  @override
  State<GeneralAwarenessScreen> createState() => _GeneralAwarenessScreenState();
}

class _GeneralAwarenessScreenState extends State<GeneralAwarenessScreen> {
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
  StreamSubscription<User?>? _authSub;

  final PageController _pageController = PageController(viewportFraction: 0.88);

  // Brand-ish colors (from logo)
  final Color _purple = const Color(0xFF8E24AA);
  final Color _green = const Color(0xFF43A047);
  final Color _softBg = const Color(0xFFF6F7FB);
  final Color _redAccent = const Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _attachListeners();
    _listenBookmarksIfSignedIn();
    _authSub = _auth.authStateChanges().listen((user) {
      _listenBookmarksIfSignedIn();
    });
  }

  void _attachListeners() {
    _carouselSub?.cancel();
    _educationSub?.cancel();
    _feedSub?.cancel();

    // carousel
    _carouselSub = DatabaseService.getAwarenessCarousel().listen((evt) {
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
    });

    // education
    _educationSub = DatabaseService.getAwarenessEducation().listen((evt) {
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
    _feedSub = DatabaseService.getAwarenessFeed().listen((evt) {
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
    _bookmarkSub?.cancel();
    bookmarks.clear();

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {});
      return;
    }
    _bookmarkSub = DatabaseService.getUserBookmarks(user.uid).listen((evt) {
      bookmarks.clear();
      if (evt.snapshot.value != null) {
        final map = Map.from(evt.snapshot.value as Map);
        map.forEach((k, v) {
          bookmarks.add(k.toString());
        });
      }
      setState(() {});
    });
  }

  Future<void> _toggleBookmark(NewsItem item) async {
    final user = _auth.currentUser;
    if (user == null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Sign in to save',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _purple,
            ),
          ),
          content: const Text(
              'Create a free HealSphere account to bookmark helpful articles.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Maybe later')),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                minimumSize: const Size(96, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      if (go == true) {
        if (!mounted) return;
        Navigator.of(context).pushNamed('/login');
      }
      return;
    }

    if (bookmarks.contains(item.id)) {
      await DatabaseService.removeBookmark(uid: user.uid, itemId: item.id);
    } else {
      await DatabaseService.addBookmark(
        uid: user.uid,
        itemId: item.id,
        title: item.title,
        link: item.link,
        type: 'news',
      );
    }
  }

  Widget _buildAuthBanner() {
    if (!widget.showAuthCtas || _auth.currentUser != null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: _purple.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _purple.withOpacity(0.14),
              child: Icon(Icons.favorite, color: _redAccent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join HealSphere',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _purple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Track your journey, talk to your care team, and save articles you trust.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _purple,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Login'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/register'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            side: BorderSide(color: _green),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            'Register',
                            style: TextStyle(color: _green),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  void dispose() {
    _carouselSub?.cancel();
    _educationSub?.cancel();
    _feedSub?.cancel();
    _bookmarkSub?.cancel();
    _authSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /* ------------------------ UI sections ------------------------ */

  Widget _sectionTitle(String title, {String? subtitle, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        children: [
          if (icon != null)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_purple, _green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(6),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
          if (icon != null) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    if (carouselItems.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
            child: Text('No news available right now',
                style: TextStyle(color: Colors.grey.shade700))),
      );
    }
    return SizedBox(
      height: 190,
      child: PageView.builder(
        controller: _pageController,
        itemCount: carouselItems.length,
        itemBuilder: (context, index) {
          final it = carouselItems[index];
          final isBook = bookmarks.contains(it.id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6),
            child: GestureDetector(
              onTap: () => _openLink(it.link),
              child: Card(
                elevation: 5,
                shadowColor: _purple.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    children: [
                      // image / icon side
                      Container(
                        width: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_purple.withOpacity(0.8), _green],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          image: it.imageUrl != null && it.imageUrl!.isNotEmpty
                              ? DecorationImage(
                            image: NetworkImage(it.imageUrl!),
                            fit: BoxFit.cover,
                          )
                              : null,
                        ),
                        child: (it.imageUrl == null ||
                            it.imageUrl!.isEmpty)
                            ? const Center(
                          child: Icon(Icons.article,
                              size: 44, color: Colors.white),
                        )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      // text
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12.0, horizontal: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Text(
                                  it.description,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    onPressed: () => _toggleBookmark(it),
                                    icon: Icon(
                                      isBook
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                      color: isBook ? _purple : _purple,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _openLink(it.link),
                                    style: TextButton.styleFrom(
                                      foregroundColor: _green,
                                    ),
                                    child: const Text('Read more'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEducationAccordion() {
    if (educationItems.isEmpty) {
      return const Text('No education content available yet.');
    }
    return Column(
      children: educationItems.map((e) {
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            leading: Icon(Icons.health_and_safety, color: _green),
            title: Text(
              e.title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              e.short,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              Text(
                e.details,
                style: const TextStyle(height: 1.4, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _openLink(e.moreLink ??
                        'https://www.who.int/health-topics/cancer'),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Learn more'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      final asNews = NewsItem(
                        id: e.id,
                        title: e.title,
                        description: e.short,
                        link: e.moreLink ?? '',
                        imageUrl: '',
                      );
                      _toggleBookmark(asNews);
                    },
                    icon: const Icon(Icons.bookmark_outline, size: 18),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      side: BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  )
                ],
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeedList() {
    if (feedItems.isEmpty) {
      return const Text('No articles in the feed yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: feedItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final it = feedItems[index];
        final isBook = bookmarks.contains(it.id);
        return Card(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openLink(it.link),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 2),
                leading: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    image: it.imageUrl != null && it.imageUrl!.isNotEmpty
                        ? DecorationImage(
                      image: NetworkImage(it.imageUrl!),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: (it.imageUrl == null || it.imageUrl!.isEmpty)
                      ? Icon(Icons.article, color: _purple)
                      : null,
                ),
                title: Text(
                  it.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  it.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        isBook ? Icons.bookmark : Icons.bookmark_border,
                        color: isBook ? _purple : Colors.grey.shade700,
                      ),
                      onPressed: () => _toggleBookmark(it),
                      tooltip: isBook ? 'Remove bookmark' : 'Save for later',
                    ),
                    IconButton(
                      icon: const Icon(Icons.launch, size: 20),
                      onPressed: () => _openLink(it.link),
                      tooltip: 'Open article',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _purple,
        title: const Text(
          'General Awareness',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              final user = _auth.currentUser;
              if (user != null) {
                Navigator.of(context).pushNamed('/home');
              } else {
                Navigator.of(context).pushNamed('/login');
              }
            },
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile / Home',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _attachListeners();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuthBanner(),
              _sectionTitle(
                'Latest news',
                subtitle: 'Trusted cancer updates curated for you',
                icon: Icons.auto_awesome,
              ),
              const SizedBox(height: 8),
              _buildCarousel(),
              const SizedBox(height: 18),
              _sectionTitle(
                'Cancer education',
                subtitle: 'Simple explanations and prevention tips',
                icon: Icons.menu_book_outlined,
              ),
              const SizedBox(height: 8),
              _buildEducationAccordion(),
              const SizedBox(height: 18),
              _sectionTitle(
                'Research & articles',
                subtitle: 'Deep dives, survivor stories, and expert blogs',
                icon: Icons.science_outlined,
              ),
              const SizedBox(height: 8),
              _buildFeedList(),
              const SizedBox(height: 26),
              Center(
                child: Text(
                  'Sources: WHO • American Cancer Society • Local oncology networks',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------ Models ------------------------ */

class NewsItem {
  final String id;
  final String title;
  final String description;
  final String link;
  final String? imageUrl;
  final int? timestamp;

  NewsItem({
    required this.id,
    required this.title,
    required this.description,
    required this.link,
    this.imageUrl,
    this.timestamp,
  });

  factory NewsItem.fromMap(Map<String, dynamic> m, {required String key}) {
    return NewsItem(
      id: m['id']?.toString() ?? key,
      title: m['title']?.toString() ?? '',
      description: m['description']?.toString() ?? '',
      link: m['link']?.toString() ?? '',
      imageUrl: m['imageUrl']?.toString(),
      timestamp: (m['timestamp'] is int)
          ? m['timestamp'] as int
          : (m['timestamp'] is double
          ? (m['timestamp'] as double).toInt()
          : null),
    );
  }
}

class EducationItem {
  final String id;
  final String title;
  final String short;
  final String details;
  final String? moreLink;

  EducationItem({
    required this.id,
    required this.title,
    required this.short,
    required this.details,
    this.moreLink,
  });

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
