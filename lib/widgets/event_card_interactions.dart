import 'package:flutter/material.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';

class EventCardInteractions extends StatefulWidget {
  const EventCardInteractions({
    required this.event,
    required this.userId,
    required this.eventService,
    super.key,
  });

  final EventModel event;
  final String userId;
  final EventService eventService;

  @override
  State<EventCardInteractions> createState() => _EventCardInteractionsState();
}

class _EventCardInteractionsState extends State<EventCardInteractions> {
  late bool _isLiked;
  late bool _isDisliked;
  late int _likeCount;
  late int _dislikeCount;
  late Map<String, double> _ratings;
  bool _isSavingReaction = false;
  bool _isSavingRating = false;

  @override
  void initState() {
    super.initState();
    _syncFromEvent();
  }

  @override
  void didUpdateWidget(covariant EventCardInteractions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event != widget.event) _syncFromEvent();
  }

  void _syncFromEvent() {
    _isLiked = widget.event.likes.contains(widget.userId);
    _isDisliked = widget.event.dislikes.contains(widget.userId);
    _likeCount = widget.event.likes.length;
    _dislikeCount = widget.event.dislikes.length;
    _ratings = Map<String, double>.from(widget.event.ratings);
  }

  double get _averageRating {
    if (_ratings.isEmpty) return 0;
    return _ratings.values.reduce((total, rating) => total + rating) /
        _ratings.length;
  }

  Future<void> _toggleReaction({required bool like}) async {
    if (_isSavingReaction) return;

    final previousLiked = _isLiked;
    final previousDisliked = _isDisliked;
    final previousLikeCount = _likeCount;
    final previousDislikeCount = _dislikeCount;
    final currentlyActive = like ? _isLiked : _isDisliked;

    setState(() {
      if (like) {
        _isLiked = !currentlyActive;
        _likeCount += currentlyActive ? -1 : 1;
        if (_isDisliked) {
          _isDisliked = false;
          _dislikeCount--;
        }
      } else {
        _isDisliked = !currentlyActive;
        _dislikeCount += currentlyActive ? -1 : 1;
        if (_isLiked) {
          _isLiked = false;
          _likeCount--;
        }
      }
      _isSavingReaction = true;
    });

    try {
      if (like) {
        await widget.eventService.toggleLike(widget.event.id, widget.userId);
      } else {
        await widget.eventService.toggleDislike(widget.event.id, widget.userId);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLiked = previousLiked;
          _isDisliked = previousDisliked;
          _likeCount = previousLikeCount;
          _dislikeCount = previousDislikeCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update reaction: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingReaction = false);
    }
  }

  Future<void> _setRating(double? rating) async {
    if (_isSavingRating) return;

    final previousRatings = Map<String, double>.from(_ratings);
    setState(() {
      if (rating == null) {
        _ratings.remove(widget.userId);
      } else {
        _ratings[widget.userId] = rating;
      }
      _isSavingRating = true;
    });

    try {
      if (rating == null) {
        await widget.eventService.removeRating(widget.event.id, widget.userId);
      } else {
        await widget.eventService.rateEvent(
          widget.event.id,
          widget.userId,
          rating,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _ratings = previousRatings);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update rating: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserRating = _ratings[widget.userId];
    final ratingCount = _ratings.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 20),
            const SizedBox(width: 4),
            Text(
              '${_averageRating.toStringAsFixed(1)} ($ratingCount ${ratingCount == 1 ? 'review' : 'reviews'})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                tooltip: 'Rate $star out of 5',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _isSavingRating
                    ? null
                    : () => _setRating(star.toDouble()),
                icon: Icon(
                  currentUserRating != null && star <= currentUserRating
                      ? Icons.star
                      : Icons.star_border,
                  color: currentUserRating != null && star <= currentUserRating
                      ? Colors.amber
                      : Colors.grey,
                ),
              ),
            if (currentUserRating != null)
              TextButton(
                onPressed: _isSavingRating ? null : () => _setRating(null),
                child: const Text('Remove Rating'),
              ),
          ],
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isSavingReaction
                  ? null
                  : () => _toggleReaction(like: true),
              icon: Icon(
                _isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                color: _isLiked ? Colors.blue : null,
              ),
              label: Text('$_likeCount'),
            ),
            TextButton.icon(
              onPressed: _isSavingReaction
                  ? null
                  : () => _toggleReaction(like: false),
              icon: Icon(
                _isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                color: _isDisliked ? Colors.deepOrange : null,
              ),
              label: Text('$_dislikeCount'),
            ),
          ],
        ),
      ],
    );
  }
}
