import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/page_transitions.dart';
import '../widgets/animated_button.dart';
import 'home_screen.dart';
import 'parent_dashboard_screen.dart';
import 'package:animations/animations.dart';
import 'package:provider/provider.dart';
import '../providers/parent_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isDriverRole = true; // true = Driver, false = Parent

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    if (!_isDriverRole) {
      // Parent Login Flow
      final success = await Provider.of<ParentProvider>(context, listen: false)
          .loginAndFetchData(_emailController.text, _passwordController.text);
      
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const ParentDashboardScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid parent credentials or student not found.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
      return;
    }

    // Driver Login Flow
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        bool isRegistered = false;
        
        final docById = await FirebaseFirestore.instance.collection('drivers').doc(user.uid).get();
        if (docById.exists) {
          isRegistered = true;
        } else {
          final emailQuery = await FirebaseFirestore.instance.collection('drivers').where('email', isEqualTo: user.email).limit(1).get();
          if (emailQuery.docs.isNotEmpty) {
            isRegistered = true;
          } else {
            final uidQuery = await FirebaseFirestore.instance.collection('drivers').where('uid', isEqualTo: user.uid).limit(1).get();
            if (uidQuery.docs.isNotEmpty) {
              isRegistered = true;
            }
          }
        }

        if (!isRegistered) {
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Access Denied: You are not registered as a driver.'),
                backgroundColor: Colors.redAccent,
              ),
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Authentication failed';
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        errorMessage = 'No user found for that email.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        errorMessage = 'Incorrect email or password.';
      } else if (e.code == 'network-request-failed') {
        errorMessage = 'Network error. Please check your connection.';
      } else {
        errorMessage = e.message ?? errorMessage;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Image.asset(
              _isDriverRole ? "assets/background.jpg" : "assets/bg.png",
              key: ValueKey<bool>(_isDriverRole),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          
          // Dark overlay to ensure text is readable
          Container(
            color: Colors.black.withOpacity(0.3),
          ),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_bus, size: 80, color: Colors.white),
                          const SizedBox(height: 16),
                          const Text(
                            'FaceIt!',
                            style: TextStyle(
                              fontSize: 32, 
                              fontWeight: FontWeight.bold, 
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            _isDriverRole ? 'Driver Portal' : 'Parent Portal',
                            style: const TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.w500, 
                              color: Colors.white70,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 30),
                          
                          // Role Toggle
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDriverRole = true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _isDriverRole ? Colors.white.withOpacity(0.2) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Driver',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _isDriverRole = false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: !_isDriverRole ? Colors.white.withOpacity(0.2) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Parent',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          
                          // Email Field
                          TextFormField(
                            controller: _emailController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(Icons.email, color: Colors.white),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white),
                              ),
                              errorStyle: const TextStyle(color: Colors.redAccent),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 20),
                          
                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.white70),
                              prefixIcon: const Icon(Icons.lock, color: Colors.white),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.white),
                              ),
                              errorStyle: const TextStyle(color: Colors.redAccent),
                            ),
                            obscureText: !_isPasswordVisible,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          
                          const SizedBox(height: 40),
                          
                          // Login Button
                          AnimatedButton(
                            onPressed: _isLoading ? () {} : _login,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                                  ),
                                  child: Center(
                                    child: _isLoading 
                                        ? const SizedBox(
                                            height: 24, 
                                            width: 24, 
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                          )
                                        : const Text(
                                            'LOGIN', 
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
