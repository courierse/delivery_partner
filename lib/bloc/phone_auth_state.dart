part of 'phone_auth_cubit.dart';

class PhoneAuthState extends Equatable {
  final Map<String, String> fields;
  final Map<String, String?> errors;
  final String statusMessage;
  final bool isCodeSent;
  final String? phoneNumber;
  final String? verificationId;
  final User? user; // Added to track authenticated user

  const PhoneAuthState({
    this.fields = const {'name': '', 'phone': '', 'address': '', 'age': '', 'vehicle': ''},
    this.errors = const {'name': null, 'phone': null, 'address': null, 'age': null, 'vehicle': null},
    this.statusMessage = '',
    this.isCodeSent = false,
    this.phoneNumber,
    this.verificationId,
    this.user,
  });

  PhoneAuthState copyWith({
    Map<String, String>? fields,
    Map<String, String?>? errors,
    String? statusMessage,
    bool? isCodeSent,
    String? phoneNumber,
    String? verificationId,
    User? user,
  }) {
    return PhoneAuthState(
      fields: fields ?? this.fields,
      errors: errors ?? this.errors,
      statusMessage: statusMessage ?? this.statusMessage,
      isCodeSent: isCodeSent ?? this.isCodeSent,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationId: verificationId ?? this.verificationId,
      user: user ?? this.user,
    );
  }

  @override
  List<Object?> get props => [fields, errors, statusMessage, isCodeSent, phoneNumber, verificationId, user];
}