class UserModel {
  final String uid;
  final String studentId;
  final String department;
  final String emailOrPhone;
  final String role; // 'admin' অথবা 'user'

  UserModel({
    required this.uid,
    required this.studentId,
    required this.department,
    required this.emailOrPhone,
    this.role = 'user',
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'studentId': studentId,
      'department': department,
      'emailOrPhone': emailOrPhone,
      'role': role,
      'createdAt': DateTime.now(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      studentId: map['studentId'] ?? '',
      department: map['department'] ?? '',
      emailOrPhone: map['emailOrPhone'] ?? '',
      role: map['role'] ?? 'user',
    );
  }
}