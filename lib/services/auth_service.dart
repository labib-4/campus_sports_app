import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Sign Up with Email
  Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
    required String studentId,
    required String department,
  }) async {
    try {
      UserCredential res = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (res.user != null) {
        UserModel newUser = UserModel(
          uid: res.user!.uid,
          studentId: studentId,
          department: department,
          emailOrPhone: email,
        );

        // Save user info in Firestore database
        await _db.collection('users').doc(res.user!.uid).set(newUser.toMap());
      }
      return res;
    } catch (e) {
      rethrow;
    }
  }

  // Sign In with Email
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}