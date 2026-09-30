import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/event_model.dart';

class EventService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ১. যে কেউ ইভেন্ট ক্রিয়েট করতে পারবে
  Future<void> createEvent(EventModel event) async {
    await _db.collection('events').add(event.toMap());
  }

  Future<String?> uploadEventImage(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://api.imgbb.com/1/upload?key=6d207e02198a847aa98d0a2a901485a5',
        ),
      );

      // Only attach the image file, no additional fields
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        return jsonResponse['data']['url'];
      } else {
        throw Exception(
          'Upload Failed (${response.statusCode}):${response.body}',
        );
      }
    } catch (e) {
      print("Image Upload Error: $e");
      rethrow;
    }
  }

  // ২. লাইভ ইভেন্ট ফিড
  Stream<List<EventModel>> getEvents() {
    return _db.collection('events').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => EventModel.fromFirestore(doc)).toList();
    });
  }

  Future<List<EventModel>> getPaginatedEvents({
    DocumentSnapshot? startAfterDocument,
    int limit = 3,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('events')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }

    final snapshot = await query.get();
    return snapshot.docs.map(EventModel.fromFirestore).toList();
  }

  // ৩. প্লেয়ার রেজিস্ট্রেশন
  Future<void> registerForEvent({
    required String eventId,
    required String userId,
    required String studentId,
    required String department,
  }) async {
    await _db
        .collection('events')
        .doc(eventId)
        .collection('registrations')
        .doc(userId)
        .set({
          'studentId': studentId,
          'department': department,
          'registeredAt': FieldValue.serverTimestamp(),
        });
  }

  // ৪. ইভেন্টে লাইক / আনলাইক (Toggle Like)
  Future<void> toggleLike(String eventId, String userId) async {
    await _toggleReaction(eventId, userId, 'likes', 'dislikes');
  }

  Future<void> toggleDislike(String eventId, String userId) async {
    await _toggleReaction(eventId, userId, 'dislikes', 'likes');
  }

  Future<void> _toggleReaction(
    String eventId,
    String userId,
    String reactionField,
    String oppositeField,
  ) async {
    final eventRef = _db.collection('events').doc(eventId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(eventRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      List<String> userIds(String field) {
        final values = data[field];
        if (values is! Iterable) return <String>[];
        return values.whereType<String>().toList();
      }

      final reactions = userIds(reactionField);
      final oppositeReactions = userIds(oppositeField)..remove(userId);
      if (reactions.contains(userId)) {
        reactions.remove(userId);
      } else {
        reactions.add(userId);
      }

      transaction.update(eventRef, {
        reactionField: reactions,
        oppositeField: oppositeReactions,
      });
    });
  }

  Future<void> rateEvent(String eventId, String userId, double rating) async {
    if (!rating.isFinite || rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Must be between 1 and 5.');
    }

    await _db.collection('events').doc(eventId).update({
      FieldPath(['ratings', userId]): rating,
    });
  }

  Future<void> removeRating(String eventId, String userId) async {
    await _db.collection('events').doc(eventId).update({
      FieldPath(['ratings', userId]): FieldValue.delete(),
    });
  }

  // ৫. ইভেন্টে কমেন্ট করা
  Future<void> addComment({
    required String eventId,
    required String studentId,
    required String text,
  }) async {
    await _db.collection('events').doc(eventId).collection('comments').add({
      'studentId': studentId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment(String eventId, String commentId) async {
    await _db
        .collection('events')
        .doc(eventId)
        .collection('comments')
        .doc(commentId)
        .delete();
  }
}
