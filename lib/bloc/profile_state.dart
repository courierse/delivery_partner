part of 'profile_cubit.dart';

class PhoneAuthState extends Equatable {
  final Map<String, String> fields;
  final Map<String, String?> errors;
  final Map<String, String> vehicleNumbers;
  final Map<String, XFile?> rcImageFiles; // Added to store XFile objects
  final Map<String, String> rcImages;
  final String statusMessage;
  final bool isCodeSent;
  final String? phoneNumber;
  final String? verificationId;
  final User? user;

  const PhoneAuthState({
    this.fields = const {
      'name': '',
      'phone': '',
      'address': '',
      'age': '',
      'vehicleTypes': '',
    },
    this.errors = const {
      'name': null,
      'phone': null,
      'address': null,
      'age': null,
      'vehicleTypes': null,
    },
    this.vehicleNumbers = const {},
    this.rcImageFiles = const {}, // Initialize rcImageFiles
    this.rcImages = const {},
    this.statusMessage = '',
    this.isCodeSent = false,
    this.phoneNumber,
    this.verificationId,
    this.user,
  });

  PhoneAuthState copyWith({
    Map<String, String>? fields,
    Map<String, String?>? errors,
    Map<String, String>? vehicleNumbers,
    Map<String, XFile?>? rcImageFiles,
    Map<String, String>? rcImages,
    String? statusMessage,
    bool? isCodeSent,
    String? phoneNumber,
    String? verificationId,
    User? user,
  }) {
    return PhoneAuthState(
      fields: fields ?? this.fields,
      errors: errors ?? this.errors,
      vehicleNumbers: vehicleNumbers ?? this.vehicleNumbers,
      rcImageFiles: rcImageFiles ?? this.rcImageFiles,
      rcImages: rcImages ?? this.rcImages,
      statusMessage: statusMessage ?? this.statusMessage,
      isCodeSent: isCodeSent ?? this.isCodeSent,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      verificationId: verificationId ?? this.verificationId,
      user: user ?? this.user,
    );
  }

  @override
  List<Object?> get props => [fields, errors, vehicleNumbers, rcImageFiles, rcImages, statusMessage, isCodeSent, phoneNumber, verificationId, user];
}