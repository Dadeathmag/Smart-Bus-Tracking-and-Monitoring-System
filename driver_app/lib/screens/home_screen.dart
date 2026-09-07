import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../utils/page_transitions.dart';
import '../widgets/animated_button.dart';
import '../providers/driver_provider.dart';
import 'login_screen.dart';
import 'camera_screen.dart';
import 'package:animations/animations.dart';
import '../models/student_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<StudentModel> _lastSessionStudents = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DriverProvider>(context, listen: false).fetchDriverData();
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Provider.of<DriverProvider>(context, listen: false).clearData();
      Navigator.of(context).pushReplacement(fadeRoute(const LoginScreen()));
    }
  }

  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  void _showSummaryDialog(List<StudentModel> markedStudents) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.fact_check, color: Colors.greenAccent, size: 28),
              SizedBox(width: 12),
              Text('Session Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: markedStudents.length,
              itemBuilder: (context, index) {
                final student = markedStudents[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage: student.getProfileImage() as ImageProvider?,
                    child: student.getProfileImage() == null
                        ? const Icon(Icons.person, color: Colors.white70)
                        : null,
                  ),
                  title: Text(student.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('Roll No: ${student.rollNumber}', style: const TextStyle(color: Colors.white70)),
                  trailing: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverData = Provider.of<DriverProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.account_circle, size: 28),
          tooltip: 'Driver Details',
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.black.withOpacity(0.85),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
                ),
                title: const Row(
                  children: [
                    Icon(Icons.account_circle, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Text('Driver Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Name: ${driverData.name.isEmpty ? "Unknown" : driverData.name}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 12),
                    Text('Email: ${driverData.email.isEmpty ? "Unknown" : driverData.email}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('Phone: ${driverData.phone.isEmpty ? "Unknown" : driverData.phone}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('Status: ${driverData.status.isEmpty ? "Unknown" : driverData.status}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 16),
                    const Text('Assigned Bus Details', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Bus: ${driverData.busNumber.isEmpty ? "Unassigned" : driverData.busNumber}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('Route: ${driverData.route.isEmpty ? "No Route" : driverData.route}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        ),
        title: const Text('FaceIt! Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset(
            "assets/background.jpg",
            fit: BoxFit.cover,
          ),
          
          // Dark overlay mapping
          Container(
            color: Colors.black.withOpacity(0.3),
          ),
          
          driverData.isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _getGreeting(),
                        style: const TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        driverData.name.isEmpty ? 'Driver' : driverData.name,
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 40),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.directions_bus, size: 40, color: Colors.white),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Active Bus', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(
                                        driverData.busNumber.isEmpty ? 'Not Assigned' : driverData.busNumber,
                                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('Current Route', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      Text(
                                        driverData.route.isEmpty ? 'No Route' : driverData.route,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      AnimatedButton(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const CameraScreen()),
                          );
                          
                          if (result is List) {
                            if (result.isNotEmpty) {
                              final students = result.map((e) => e['student'] as StudentModel).toList();
                              setState(() {
                                _lastSessionStudents = students;
                              });
                            } else {
                              setState(() {
                                _lastSessionStudents = [];
                              });
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('No students marked in this session.', style: TextStyle(color: Colors.white)),
                                    backgroundColor: Colors.black.withOpacity(0.8),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.camera_alt, size: 28, color: Colors.white),
                                  SizedBox(width: 12),
                                  Text(
                                    'START ATTENDANCE',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_lastSessionStudents.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        AnimatedButton(
                          onPressed: () => _showSummaryDialog(_lastSessionStudents),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.greenAccent.withOpacity(0.4), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.fact_check, size: 24, color: Colors.greenAccent),
                                    SizedBox(width: 12),
                                    Text(
                                      'VIEW LAST ATTENDANCE',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
