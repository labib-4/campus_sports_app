import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/event_model.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
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
  final ScrollController _feedScrollController = ScrollController();
  final List<EventModel> _events = [];
  bool _isLoadingEvents = false;
  bool _hasMoreEvents = true;
  Object? _eventLoadError;
  DocumentSnapshot? _lastEventDocument;
  final EventService _eventService = EventService();
  final Map<String, bool> _likeOverrides = {};
  final Map<String, bool> _dislikeOverrides = {};
  final Set<String> _pendingReactions = {};
  final Map<String, double?> _ratingOverrides = {};
  final Set<String> _pendingRatings = {};

  @override
  void initState() {
    super.initState();
    _feedScrollController.addListener(_onFeedScroll);
    _loadMoreEvents();
  }

  @override
  void dispose() {
    _feedScrollController
      ..removeListener(_onFeedScroll)
      ..dispose();
    super.dispose();
  }

  void _onFeedScroll() {
    if (!_feedScrollController.hasClients ||
        _isLoadingEvents ||
        !_hasMoreEvents) {
      return;
    }
    if (_feedScrollController.position.extentAfter < 320) {
      _loadMoreEvents();
    }
  }

  Future<void> _loadMoreEvents() async {
    if (_isLoadingEvents || !_hasMoreEvents) return;
    setState(() {
      _isLoadingEvents = true;
      _eventLoadError = null;
    });

    try {
      final page = await _eventService.getPaginatedEvents(
        startAfterDocument: _lastEventDocument,
        limit: _eventPageSize,
      );
      if (!mounted) return;
      setState(() {
        _events.addAll(page);
        if (page.isNotEmpty) {
          _lastEventDocument = page.last.documentSnapshot;
        }
        _hasMoreEvents = page.length == _eventPageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _eventLoadError = error);
    } finally {
      if (mounted) setState(() => _isLoadingEvents = false);
    }
  }

  int _displayedReactionCount(
    List<String> reactions,
    Map<String, bool> overrides,
    String eventId,
    String userId,
  ) {
    final baseline = reactions.contains(userId);
    final override = overrides[eventId];
    if (override == null || override == baseline) return reactions.length;
    return reactions.length + (override ? 1 : -1);
  }

  String _formatDateTime(DateTime dateTime) {
    final localDate = dateTime.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year} $hour:$minute';
  }

  Future<void> _toggleLike(
    EventService eventService,
    EventModel event,
    String userId,
  ) async {
    if (_pendingReactions.contains(event.id)) return;

    final currentlyLiked =
        _likeOverrides[event.id] ?? event.likes.contains(userId);
    setState(() {
      _likeOverrides[event.id] = !currentlyLiked;
      _dislikeOverrides[event.id] = false;
      _pendingReactions.add(event.id);
    });

    try {
      await eventService.toggleLike(event.id, userId);
      await _refreshEvent(event.id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _likeOverrides.remove(event.id);
          _dislikeOverrides.remove(event.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update like: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingReactions.remove(event.id));
    }
  }

  Future<void> _toggleDislike(
    EventService eventService,
    EventModel event,
    String userId,
  ) async {
    if (_pendingReactions.contains(event.id)) return;

    final currentlyDisliked =
        _dislikeOverrides[event.id] ?? event.dislikes.contains(userId);
    setState(() {
      _dislikeOverrides[event.id] = !currentlyDisliked;
      _likeOverrides[event.id] = false;
      _pendingReactions.add(event.id);
    });

    try {
      await eventService.toggleDislike(event.id, userId);
      await _refreshEvent(event.id);
    } catch (error) {
      if (mounted) {
        setState(() {
          _likeOverrides.remove(event.id);
          _dislikeOverrides.remove(event.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update reaction: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingReactions.remove(event.id));
    }
  }

  Future<void> _setRating(
    EventService eventService,
    EventModel event,
    String userId,
    double? rating,
  ) async {
    if (_pendingRatings.contains(event.id)) return;

    setState(() {
      _ratingOverrides[event.id] = rating;
      _pendingRatings.add(event.id);
    });

    try {
      if (rating == null) {
        await eventService.removeRating(event.id, userId);
      } else {
        await eventService.rateEvent(event.id, userId, rating);
      }
      await _refreshEvent(event.id);
    } catch (error) {
      if (mounted) {
        setState(() => _ratingOverrides.remove(event.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update rating: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingRatings.remove(event.id));
    }
  }

  EventModel _eventFromSnapshot(DocumentSnapshot snapshot) =>
      EventModel.fromFirestore(snapshot);

  Future<void> _refreshEvent(String eventId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .get();
      if (!mounted || !snapshot.exists) return;
      final updatedEvent = _eventFromSnapshot(snapshot);
      setState(() {
        final index = _events.indexWhere((event) => event.id == eventId);
        if (index != -1) _events[index] = updatedEvent;
        _likeOverrides.remove(eventId);
        _dislikeOverrides.remove(eventId);
        _ratingOverrides.remove(eventId);
      });
    } catch (_) {}
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateEventScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Event'),
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
                          for (final event in events) {
                            if (!_pendingRatings.contains(event.id) &&
                                _ratingOverrides.containsKey(event.id) &&
                                event.ratings[user.uid] ==
                                    _ratingOverrides[event.id]) {
                              final ratingOverride = _ratingOverrides[event.id];
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted &&
                                    !_pendingRatings.contains(event.id) &&
                                    _ratingOverrides.containsKey(event.id) &&
                                    _ratingOverrides[event.id] ==
                                        ratingOverride) {
                                  setState(
                                    () => _ratingOverrides.remove(event.id),
                                  );
                                }
                              });
                            }
                          }
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
                                                onPressed: _loadMoreEvents,
                                                icon: const Icon(Icons.refresh),
                                                label: const Text('Retry'),
                                              )
                                            else if (_hasMoreEvents)
                                              TextButton(
                                                onPressed: _loadMoreEvents,
                                                child: const Text('Load more'),
                                              ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _feedScrollController,
                                        itemCount:
                                            filteredEvents.length +
                                            (_isLoadingEvents ||
                                                    _eventLoadError != null ||
                                                    _hasMoreEvents
                                                ? 1
                                                : 0),
                                        itemBuilder: (context, index) {
                                          if (index == filteredEvents.length) {
                                            if (_eventLoadError != null) {
                                              return Center(
                                                child: TextButton.icon(
                                                  onPressed: _loadMoreEvents,
                                                  icon: const Icon(
                                                    Icons.refresh,
                                                  ),
                                                  label: const Text('Retry'),
                                                ),
                                              );
                                            }
                                            return _isLoadingEvents
                                                ? const Padding(
                                                    padding: EdgeInsets.all(16),
                                                    child: Center(
                                                      child: SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                    ),
                                                  )
                                                : const SizedBox(height: 48);
                                          }
                                          final event = filteredEvents[index];
                                          final isLiked =
                                              _likeOverrides[event.id] ??
                                              event.likes.contains(user.uid);
                                          final isDisliked =
                                              _dislikeOverrides[event.id] ??
                                              event.dislikes.contains(user.uid);
                                          final displayedLikeCount =
                                              _displayedReactionCount(
                                                event.likes,
                                                _likeOverrides,
                                                event.id,
                                                user.uid,
                                              );
                                          final displayedDislikeCount =
                                              _displayedReactionCount(
                                                event.dislikes,
                                                _dislikeOverrides,
                                                event.id,
                                                user.uid,
                                              );
                                          final displayedRatings =
                                              Map<String, double>.from(
                                                event.ratings,
                                              );
                                          if (_ratingOverrides.containsKey(
                                            event.id,
                                          )) {
                                            final override =
                                                _ratingOverrides[event.id];
                                            if (override == null) {
                                              displayedRatings.remove(user.uid);
                                            } else {
                                              displayedRatings[user.uid] =
                                                  override;
                                            }
                                          }
                                          final displayedTotalRatings =
                                              displayedRatings.length;
                                          final displayedAverageRating =
                                              displayedTotalRatings == 0
                                              ? 0.0
                                              : displayedRatings.values.reduce(
                                                      (total, rating) =>
                                                          total + rating,
                                                    ) /
                                                    displayedTotalRatings;
                                          final currentUserRating =
                                              displayedRatings[user.uid];
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
                                                      Row(
                                                        children: [
                                                          const Icon(
                                                            Icons.star,
                                                            color: Colors.amber,
                                                            size: 20,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '${displayedAverageRating.toStringAsFixed(1)} ($displayedTotalRatings ${displayedTotalRatings == 1 ? 'review' : 'reviews'})',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      Wrap(
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          for (
                                                            var star = 1;
                                                            star <= 5;
                                                            star++
                                                          )
                                                            IconButton(
                                                              tooltip:
                                                                  'Rate $star out of 5',
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              constraints:
                                                                  const BoxConstraints(
                                                                    minWidth:
                                                                        36,
                                                                    minHeight:
                                                                        36,
                                                                  ),
                                                              onPressed:
                                                                  _pendingRatings
                                                                      .contains(
                                                                        event
                                                                            .id,
                                                                      )
                                                                  ? null
                                                                  : () => _setRating(
                                                                      eventService,
                                                                      event,
                                                                      user.uid,
                                                                      star.toDouble(),
                                                                    ),
                                                              icon: Icon(
                                                                currentUserRating !=
                                                                            null &&
                                                                        star <=
                                                                            currentUserRating
                                                                    ? Icons.star
                                                                    : Icons
                                                                          .star_border,
                                                                color:
                                                                    currentUserRating !=
                                                                            null &&
                                                                        star <=
                                                                            currentUserRating
                                                                    ? Colors
                                                                          .amber
                                                                    : Colors
                                                                          .grey,
                                                              ),
                                                            ),
                                                          if (currentUserRating !=
                                                              null)
                                                            TextButton(
                                                              onPressed:
                                                                  _pendingRatings
                                                                      .contains(
                                                                        event
                                                                            .id,
                                                                      )
                                                                  ? null
                                                                  : () => _setRating(
                                                                      eventService,
                                                                      event,
                                                                      user.uid,
                                                                      null,
                                                                    ),
                                                              child: const Text(
                                                                'Remove Rating',
                                                              ),
                                                            ),
                                                        ],
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
                                                          TextButton.icon(
                                                            onPressed:
                                                                _pendingReactions
                                                                    .contains(
                                                                      event.id,
                                                                    )
                                                                ? null
                                                                : () => _toggleLike(
                                                                    eventService,
                                                                    event,
                                                                    user.uid,
                                                                  ),
                                                            icon: Icon(
                                                              isLiked
                                                                  ? Icons
                                                                        .thumb_up
                                                                  : Icons
                                                                        .thumb_up_outlined,
                                                              color: isLiked
                                                                  ? Colors.blue
                                                                  : null,
                                                            ),
                                                            label: Text(
                                                              '$displayedLikeCount',
                                                            ),
                                                          ),
                                                          TextButton.icon(
                                                            onPressed:
                                                                _pendingReactions
                                                                    .contains(
                                                                      event.id,
                                                                    )
                                                                ? null
                                                                : () => _toggleDislike(
                                                                    eventService,
                                                                    event,
                                                                    user.uid,
                                                                  ),
                                                            icon: Icon(
                                                              isDisliked
                                                                  ? Icons
                                                                        .thumb_down
                                                                  : Icons
                                                                        .thumb_down_outlined,
                                                              color: isDisliked
                                                                  ? Colors
                                                                        .deepOrange
                                                                  : null,
                                                            ),
                                                            label: Text(
                                                              '$displayedDislikeCount',
                                                            ),
                                                          ),
                                                          const Spacer(),
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
