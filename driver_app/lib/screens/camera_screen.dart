import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:ui';
import '../utils/page_transitions.dart';
import '../models/student_model.dart';
import '../services/face_recognition_service.dart';
import 'attendance_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  final FaceRecognitionService _faceRecognitionService = FaceRecognitionService();

  bool _isDetecting = false;
  bool _isProcessingFace = false;
  bool _isInitialized = false;
  bool _isShowingResult = false;
  bool _isFaceCentered = false;
  bool _isEndingSession = false;

  // Multi-frame confirmation — prevents single-frame false positives
  int _consecutiveMatchCount = 0;
  String? _lastMatchedStudentId;
  Size _screenSize = Size.zero;

  List<StudentModel> _students = [];
  Rect? _faceBoundingBox;
  Size? _imageSize;
  InputImageRotation? _imageRotation;
  String _scanStatus = "Scanning for faces...";
  late AnimationController _shakeController;
  bool _isMatch = false;
  final List<Map<String, dynamic>> _markedInSession = [];

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _faceRecognitionService.initialize();
    await _fetchStudents();
    await _initializeCamera();
  }

  Future<void> _fetchStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('students').get();
      setState(() {
        _students = snapshot.docs.map((doc) => StudentModel.fromMap(doc.id, doc.data())).toList();
      });
      debugPrint("Fetched ${_students.length} students from Firestore.");
    } catch (e) {
      debugPrint("Error fetching students: $e");
    }
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    // Use front camera
    final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);

    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS 
          ? ImageFormatGroup.bgra8888 
          : ImageFormatGroup.nv21,
    );

    await _cameraController?.initialize();
    if (!mounted) return;

    setState(() {
      _isInitialized = true;
    });

    _cameraController?.startImageStream((CameraImage image) {
      if (!_isDetecting && !_isProcessingFace) {
        _isDetecting = true;
        _processCameraImage(image);
      }
    });
  }

  Future<void> _processCameraImage(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final camera = _cameraController!.description;
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation90deg;
      
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ?? 
          (defaultTargetPlatform == TargetPlatform.iOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21);
      
      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        
        bool isCentered = false;
        if (_screenSize != Size.zero) {
           bool isPortrait = imageRotation == InputImageRotation.rotation90deg || imageRotation == InputImageRotation.rotation270deg;
           Size absoluteImageSize = Size(
             isPortrait ? imageSize.height : imageSize.width,
             isPortrait ? imageSize.width : imageSize.height,
           );
           double scaleX = _screenSize.width / absoluteImageSize.width;
           double scaleY = _screenSize.height / absoluteImageSize.height;
           
           double left = _screenSize.width - (face.boundingBox.right * scaleX);
           double top = face.boundingBox.top * scaleY;
           double width = face.boundingBox.width * scaleX;
           double height = face.boundingBox.height * scaleY;
           
           double faceCenterX = left + width / 2;
           double faceCenterY = top + height / 2;
           double screenCenterX = _screenSize.width / 2;
           double screenCenterY = _screenSize.height / 2;
           
           double distance = sqrt(pow(faceCenterX - screenCenterX, 2) + pow(faceCenterY - screenCenterY, 2));
           if (distance < 120) { 
             isCentered = true;
           }
        }

        if (!mounted || _isEndingSession) return;
        setState(() {
          _faceBoundingBox = face.boundingBox;
          _imageSize = imageSize;
          _imageRotation = imageRotation;
          _isFaceCentered = isCentered;
        });

        if (!_isProcessingFace && !_isShowingResult && !_isEndingSession) {
          if (isCentered) {
            // --- Head pose quality filter ---
            final double? yaw   = face.headEulerAngleY;
            final double? pitch = face.headEulerAngleX;
            if (yaw != null && yaw.abs() > 20) {
              if (mounted) setState(() => _scanStatus = "Look straight at the camera");
              _isDetecting = false;
              return;
            }
            if (pitch != null && pitch.abs() > 15) {
              if (mounted) setState(() => _scanStatus = "Hold your face level");
              _isDetecting = false;
              return;
            }
            _isProcessingFace = true;
            if (mounted) {
              setState(() {
                _scanStatus = "Scanning face...";
              });
            }
            // Yield to UI thread to paint the scanning feedback
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted || _isEndingSession) return;
            await _recognizeFace(image, face);
          } else {
            if (mounted) {
              setState(() {
                _scanStatus = "Center your face in the circle";
              });
            }
          }
        }
      } else {
        if (mounted && !_isEndingSession) {
          setState(() {
            _faceBoundingBox = null;
            _isFaceCentered = false;
            if (!_isShowingResult) {
              _scanStatus = "Scanning for faces...";
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error processing camera image: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
        });
      }
    }
  }
  void _restartScanning() {
    if (!mounted) return;
    _consecutiveMatchCount = 0;
    _lastMatchedStudentId = null;
    setState(() {
      _isDetecting = false;
      _isProcessingFace = false;
      _isShowingResult = false;
      _isMatch = false;
      _isFaceCentered = false;
      _faceBoundingBox = null;
      _scanStatus = "Scanning for faces...";
    });
    // Guard: only start if the stream is not already running
    if (_cameraController != null && _cameraController!.value.isInitialized &&
        !_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream((CameraImage image) {
        if (!_isDetecting && !_isProcessingFace) {
          _isDetecting = true;
          _processCameraImage(image);
        }
      });
    }
  }

  Future<void> _recognizeFace(CameraImage cameraImage, Face face) async {
    try {
      img.Image? convertedImage = _convertCameraImage(cameraImage);
      if (convertedImage == null) {
        _isProcessingFace = false;
        return;
      }

      // Need to adjust rotation since the convert function brings it incorrectly oriented depending on sensor rotation
      int sensorOrientation = _cameraController!.description.sensorOrientation;
      if (sensorOrientation != 0) {
        convertedImage = img.copyRotate(convertedImage, angle: sensorOrientation);
      }

      final embedding = _faceRecognitionService.generateFaceEmbedding(convertedImage, face);
      
      if (embedding.isNotEmpty) {
        debugPrint("===============================");
        debugPrint("NEW EMBEDDING GENERATED FOR YOU:");
        debugPrint(embedding.toString());
        debugPrint("===============================");

        // --- Find best AND second-best match ---
        StudentModel? matchedStudent;
        double maxSimilarity = 0.0;
        double secondSimilarity = 0.0;

        for (var student in _students) {
          if (student.embedding.isNotEmpty) {
            double similarity = _faceRecognitionService.cosineSimilarity(embedding, student.embedding);
            debugPrint("  ${student.name}: ${similarity.toStringAsFixed(3)}");
            if (similarity > maxSimilarity) {
              secondSimilarity = maxSimilarity;
              maxSimilarity = similarity;
              matchedStudent = student;
            } else if (similarity > secondSimilarity) {
              secondSimilarity = similarity;
            }
          }
        }

        final double margin = maxSimilarity - secondSimilarity;
        debugPrint("Best: ${matchedStudent?.name} = ${maxSimilarity.toStringAsFixed(3)}, margin: ${margin.toStringAsFixed(3)}");

        // Threshold: 0.65 (genuine pairs) + margin ≥ 0.08 (not ambiguous)
        final bool isGoodMatch = maxSimilarity >= 0.50 &&
            (secondSimilarity == 0.0 || margin >= 0.08) &&
            matchedStudent != null;

        if (isGoodMatch) {
          // Multi-frame confirmation: require 2 consecutive frames for same student
          if (_lastMatchedStudentId == matchedStudent!.studentId) {
            _consecutiveMatchCount++;
          } else {
            _lastMatchedStudentId = matchedStudent.studentId;
            _consecutiveMatchCount = 1;
          }

          if (_consecutiveMatchCount >= 2) {
            // Confirmed match!
            _consecutiveMatchCount = 0;
            _lastMatchedStudentId = null;
            _cameraController?.stopImageStream();
            setState(() {
              _scanStatus = "Matched! Marking attendance...";
              _isShowingResult = true;
              _isMatch = true;
            });
            _shakeController.forward(from: 0);
            await Future.delayed(const Duration(milliseconds: 800));
            if (mounted) {
              final stopAddress = await Navigator.push(context, zoomRoute(AttendanceScreen(student: matchedStudent)));
              if (!_markedInSession.any((s) => (s['student'] as StudentModel).studentId == matchedStudent!.studentId)) {
                _markedInSession.add({
                  'student': matchedStudent,
                  'stop': (stopAddress is String && stopAddress.isNotEmpty) ? stopAddress : 'Unknown location',
                });
              }
              _restartScanning();
            }
          } else {
            // First frame match — wait for confirmation
            if (mounted) setState(() => _scanStatus = "Hold still... confirming");
          }
        } else {
          _consecutiveMatchCount = 0;
          _lastMatchedStudentId = null;
          debugPrint("Failed match. Best: ${maxSimilarity.toStringAsFixed(3)}, margin: ${margin.toStringAsFixed(3)}");
          if (mounted) {
            setState(() {
              _scanStatus = "Not recognized (${maxSimilarity.toStringAsFixed(2)}). Try again.";
              _isShowingResult = true;
              _isMatch = false;
            });
            _shakeController.forward(from: 0);
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() {
                  _isShowingResult = false;
                  _scanStatus = "Scanning for faces...";
                });
              }
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _scanStatus = "Error: Invalid mobilefacenet.tflite model!";
            _isShowingResult = true;
          });
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _isShowingResult = false;
                _scanStatus = "Scanning for faces...";
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error in face recognition: $e");
    } finally {
      _isProcessingFace = false;
    }
  }

  img.Image? _convertCameraImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.yuv420 || image.format.group == ImageFormatGroup.nv21) {
      return _convertYUV420(image);
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(image);
    }
    return null;
  }

  img.Image _convertYUV420(CameraImage image) {
    final width = image.width;
    final height = image.height;
    var imgOutput = img.Image(width: width, height: height);

    if (image.planes.length == 1) {
      final bytes = image.planes[0].bytes;
      final int size = width * height;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;
          if (yIndex < bytes.length) {
            final int yValue = bytes[yIndex];
            int uValue = 128;
            int vValue = 128;

            final int uvIndex = size + (y >> 1) * width + (x & ~1);
            if (uvIndex + 1 < bytes.length) {
              vValue = bytes[uvIndex];
              uValue = bytes[uvIndex + 1];
            }

            int r = (yValue + 1.402 * (vValue - 128)).toInt();
            int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).toInt();
            int b = (yValue + 1.772 * (uValue - 128)).toInt();

            imgOutput.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
          }
        }
      }
      return imgOutput;
    }

    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      int pY = y * image.planes[0].bytesPerRow;
      int pUV = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        int uvOffset = pUV + (x >> 1) * uvPixelStride;

        final yValue = image.planes[0].bytes[pY];
        final uValue = image.planes[1].bytes[uvOffset];
        final vValue = image.planes[2].bytes[uvOffset];

        int r = (yValue + 1.402 * (vValue - 128)).toInt();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).toInt();
        int b = (yValue + 1.772 * (uValue - 128)).toInt();

        imgOutput.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
        pY++;
      }
    }
    return imgOutput;
  }

  img.Image _convertBGRA8888(CameraImage image) {
    final width = image.width;
    final height = image.height;
    var imgOutput = img.Image(width: width, height: height);
    final bytes = image.planes[0].bytes;
    
    int index = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final b = bytes[index++];
        final g = bytes[index++];
        final r = bytes[index++];
        final a = bytes[index++];
        imgOutput.setPixelRgba(x, y, r, g, b, a);
      }
    }
    return imgOutput;
  }

  void _showSessionSummary() async {
    // Prevent re-entry
    if (_isEndingSession) return;

    // Stop the image stream while showing summary
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }

    if (_markedInSession.isEmpty) {
      // Nothing scanned yet — confirm exit
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('No Attendance Marked',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'No students have been scanned yet. Do you want to stop the session?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, 'cancel');
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, 'stop');
              },
              child: const Text('Stop', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      
      if (result == 'stop') {
        await _cleanupCameraBeforeExit();
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted) Navigator.pop(context, _markedInSession);
          });
        }
      } else {
        if (mounted) _restartScanning();
      }
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Session Summary',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${_markedInSession.length} student${_markedInSession.length == 1 ? '' : 's'} marked present',
                                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Column headers
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              flex: 3,
                              child: Text('Student Name',
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                            ),
                            const Expanded(
                              flex: 2,
                              child: Text('Roll No.',
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text('Stop',
                                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                  textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // List
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _markedInSession.length,
                          separatorBuilder: (_, __) => Divider(
                            color: Colors.white.withOpacity(0.08),
                            height: 1,
                          ),
                          itemBuilder: (_, index) {
                            final entry = _markedInSession[index];
                            final student = entry['student'] as StudentModel;
                            final stop = entry['stop'] as String;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: index.isEven
                                    ? Colors.white.withOpacity(0.04)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Avatar + name
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: Colors.white.withOpacity(0.12),
                                          backgroundImage: student.getProfileImage() as ImageProvider?,
                                          child: student.getProfileImage() == null
                                              ? const Icon(Icons.person, size: 18, color: Colors.white70)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            student.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Roll no
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      student.rollNumber,
                                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13),
                                    ),
                                  ),
                                  // Stop location
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      stop,
                                      style: TextStyle(
                                        color: Colors.greenAccent.withOpacity(0.85),
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      // Done button
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx, 'stop');
                            },
                            icon: const Icon(Icons.done_all_rounded, size: 20),
                            label: const Text(
                              'Done — End Session',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == 'stop') {
      await _cleanupCameraBeforeExit();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, _markedInSession);
        });
      }
    } else {
      if (mounted) _restartScanning();
    }
  }

  /// Stop the image stream BEFORE popping the screen to avoid native
  /// buffer queue overload and crashes during the OpenContainer animation.
  /// We leave the CameraController active so the fade animation can complete safely.
  Future<void> _cleanupCameraBeforeExit() async {
    _isEndingSession = true;
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } catch (e) {
      debugPrint('Camera cleanup error: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              "assets/background.jpg",
              fit: BoxFit.cover,
            ),
            Container(color: Colors.black.withOpacity(0.3)),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    _screenSize = size;

    return Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Scan Face', style: TextStyle(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: TextButton.icon(
                onPressed: _showSessionSummary,
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 20),
                label: const Text('Stop', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image for letterboxing
            Image.asset(
            "assets/background.jpg",
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withOpacity(0.3)),
          
          // Fix Aspect Ratio
          ClipRect(
            child: Transform.scale(
              scale: _cameraController!.value.aspectRatio * size.aspectRatio < 1
                  ? 1 / (_cameraController!.value.aspectRatio * size.aspectRatio)
                  : (_cameraController!.value.aspectRatio * size.aspectRatio),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / _cameraController!.value.aspectRatio,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),
          
          // Face Target Overlay
          Center(
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final sineValue = sin(6 * pi * _shakeController.value);
                final offset = _isShowingResult 
                    ? (_isMatch ? Offset(0, sineValue * 20) : Offset(sineValue * 20, 0))
                    : Offset.zero;
                return Transform.translate(
                  offset: offset,
                  child: child,
                );
              },
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _isShowingResult 
                        ? (_scanStatus.startsWith("Matched successfully") ? Colors.greenAccent : Colors.redAccent)
                        : (_isProcessingFace 
                            ? Colors.orangeAccent 
                            : (_isFaceCentered ? Colors.greenAccent : Colors.white.withOpacity(0.3))),
                    width: 5,
                  ),
                ),
              ),
            ),
          ),
          
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isProcessingFace)
                        const Padding(
                          padding: EdgeInsets.only(right: 12.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _scanStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
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
