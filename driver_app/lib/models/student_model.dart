import 'dart:convert';
import 'package:flutter/material.dart';

class StudentModel {
  final String studentId;
  final String name;
  final String rollNumber;
  final String className;
  final String photoUrl;
  final String photoBase64;
  final String parentPhoneNumber;
  final String parentEmail;
  final String parentName;
  final String routeName;
  final String busId;
  final String busNo;
  final int totalFee;
  final List<double> embedding;

  StudentModel({
    required this.studentId,
    required this.name,
    required this.rollNumber,
    required this.className,
    required this.photoUrl,
    this.photoBase64 = '',
    this.parentPhoneNumber = '',
    this.parentEmail = '',
    this.parentName = '',
    this.routeName = '',
    this.busId = '',
    this.busNo = '',
    this.totalFee = 0,
    required this.embedding,
  });

  factory StudentModel.fromMap(String id, Map<String, dynamic> data) {
    return StudentModel(
      studentId: id,
      name: data['name'] ?? '',
      rollNumber: data['admission_number']?.toString() ?? data['rollNumber'] ?? '',
      className: data['class'] ?? 'N/A',
      photoUrl: data['photo_path'] ?? data['photoUrl'] ?? '',
      photoBase64: data['photoBase64'] ?? '',
      parentPhoneNumber: data['parent_phone_number']?.toString() ?? '',
      parentEmail: data['parent_email']?.toString() ?? '',
      parentName: data['parent_name']?.toString() ?? '',
      routeName: data['routes']?['morning']?['stop_name']?.toString() ?? data['routes']?['evening']?['stop_name']?.toString() ?? 'N/A',
      busId: data['bus_id']?.toString() ?? '',
      busNo: data['bus_no']?.toString() ?? '',
      totalFee: int.tryParse(data['total_fee']?.toString() ?? '') ?? int.tryParse(data['routes']?['total_fee']?.toString() ?? '') ?? 0,
      embedding: (data['embedding'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'rollNumber': rollNumber,
      'class': className,
      'photoUrl': photoUrl,
      'photoBase64': photoBase64,
      'embedding': embedding,
    };
  }

  ImageProvider? getProfileImage() {
    // The method uses base64Decode and MemoryImage if base64 is present
    if (photoBase64.isNotEmpty) {
       try {
         String b64 = photoBase64;
         if (b64.contains(',')) {
           b64 = b64.split(',')[1];
         }
         return MemoryImage(base64Decode(b64.trim()));
       } catch(e) { /* Fallback */ }
    }
    
    if (photoUrl.isNotEmpty && photoUrl.startsWith('http')) {
      return NetworkImage(photoUrl);
    }
    
    return null;
  }
}

