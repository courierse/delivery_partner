part of 'phone_auth_cubit.dart';

class PhoneAuthState extends Equatable {
  final Map<String, String> fields;
  final Map<String, String?> errors;
  final String statusMessage;
  final bool isCodeSent;
  final String? phoneNumber;

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
  });

  PhoneAuthState copyWith({
    Map<String, String>? fields,
    Map<String, String?>? errors,
    String? statusMessage,
    bool? isCodeSent,
    String? phoneNumber,
  }) {
    return PhoneAuthState(
      fields: fields ?? this.fields,
      errors: errors ?? this.errors,
      statusMessage: statusMessage ?? this.statusMessage,
      isCodeSent: isCodeSent ?? this.isCodeSent,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  @override
  List<Object?> get props => [fields, errors, statusMessage, isCodeSent, phoneNumber];
}