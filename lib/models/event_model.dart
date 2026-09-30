import 'package:cloud_firestore/cloud_firestore.dart';

class EventModel {
  final String id;
  final String title;
  final String category;
  final String description;
  final String? videoUrl;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final DateTime eventDate;
  final DateTime registrationDeadline;
  final bool isOpen;
  final List<String> likes;
  final List<String> dislikes;
  final Map<String, double> ratings;
  final DocumentSnapshot? documentSnapshot;

  EventModel({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    this.videoUrl,
    this.imageUrl,
    double? latitude,
    double? longitude,
    required this.eventDate,
    required this.registrationDeadline,
    this.isOpen = true,
    this.likes = const [],
    this.dislikes = const [],
    this.ratings = const {},
    this.documentSnapshot,
  }) : latitude = latitude ?? 22.4707,
       longitude = longitude ?? 91.7877;

  double get averageRating => totalRatings == 0
      ? 0
      : ratings.values.reduce((total, rating) => total + rating) / totalRatings;

  int get totalRatings => ratings.length;

  factory EventModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final eventDateValue = data['eventDate'];
    final eventDate = eventDateValue is Timestamp
        ? eventDateValue.toDate()
        : DateTime.now();
    final ratingsData = data['ratings'] is Map
        ? Map<String, dynamic>.from(data['ratings'] as Map)
        : <String, dynamic>{};
    List<String> readUserIds(String field) {
      final values = data[field];
      if (values is! Iterable) return <String>[];
      return values.whereType<String>().toList();
    }

    return EventModel(
      id: doc.id,
      title: data['title'] ?? '',
      category: data['category'] ?? '',
      description: data['description'] ?? '',
      videoUrl: data['videoUrl'] as String?,
      imageUrl: data['imageUrl'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 22.4707,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 91.7877,
      eventDate: eventDate,
      registrationDeadline:
          (data['registrationDeadline'] as Timestamp?)?.toDate() ?? eventDate,
      isOpen: data['isOpen'] ?? true,
      likes: readUserIds('likes'),
      dislikes: readUserIds('dislikes'),
      ratings: ratingsData.map(
        (userId, rating) => MapEntry(userId, (rating as num).toDouble()),
      ),
      documentSnapshot: doc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'description': description,
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'eventDate': Timestamp.fromDate(eventDate),
      'registrationDeadline': Timestamp.fromDate(registrationDeadline),
      'isOpen': isOpen,
      'likes': List<String>.from(likes),
      'dislikes': List<String>.from(dislikes),
      'ratings': ratings,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
