import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/core/validators.dart';

part 'profile_state.dart';

class PhoneAuthCubit extends Cubit<PhoneAuthState> {
  PhoneAuthCubit() : super(const PhoneAuthState()) {
    _checkAuthState(); // Check auth state on initialization
  }

  void _checkAuthState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      emit(state.copyWith(
        user: user,
        statusMessage: 'Authenticated',
        isCodeSent: false,
        phoneNumber: null,
        verificationId: null,
      ));
    }
  }

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    final errors = Map<String, String?>.from(state.errors);
    errors[key] = validateField(key, value);
    emit(state.copyWith(fields: fields, errors: errors));
  }

  void submitForm() async {
    final fields = state.fields;
    final errors = <String, String?>{};
    bool hasError = false;

    fields.forEach((key, value) {
      final error = validateField(key, value);
      errors[key] = error;
      if (error != null) hasError = true;
    });

    if (hasError) {
      emit(state.copyWith(errors: errors, statusMessage: 'Please fix the errors in the form.'));
      return;
    }

    final phoneNumber = fields['phone']!.startsWith('+91')
        ? fields['phone']!
        : '+91${fields['phone']}';

    try {
      emit(state.copyWith(statusMessage: 'Sending verification code...'));

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await _saveUserDataToFirestore(user.uid);
            emit(state.copyWith(
              user: user,
              statusMessage: 'Authentication successful',
              isCodeSent: false,
              phoneNumber: null,
              verificationId: null,
            ));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          emit(state.copyWith(
            statusMessage: 'Error: ${e.message}',
            isCodeSent: false,
            phoneNumber: null,
            verificationId: null,
          ));
        },
        codeSent: (String verificationId, int? resendToken) {
          emit(state.copyWith(
            isCodeSent: true,
            phoneNumber: phoneNumber,
            verificationId: verificationId,
            statusMessage: 'Verification code sent to $phoneNumber',
          ));
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      emit(state.copyWith(statusMessage: 'Error: $e'));
    }
  }

  void verifyOtp(String smsCode, String verificationId, BuildContext context) async {
    try {
      emit(state.copyWith(statusMessage: 'Verifying OTP...'));

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        await _saveUserDataToFirestore(user.uid);
        emit(state.copyWith(
          user: user,
          statusMessage: 'Authentication successful',
          isCodeSent: false,
          phoneNumber: null,
          verificationId: null,
        ));
        context.go('/home');
      } else {
        emit(state.copyWith(statusMessage: 'Error: Authentication failed'));
      }
    } catch (e) {
      emit(state.copyWith(statusMessage: 'Error: $e'));
    }
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      emit(const PhoneAuthState(
        statusMessage: 'Logged out',
        isCodeSent: false,
        phoneNumber: null,
        verificationId: null,
        user: null,
      ));
    } catch (e) {
      emit(state.copyWith(statusMessage: 'Error logging out: $e'));
    }
  }

  Future<void> _saveUserDataToFirestore(String uid) async {
    try {
      final driverRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
      await driverRef.set({
        'name': state.fields['name'] ?? '',
        'phone': state.fields['phone'] ?? '',
        'address': state.fields['address'] ?? '',
        'age': state.fields['age'] ?? '',
        'vehicle': state.fields['vehicle'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving to Firestore: $e');
      emit(state.copyWith(statusMessage: 'Error saving data: $e'));
    }
  }
}