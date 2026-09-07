import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognitionService {
  late Interpreter _interpreter;
  bool _isInitialized = false;

  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
      _isInitialized = true;
      debugPrint("TFLite Model Loaded Successfully.");
    } catch (e) {
      debugPrint("Error loading TFLite model: $e");
    }
  }

  List<double> generateFaceEmbedding(img.Image image, Face face) {
    if (!_isInitialized) {
      debugPrint("Interpreter not initialized");
      return [];
    }

    // Crop face from the original image
    final Rect boundingBox = face.boundingBox;
    
    int x = max(0, boundingBox.left.toInt());
    int y = max(0, boundingBox.top.toInt());
    int width = boundingBox.width.toInt();
    int height = boundingBox.height.toInt();
    
    if (x + width > image.width) width = image.width - x;
    if (y + height > image.height) height = image.height - y;

    img.Image croppedImage = img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );

    // Resize to 112x112 as expected by MobileFaceNet
    img.Image resizedImage = img.copyResize(croppedImage, width: 112, height: 112);

    // Preprocess: convert image to a 4D float array [1, 112, 112, 3]
    var input = _imageToByteListFloat32(resizedImage, 112, 127.5, 127.5).reshape([1, 112, 112, 3]);
    var output = List<double>.filled(192, 0).reshape([1, 192]);

    _interpreter.run(input, output);

    final rawEmbedding = List<double>.from(output[0]);
    return _l2Normalize(rawEmbedding);
  }

  /// Converts an img.Image instance to a 1D Float32List
  Float32List _imageToByteListFloat32(img.Image image, int inputSize, double mean, double std) {
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixelSafe(j, i);
        buffer[pixelIndex++] = (pixel.r - mean) / std;
        buffer[pixelIndex++] = (pixel.g - mean) / std;
        buffer[pixelIndex++] = (pixel.b - mean) / std;
      }
    }
    return convertedBytes.buffer.asFloat32List();
  }

  double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
    if (vectorA.length != vectorB.length || vectorA.isEmpty) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vectorA.length; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      normA += vectorA[i] * vectorA[i];
      normB += vectorB[i] * vectorB[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// L2-normalizes a vector so its magnitude = 1.
  /// MobileFaceNet embeddings must be unit-vectors for cosine similarity
  /// to produce reliable, threshold-stable scores.
  List<double> _l2Normalize(List<double> vec) {
    double norm = sqrt(vec.fold(0.0, (sum, v) => sum + v * v));
    if (norm == 0.0) return vec;
    return vec.map((v) => v / norm).toList();
  }
}
