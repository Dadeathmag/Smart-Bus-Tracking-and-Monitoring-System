import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../providers/parent_provider.dart';
import '../models/student_model.dart';
import 'login_screen.dart';
import '../utils/page_transitions.dart';

class ParentDashboardScreen extends StatelessWidget {
  const ParentDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final parentProvider = Provider.of<ParentProvider>(context);
    final student = parentProvider.linkedStudent;

    if (student == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Parent Portal', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              parentProvider.clearData();
              Navigator.pushReplacement(
                context, 
                PageRouteBuilder(
                  pageBuilder: (_,__,___) => const LoginScreen(),
                  transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
                )
              );
            },
          )
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            "assets/bg.png",
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          
          // Dark overlay
          Container(
            color: Colors.black.withOpacity(0.4),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'Welcome, ${student.parentName}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Profile Card
                  _buildGlassCard(
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                            image: student.getProfileImage() != null
                                ? DecorationImage(image: student.getProfileImage()!, fit: BoxFit.cover)
                                : null,
                          ),
                          child: student.getProfileImage() == null
                              ? const Icon(Icons.person, color: Colors.white70, size: 40)
                              : null,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Class: ${student.className} | Roll: ${student.rollNumber}',
                                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Live Attendance Status
                  const Text('Live Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('attendance')
                        .where('studentId', isEqualTo: student.studentId)
                        .orderBy('timestamp', descending: true)
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildGlassCard(
                          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                        );
                      }
                      
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildGlassCard(
                          child: Column(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.white70, size: 40),
                              const SizedBox(height: 12),
                              const Text(
                                'No attendance records yet',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }

                      final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                      final timestamp = (data['timestamp'] as Timestamp).toDate();
                      final address = data['locationAddress'] ?? 'Unknown location';
                      final timeStr = DateFormat('h:mm a').format(timestamp);
                      final dateStr = DateFormat('MMM d, yyyy').format(timestamp);

                      return _buildGlassCard(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 30),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Scanned on Bus',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$dateStr at $timeStr',
                                    style: const TextStyle(fontSize: 14, color: Colors.greenAccent, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, color: Colors.white70, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          address,
                                          style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
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

                  const SizedBox(height: 20),

                  // Bus & Driver Details
                  const Text('Transport Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance.collection('drivers')
                        .where('assigned_bus_id', isEqualTo: student.busId)
                        .limit(1)
                        .get(),
                    builder: (context, snapshot) {
                      String driverName = 'Loading...';
                      String busNumber = student.busNo.isNotEmpty ? student.busNo : 'N/A';
                      Map<String, dynamic>? driverData;

                      if (snapshot.connectionState == ConnectionState.done) {
                        if (snapshot.hasError) {
                          driverName = 'Error catching data';
                          // Hacky way to display error in UI for debug
                          busNumber = '${student.busNo} (Err: ${snapshot.error})';
                        } else if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                          driverData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                          driverName = driverData['name'] ?? 'Unknown Driver';
                        } else {
                          driverName = 'No Driver Found (Searched ID: "${student.busId}")';
                        }
                      }

                      return _buildGlassCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.directions_bus, color: Colors.white70, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bus #$busNumber',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Route: ${student.routeName}',
                                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Driver: $driverName',
                                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
                                  ),
                                  const SizedBox(height: 12),
                                  if (driverData != null)
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _showDriverDetailsDialog(context, driverData!),
                                        icon: const Icon(Icons.visibility, size: 18, color: Colors.white),
                                        label: const Text('View Full Details', style: TextStyle(color: Colors.white)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white.withOpacity(0.2),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          alignment: Alignment.centerLeft,
                                          elevation: 0,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      'Button hidden: No driver assigned to Bus ID ${student.busId} in the database.',
                                      style: TextStyle(fontSize: 12, color: Colors.redAccent.withOpacity(0.9), fontStyle: FontStyle.italic),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Fee Details
                  const Text('Fee Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  _buildGlassCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Term Fee',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${student.totalFee}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            // Placeholder status logic - assuming if total is > 0 it's billed
                            color: Colors.greenAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.greenAccent),
                          ),
                          child: const Text(
                            'PAID',
                            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  void _showDriverDetailsDialog(BuildContext context, Map<String, dynamic> driverData) {
    showDialog(
      context: context,
      builder: (context) {
        final photoBase64 = driverData['permit_photo_base64'] as String?;
        ImageProvider? photoProvider;
        if (photoBase64 != null && photoBase64.isNotEmpty) {
          try {
             String b64 = photoBase64;
             if (b64.contains(',')) {
               b64 = b64.split(',')[1];
             }
             photoProvider = MemoryImage(base64Decode(b64.trim()));
          } catch(e) { }
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Driver Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 20),
                    if (photoProvider != null)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                          image: DecorationImage(image: photoProvider, fit: BoxFit.cover),
                        ),
                      )
                    else
                      const Icon(Icons.drive_eta, size: 60, color: Colors.white70),
                    const SizedBox(height: 20),
                    _buildDetailRow('Name', driverData['name']?.toString() ?? 'N/A'),
                    const SizedBox(height: 10),
                    _buildDetailRow('Bus Number', driverData['bus_number']?.toString() ?? 'N/A'),
                    const SizedBox(height: 10),
                    _buildDetailRow('Status', (driverData['status']?.toString() ?? 'N/A').toUpperCase()),
                    const SizedBox(height: 10),
                    _buildDetailRow('Capacity', '${driverData['current_strength'] ?? 0} / ${driverData['student_limit'] ?? '?'}'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
