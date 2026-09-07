import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student_model.dart';

class ParentProvider extends ChangeNotifier {
  StudentModel? _linkedStudent;
  bool _isLoading = false;

  StudentModel? get linkedStudent => _linkedStudent;
  bool get isLoading => _isLoading;

  /// Fetches the student linked to the provided parent email and password.
  /// This serves as the login + data fetch for parents.
  Future<bool> loginAndFetchData(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('parent_email', isEqualTo: email.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        
        // Verify password locally to avoid requiring a composite index in Firestore
        if (data['parent_password'] == password.trim() || data['password'] == password.trim()) {
          _linkedStudent = StudentModel.fromMap(doc.id, data);
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          debugPrint("Password mismatch.");
          _isLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint("Error fetching parent data: $e");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearData() {
    _linkedStudent = null;
    notifyListeners();
  }
}
