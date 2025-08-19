part of 'phone_auth_cubit.dart';

class PhoneAuthState extends Equatable {
  final Map<String, String> fields;
  final Map<String, String?> errors;
  final String statusMessage;
  final bool isCodeSent;
  final String? phoneNumber;
  final String? verificationId; // Added for Firebase OTP verification

  const PhoneAuthState({
    this.fields = const {
      'name': '',
      'phone': '',
      'address': '',
      'age': '',
      'vehicle': '',
    },
    this.errors = const {},
    this.statusMessage = '',
    this.isCodeSent = false,
    this.phoneNumber,
    this.verificationId,
  });

  PhoneAuthState copyWith({
    Map<String, String>? fields,
    Map<String, String?>? errors,
    String? statusMessage,
    bool? isCodeSent,
    String? phoneNumber,
    String? verificationId,
  }) {
    return PhoneAuthState(
      fields: fields ?? this.fields,
      errors: errors ?? this.errors,
      statusMessage: statusMessage ?? this.statusMessage,
      isCodeSent: isCodeSent ?? this.isCodeSent,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationId: verificationId ?? this.verificationId,
    );
  }

  @override
  List<Object?> get props => [fields, errors, statusMessage, isCodeSent, phoneNumber, verificationId];
}