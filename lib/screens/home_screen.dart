import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/event_model.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../widgets/event_card_interactions.dart';
import '../widgets/youtube_player_widget.dart';
import 'create_event_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _eventPageSize = 3;
  static const _categories = [
    'FC Mobile',
    'EA Sports',
    'Cricket',
    'Football',
    'Badminton',
    'Chess',
    'Carrom',
  ];

  String _searchQuery = '';
  String _selectedCategory = 'All';
  final List<EventModel> _events = [];
  List<DocumentSnapshot?> _pageDocumentHistory = [null];
  int _currentPage = 1;
  bool _isLoadingEvents = false;
  Object? _eventLoadError;
  final EventService _eventService = EventService();

  @override
  void initState() {
    super.initState();
    _loadPage(pageNumber: 1, startAfterDocument: null);
  }

  Future<void> _loadPage({
    required int pageNumber,
    required DocumentSnapshot? startAfterDocument,
  }) async {
    if (_isLoadingEvents) return;
    setState(() {
      _isLoadingEvents = true;
      _eventLoadError = null;
    });

    try {
      final page = await _eventService.getPaginatedEvents(
        startAfterDocument: startAfterDocument,
        limit: _eventPageSize,
      );
      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(page);
        _currentPage = pageNumber;

        _pageDocumentHistory = _pageDocumentHistory.take(pageNumber).toList();
        if (page.length == _eventPageSize) {
          final nextPageDocument = page.last.documentSnapshot;
          if (nextPageDocument != null) {
            _pageDocumentHistory.add(nextPageDocument);
          }
        }
      });
    } catch (error) {
      if (mounted) setState(() => _eventLoadError = error);
    } finally {
      if (mounted) setState(() => _isLoadingEvents = false);
    }
  }

  Future<void> _goToPreviousPage() async {
    if (_currentPage <= 1 || _isLoadingEvents) return;
    await _loadPage(
      pageNumber: _currentPage - 1,
      startAfterDocument: _pageDocumentHistory[_currentPage - 2],
    );
  }

  Future<void> _goToNextPage() async {
    if (_isLoadingEvents || _events.length < _eventPageSize) return;
    final nextPageNumber = _currentPage + 1;
    await _loadPage(
      pageNumber: nextPageNumber,
      startAfterDocument: _pageDocumentHistory[_currentPage],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final localDate = dateTime.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year} $hour:$minute';
  }

  void _showCommentsBottomSheet(
    BuildContext context,
    String eventId,
    String currentStudentId,
  ) {
    final commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 16,
          left: 16,
          right: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Comments',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('events')
                    .doc(eventId)
                    .collection('comments')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No comments yet.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        title: Text(
                          data['studentId'] ?? 'Student',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(data['text'] ?? ''),
                        trailing: data['studentId'] == currentStudentId
                            ? IconButton(
                                tooltip: 'Delete comment',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => EventService().deleteComment(
                                  eventId,
                                  docs[index].id,
                                ),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    if (commentController.text.trim().isNotEmpty) {
                      await EventService().addComment(
                        eventId: eventId,
                        studentId: currentStudentId,
                        text: commentController.text.trim(),
                      );
                      commentController.clear();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showParticipantsBottomSheet(BuildContext context, String eventId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .collection('registrations')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return const Center(
                child: Text('No participants registered yet.'),
              );
            }
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                var data = docs[i].data() as Map<String, dynamic>;
                return ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text('Student ID: ${data['studentId']}'),
                  subtitle: Text('Dept: ${data['department']}'),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final authService = AuthService();
    final eventService = _eventService;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Sports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await authService.signOut(),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateEventScreen()),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Create Event'),
        ),
      ),
      body: user == null
          ? const Center(child: Text('No User Found'))
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('User Profile Not Found'));
                }

                var userData = snapshot.data!.data() as Map<String, dynamic>;

                return Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(12),
                      color: Colors.deepPurple.shade50,
                      child: ListTile(
                        title: Text('Welcome, ${userData['studentId']}'),
                        subtitle: Text('Dept: ${userData['department']}'),
                      ),
                    ),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          if (_isLoadingEvents && _events.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final events = _events;
                          final query = _searchQuery.trim().toLowerCase();
                          final filteredEvents = events.where((event) {
                            final matchesCategory =
                                _selectedCategory == 'All' ||
                                event.category == _selectedCategory;
                            final matchesQuery =
                                query.isEmpty ||
                                event.title.toLowerCase().contains(query) ||
                                event.description.toLowerCase().contains(query);
                            return matchesCategory && matchesQuery;
                          }).toList();

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  8,
                                ),
                                child: TextField(
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  decoration: InputDecoration(
                                    hintText: 'Search events',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _searchQuery.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () => setState(
                                              () => _searchQuery = '',
                                            ),
                                            icon: const Icon(Icons.clear),
                                          ),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 48,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  children: ['All', ..._categories].map((
                                    category,
                                  ) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(category),
                                        selected: _selectedCategory == category,
                                        onSelected: (_) => setState(
                                          () => _selectedCategory = category,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              Expanded(
                                child: filteredEvents.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _eventLoadError != null
                                                  ? 'Could not load events.'
                                                  : events.isEmpty
                                                  ? 'No active sports events found.'
                                                  : 'No events match your search.',
                                            ),
                                            if (_eventLoadError != null)
                                              TextButton.icon(
                                                onPressed: () => _loadPage(
                                                  pageNumber: _currentPage,
                                                  startAfterDocument:
                                                      _pageDocumentHistory[_currentPage -
                                                          1],
                                                ),
                                                icon: const Icon(Icons.refresh),
                                                label: const Text('Retry'),
                                              ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filteredEvents.length,
                                        itemBuilder: (context, index) {
                                          final event = filteredEvents[index];
                                          final isExpired = DateTime.now()
                                              .isAfter(
                                                event.registrationDeadline,
                                              );

                                          return Card(
                                            clipBehavior: Clip.antiAlias,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                if (event.imageUrl != null &&
                                                    event.imageUrl!
                                                        .trim()
                                                        .isNotEmpty)
                                                  Image.network(
                                                    event.imageUrl!,
                                                    height: 180,
                                                    width: double.infinity,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) => const SizedBox(
                                                          height: 180,
                                                          child: Center(
                                                            child: Icon(
                                                              Icons
                                                                  .broken_image_outlined,
                                                            ),
                                                          ),
                                                        ),
                                                  ),
                                                Padding(
                                                  padding: const EdgeInsets.all(
                                                    12.0,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Text(
                                                            event.title,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 18,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                          ),
                                                          Chip(
                                                            label: Text(
                                                              event.category,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(event.description),
                                                      const SizedBox(height: 8),
                                                      EventCardInteractions(
                                                        event: event,
                                                        userId: user.uid,
                                                        eventService:
                                                            eventService,
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Text(
                                                        'Event date: ${_formatDateTime(event.eventDate)}',
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Registration deadline: ${_formatDateTime(event.registrationDeadline)}',
                                                        style: TextStyle(
                                                          color: isExpired
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .error
                                                              : null,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      SizedBox(
                                                        height: 150,
                                                        child: FlutterMap(
                                                          options: MapOptions(
                                                            initialCenter: LatLng(
                                                              event.latitude ??
                                                                  22.4707,
                                                              event.longitude ??
                                                                  91.7877,
                                                            ),
                                                            initialZoom: 15,
                                                          ),
                                                          children: [
                                                            TileLayer(
                                                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                                              userAgentPackageName: 'com.example.campus_sports_app',
                                                            ),
                                                            MarkerLayer(
                                                              markers: [
                                                                Marker(
                                                                  point: LatLng(
                                                                    event.latitude ??
                                                                        22.4707,
                                                                    event.longitude ??
                                                                        91.7877,
                                                                  ),
                                                                  width: 40,
                                                                  height: 40,
                                                                  child: const Icon(
                                                                    Icons
                                                                        .location_on,
                                                                    color: Colors
                                                                        .red,
                                                                    size: 36,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const RichAttributionWidget(
                                                              showFlutterMapAttribution:
                                                                  false,
                                                              attributions: [
                                                                TextSourceAttribution(
                                                                  'OpenStreetMap contributors',
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (event
                                                              .videoUrl
                                                              ?.isNotEmpty ==
                                                          true) ...[
                                                        const SizedBox(
                                                          height: 12,
                                                        ),
                                                        YouTubePlayerWidget(
                                                          videoUrl:
                                                              event.videoUrl!,
                                                        ),
                                                      ],
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          TextButton.icon(
                                                            icon: const Icon(
                                                              Icons
                                                                  .people_outline,
                                                            ),
                                                            label: const Text(
                                                              'Participants',
                                                            ),
                                                            onPressed: () =>
                                                                _showParticipantsBottomSheet(
                                                                  context,
                                                                  event.id,
                                                                ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: isExpired
                                                                ? null
                                                                : () async {
                                                                    await eventService.registerForEvent(
                                                                      eventId:
                                                                          event
                                                                              .id,
                                                                      userId: user
                                                                          .uid,
                                                                      studentId:
                                                                          userData['studentId'],
                                                                      department:
                                                                          userData['department'],
                                                                    );
                                                                    if (context
                                                                        .mounted) {
                                                                      ScaffoldMessenger.of(
                                                                        context,
                                                                      ).showSnackBar(
                                                                        SnackBar(
                                                                          content: Text(
                                                                            'Registered for ${event.title}!',
                                                                          ),
                                                                        ),
                                                                      );
                                                                    }
                                                                  },
                                                            child: Text(
                                                              isExpired
                                                                  ? 'Expired'
                                                                  : 'Register',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const Divider(),
                                                      Row(
                                                        children: [
                                                          IconButton(
                                                            icon: const Icon(
                                                              Icons
                                                                  .comment_outlined,
                                                            ),
                                                            onPressed: () =>
                                                                _showCommentsBottomSheet(
                                                                  context,
                                                                  event.id,
                                                                  userData['studentId'],
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              if (_eventLoadError != null && events.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Could not load page: $_eventLoadError',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton(
                                      onPressed:
                                          _currentPage == 1 || _isLoadingEvents
                                          ? null
                                          : _goToPreviousPage,
                                      child: const Text('Previous'),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Page $_currentPage'),
                                        if (_isLoadingEvents) ...[
                                          const SizedBox(width: 8),
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    ElevatedButton(
                                      onPressed:
                                          _events.length < _eventPageSize ||
                                              _isLoadingEvents
                                          ? null
                                          : _goToNextPage,
                                      child: const Text('Next'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
