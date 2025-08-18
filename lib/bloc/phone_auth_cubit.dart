import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:phone_authentication/core/validators.dart';

part 'phone_auth_state.dart';

class PhoneAuthCubit extends Cubit<PhoneAuthState> {
  PhoneAuthCubit() : super(const PhoneAuthState());

  void updateField(String key, String value) {
    final fields = Map<String, String>.from(state.fields)..[key] = value;
    emit(state.copyWith(fields: fields, errors: {}, statusMessage: ''));
  }

  void submitForm() {
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
      emit(state.copyWith(
        isCodeSent: true,
        statusMessage: 'Verification code sent!',
        errors: {},
        phoneNumber: '+91$phoneNumber',
      ));
    } else {
      emit(state.copyWith(
        errors: errors,
        statusMessage: 'Please correct the errors in the form',
      ));
    }
  }
}