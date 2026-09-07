import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/student_model.dart';
import '../models/attendance_model.dart';
import '../services/location_service.dart';
import '../services/mail_service.dart';

class AttendanceScreen extends StatefulWidget {
  final StudentModel student;

  const AttendanceScreen({super.key, required this.student});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final LocationService _locationService = LocationService();
  bool _isMarking = true;
  String _locationAddress = 'Locating...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Mark attendance in the background
    _markAttendance();
  }

  Future<void> _markAttendance() async {
    // Capture time immediately — before any async work
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final studentName = widget.student.name;
    final parentEmail = widget.student.parentEmail;
    final studentId = widget.student.studentId;
    final driverUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      Position? position = await _locationService.getCurrentLocation();
      final address = position != null
          ? await _locationService.getAddressFromCoordinates(
              position.latitude, position.longitude)
          : 'Location unavailable';

      if (mounted) setState(() { _locationAddress = address; });

      // Fire-and-forget: screen may already be popped, so don't await
      final docRef = FirebaseFirestore.instance.collection('attendance').doc();
      docRef.set({
        'id': docRef.id,
        'studentId': studentId,
        'studentName': studentName,
        'driverUid': driverUid,
        'timestamp': Timestamp.now(),
        'locationAddress': address,
        'location': position != null
            ? GeoPoint(position.latitude, position.longitude)
            : null,
        'status': 'present',
      });

      // Mail also fire-and-forget — context-free
      MailService.sendDepartureAlert(
        studentName: studentName,
        parentEmail: parentEmail,
        stopName: address,
      );

      if (mounted) setState(() { _isMarking = false; });
    } catch (e) {
      debugPrint('[Attendance] Error: $e');
      if (mounted) setState(() { _isMarking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Attendance', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset("assets/background.jpg", fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.45)),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),

                  // Departed heading
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.directions_bus_rounded, color: Colors.greenAccent, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Student Departed.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Student photo + name glass card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.6), width: 3),
                              ),
                              child: CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                backgroundImage: widget.student.getProfileImage() as ImageProvider?,
                                child: widget.student.getProfileImage() == null
                                    ? const Icon(Icons.person, size: 70, color: Colors.white70)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              widget.student.name,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Admission: ${widget.student.rollNumber}',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.75),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Status card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                        ),
                        child: _isMarking
                            ? Column(
                                children: [
                                  const CircularProgressIndicator(color: Colors.white),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Verifying Location & Marking...',
                                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 15),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              )
                            : _errorMessage != null
                                ? Column(
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Error: $_errorMessage',
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 60),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Attendance Marked!',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on, color: Colors.white70, size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _locationAddress,
                                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, _locationAddress);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                        ),
                      ),
                      child: const Text(
                        'Next Student',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
