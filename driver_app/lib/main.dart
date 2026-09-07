import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'providers/driver_provider.dart';
import 'providers/parent_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Force driver to login every time the app opens
  await FirebaseAuth.instance.signOut();

  // Request permissions at startup
  await [Permission.camera, Permission.location].request();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverProvider()),
        ChangeNotifierProvider(create: (_) => ParentProvider()),
      ],
      child: const FaceItApp(),
    ),
  );
}

class FaceItApp extends StatelessWidget {
  const FaceItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceIt!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}