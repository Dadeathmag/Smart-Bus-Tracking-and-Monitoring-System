import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class MailService {
  // ⚠️ IMPORTANT: To use this service securely without exposing your real password,
  // 1. Turn on 2-Step Verification for your Google Account.
  // 2. Go to Google Account Settings -> Security -> App passwords.
  // 3. Generate a 16-digit App Password and paste it below!
  static const String _gmailUsername = 'YOUR_EMAIL@gmail.com'; 
  static const String _gmailAppPassword = 'YOUR_16_DIGIT_APP_PASSWORD'; 

  /// Sends an email alert to the parent when attendance is marked.
  static Future<void> sendDepartureAlert({
    required String studentName,
    required String parentEmail,
    required String stopName,
  }) async {
    if (_gmailUsername == 'YOUR_EMAIL@gmail.com' || _gmailUsername.isEmpty) {
      debugPrint('[EMAIL] Email credentials not set. Skipping Mail.');
      return;
    }

    if (parentEmail.isEmpty || !parentEmail.contains('@')) {
      debugPrint('[EMAIL] Invalid parent email: $parentEmail');
      return;
    }

    final messageBody = 'Attendance marked for your student $studentName from $stopName';

    // Create the SMTP server connection for Gmail (SSL port 465)
    final smtpServer = gmail(_gmailUsername, _gmailAppPassword);

    // Build the email message
    final message = Message()
      ..from = Address(_gmailUsername, 'FaceIt! Attendance')
      ..recipients.add(parentEmail)
      ..subject = 'Attendance Marked: $studentName'
      ..text = messageBody;

    try {
      final sendReport = await send(message, smtpServer);
      debugPrint('[EMAIL] Sent successfully to $parentEmail - Status: ${sendReport.toString()}');
    } on MailerException catch (e) {
      debugPrint('[EMAIL] Message Failed: \n$e');
      for (var p in e.problems) {
        debugPrint('[EMAIL] Problem detail: ${p.code}: ${p.msg}');
      }
    } catch (e) {
      debugPrint('[EMAIL] Unexpected error dispatching MAIL: $e');
    }
  }
}
