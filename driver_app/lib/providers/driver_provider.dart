import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverProvider extends ChangeNotifier {
  String _name = '';
  String _busNumber = '';
  String _route = '';
  String _email = '';
  String _phone = '';
  String _status = '';
  String _assignedBusId = '';
  bool _isLoading = false;

  String get name => _name;
  String get busNumber => _busNumber;
  String get route => _route;
  String get email => _email;
  String get phone => _phone;
  String get status => _status;
  String get assignedBusId => _assignedBusId;
  bool get isLoading => _isLoading;

  Future<void> fetchDriverData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      debugPrint("Fetching driver data for UID: ${user.uid} at drivers/${user.uid}");
      DocumentSnapshot? driverDoc;

      final docById = await FirebaseFirestore.instance.collection('drivers').doc(user.uid).get();
      if (docById.exists) {
        driverDoc = docById;
      } else {
        // Fallback to checking email
        final emailQuery = await FirebaseFirestore.instance
            .collection('drivers')
            .where('email', isEqualTo: user.email)
            .limit(1)
            .get();
        if (emailQuery.docs.isNotEmpty) {
          driverDoc = emailQuery.docs.first;
        } else {
          // Fallback to checking uid field
          final uidQuery = await FirebaseFirestore.instance
              .collection('drivers')
              .where('uid', isEqualTo: user.uid)
              .limit(1)
              .get();
          if (uidQuery.docs.isNotEmpty) {
            driverDoc = uidQuery.docs.first;
          }
        }
      }

      if (driverDoc != null && driverDoc.exists) {
        final data = driverDoc.data() as Map<String, dynamic>;
        _name = data['name']?.toString() ?? 'No Name Set';
        _email = data['email']?.toString() ?? 'No Email';
        _phone = data['phone']?.toString() ?? 'No Phone';
        _status = data['status']?.toString() ?? 'Unknown Status';
        _assignedBusId = data['assigned_bus_id']?.toString() ?? '';
        
        if (_assignedBusId.isNotEmpty) {
          try {
            final busDoc = await FirebaseFirestore.instance
                .collection('buses')
                .doc(_assignedBusId)
                .get();
                
            if (busDoc.exists && busDoc.data() != null) {
              final busData = busDoc.data()!;
              _busNumber = busData['bus_number']?.toString() ?? 'No Bus Assigned';
              _route = busData['name']?.toString() ?? busData['route_name']?.toString() ?? 'No Route Assigned';
            } else {
              _busNumber = 'Bus Not Found';
              _route = 'Route Not Found';
            }
          } catch (e) {
            debugPrint("Failed to fetch assigned bus doc: $e");
            _busNumber = 'Error Fetching Bus';
            _route = 'Error Fetching Route';
          }
        } else {
          _busNumber = 'No Bus Assigned';
          _route = 'No Route Assigned';
        }
      } else {
        _name = 'Unregistered Driver';
        _busNumber = 'Register under:';
        _route = 'drivers/${user.uid}';
      }
    } catch (e) {
      debugPrint("Error fetching driver data: $e");
      _name = 'Error fetching details';
      _busNumber = 'N/A';
      _route = 'N/A';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearData() {
    _name = '';
    _busNumber = '';
    _route = '';
    _email = '';
    _phone = '';
    _status = '';
    _assignedBusId = '';
    notifyListeners();
  }
}
