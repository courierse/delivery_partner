import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phone_authentication/core/validators.dart';

part 'phone_auth_state.dart';

class PhoneAuthCubit extends Cubit<PhoneAuthState> {
  PhoneAuthCubit() : super(const PhoneAuthState());

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    emit(state.copyWith(fields: fields, errors: {}, statusMessage: ''));
  }

  void submitForm() async {
    final errors = <String, String?>{};
    bool isValid = true;

    Validator.validators.forEach((key, validator) {
      final error = validator(state.fields[key]);
      if (error != null) {
        isValid = false;
        errors[key] = error;
      }
    });

    if (isValid) {
      final phoneNumber = state.fields['phone']!;
      final fullPhoneNumber = '+91$phoneNumber'; // Adjust country code if needed
      emit(state.copyWith(
        statusMessage: 'Sending OTP...',
        errors: {},
      ));

      try {
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: fullPhoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            // Auto-resolve on Android (if SMS read automatically)
            await _signInWithCredential(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            emit(state.copyWith(
              statusMessage: 'Error: ${e.message}',
              isCodeSent: false,
            ));
          },
          codeSent: (String verificationId, int? resendToken) {
            emit(state.copyWith(
              isCodeSent: true,
              verificationId: verificationId,
              phoneNumber: fullPhoneNumber,
              statusMessage: 'Verification code sent!',
            ));
          },
          codeAutoRetrievalTimeout: (String verificationId) {
            // Optional: Handle timeout
            emit(state.copyWith(verificationId: verificationId));
          },
          timeout: const Duration(seconds: 60),
        );
      } catch (e) {
        emit(state.copyWith(
          statusMessage: 'Error sending OTP: $e',
          isCodeSent: false,
        ));
      }
    } else {
      emit(state.copyWith(
        errors: errors,
        statusMessage: 'Please correct the errors in the form',
      ));
    }
  }

  Future<void> verifyOtp(String smsCode, String verificationId) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await _signInWithCredential(credential);
    } catch (e) {
      emit(state.copyWith(statusMessage: 'Error verifying OTP: $e'));
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      emit(state.copyWith(statusMessage: 'Authentication successful! User: ${userCredential.user?.uid}'));
      // Optional: Save user data to Firestore or navigate further
    } catch (e) {
      emit(state.copyWith(statusMessage: 'Error signing in: $e'));
    }
  }
}