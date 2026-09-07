import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceModel {
  final String? id;
  final String studentId;
  final String studentName;
  final String driverUid;
  final Timestamp timestamp;
  final GeoPoint location;
  final String locationAddress;
  final String status;

  AttendanceModel({
    this.id,
    required this.studentId,
    required this.studentName,
    required this.driverUid,
    required this.timestamp,
    required this.location,
    required this.locationAddress,
    required this.status,
  });

  factory AttendanceModel.fromMap(String documentId, Map<String, dynamic> data) {
    return AttendanceModel(
      id: documentId,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      driverUid: data['driverUid'] ?? '',
      timestamp: data['timestamp'] as Timestamp,
      location: data['location'] as GeoPoint,
      locationAddress: data['locationAddress'] ?? '',
      status: data['status'] ?? 'present',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentName': studentName,
      'driverUid': driverUid,
      'timestamp': timestamp,
      'location': location,
      'locationAddress': locationAddress,
      'status': status,
    };
  }
}
