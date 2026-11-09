import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebasePhoneAuthService {
  FirebasePhoneAuthService(this._auth);

  final FirebaseAuth _auth;

  ConfirmationResult? _confirmationResult;
  String? _verificationId;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> requestOtp({required String phoneNumber}) async {
    if (kIsWeb) {
      _confirmationResult = await _auth.signInWithPhoneNumber(phoneNumber);
      return;
    }

    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        await _auth.signInWithCredential(credential);
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent: (verificationId, _) {
        _verificationId = verificationId;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );

    return completer.future;
  }

  Future<void> verifyOtp({required String smsCode}) async {
    if (kIsWeb) {
      final confirmationResult = _confirmationResult;
      if (confirmationResult == null) {
        throw StateError('otp_not_requested');
      }
      await confirmationResult.confirm(smsCode);
      return;
    }

    final verificationId = _verificationId;
    if (verificationId == null) {
      throw StateError('otp_not_requested');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    _confirmationResult = null;
    _verificationId = null;
    await _auth.signOut();
  }
}
