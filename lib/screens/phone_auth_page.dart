import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phone_authentication/constants/images.dart';
import 'package:phone_authentication/screens/custom_text_field.dart';
import '../bloc/profile_cubit.dart';

class PhoneAuthPage extends StatefulWidget {
  final String initialPhoneNumber;

  const PhoneAuthPage({super.key, this.initialPhoneNumber = ''});

  @override
  _PhoneAuthPageState createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final _controllers = {
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'address': TextEditingController(),
    'age': TextEditingController(),
    'vehicleTypes': TextEditingController(),
  };
  Map<String, TextEditingController> _vehicleNumberControllers = {};
  Map<String, XFile?> _rcImages = {};
  List<String> _selectedVehicleTypes = [];
  final _vehicleTypesFocus = FocusNode();
  late PhoneAuthCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<PhoneAuthCubit>();
    _controllers['phone']!.text = widget.initialPhoneNumber;
    _cubit.updateField('phone', widget.initialPhoneNumber);
    _controllers['phone']!.selection = TextSelection.fromPosition(
      const TextPosition(offset: 0),
    );
    final initialVehicleTypes = _cubit.state.fields['vehicleTypes'] as String?;
    if (initialVehicleTypes != null && initialVehicleTypes.isNotEmpty) {
      _selectedVehicleTypes = initialVehicleTypes.split(', ').toList();
      for (var vehicleType in _selectedVehicleTypes) {
        _vehicleNumberControllers[vehicleType] = TextEditingController(
          text: _cubit.state.vehicleNumbers[vehicleType] ?? '',
        );
        _vehicleNumberControllers[vehicleType]!.addListener(() {
          final value = _vehicleNumberControllers[vehicleType]!.text;
          if (value != _cubit.state.vehicleNumbers[vehicleType]) {
            debugPrint('Vehicle controller listener updating: $vehicleType = $value');
            _cubit.updateVehicleNumber(vehicleType, value);
          }
        });
      }
    }
    _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
    _controllers.forEach((key, controller) {
      if (key != 'vehicleTypes' && key != 'phone') {
        controller.text = _cubit.state.fields[key] ?? '';
        controller.addListener(() {
          if (controller.text != _cubit.state.fields[key]) {
            debugPrint('Controller listener updating: $key = ${controller.text}');
            _cubit.updateField(key, controller.text);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) {
      controller.removeListener(() {});
      controller.dispose();
    });
    _vehicleNumberControllers.forEach((key, controller) {
      controller.removeListener(() {});
      controller.dispose();
    });
    _vehicleTypesFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String vehicleType) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxHeight: 800,
        maxWidth: 800,
      );
      if (pickedFile != null && (pickedFile.path.endsWith('.jpg') || pickedFile.path.endsWith('.png'))) {
        setState(() {
          _rcImages[vehicleType] = pickedFile;
        });
        _cubit.updateRcImage(vehicleType, pickedFile);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RC image selected for $vehicleType, will upload after authentication')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a JPG or PNG file')),
        );
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  bool _canSubmitForm() {
    final state = _cubit.state;
    final selectedVehicles = state.fields['vehicleTypes']?.split(', ').where((v) => v.isNotEmpty).toList() ?? [];
    for (var vehicleType in selectedVehicles) {
      if (!state.rcImageFiles.containsKey(vehicleType) || state.rcImageFiles[vehicleType] == null) {
        return false;
      }
    }
    return true;
  }

  Widget _buildTextField({
    required String key,
    required String label,
    required TextInputType keyboardType,
    IconData? prefixIcon,
    String? prefixText,
    String? errorText,
    required BuildContext context,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
    TextEditingController? controller,
  }) {
    controller ??= _controllers[key]!;
    if (!readOnly && !key.startsWith('vehicleNumber_')) {
      final cubitValue = _cubit.state.fields[key] ?? '';
      if (controller.text != cubitValue) {
        debugPrint('Syncing controller for $key: setting text to $cubitValue');
        controller.text = cubitValue;
      }
    } else if (key.startsWith('vehicleNumber_')) {
      final vehicleType = key.replaceFirst('vehicleNumber_', '');
      final cubitValue = _cubit.state.vehicleNumbers[vehicleType] ?? '';
      if (controller.text != cubitValue) {
        debugPrint('Syncing vehicle controller for $vehicleType: setting text to $cubitValue');
        controller.text = cubitValue;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: CustomTextField(
        controller: controller,
        labelText: label,
        prefixIcon: prefixIcon,
        keyboardType: keyboardType,
        prefixText: prefixText,
        errorText: errorText,
        readOnly: readOnly,
        onTap: onTap,
        focusNode: focusNode,
        onChanged: readOnly
            ? null
            : (value) {
                debugPrint('Text field changed: $key = $value');
                if (key.startsWith('vehicleNumber_')) {
                  final vehicleType = key.replaceFirst('vehicleNumber_', '');
                  _cubit.updateVehicleNumber(vehicleType, value);
                } else {
                  _cubit.updateField(key, value);
                }
              },
        decoration: readOnly
            ? InputDecoration(
                labelText: label,
                prefixIcon: prefixIcon != null
                    ? Icon(prefixIcon, size: 24.sp, color: Colors.blueAccent)
                    : null,
                suffixIcon: key == 'vehicleTypes'
                    ? Icon(Icons.arrow_drop_down, size: 24.sp, color: Colors.blueAccent)
                    : null,
                labelStyle: TextStyle(fontSize: 14.sp, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: Colors.blueAccent),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
                filled: true,
                fillColor: Colors.grey[100],
              )
            : null,
      ),
    );
  }

  void _showVehicleBottomSheet() {
    final vehicles = [
      {'name': '2 Wheeler', 'dimension': '40cm x 40cm x 40cm', 'image': Images.bike},
      {'name': 'E-Loader', 'dimension': '6ft x 4.6 ft x 5ft', 'image': Images.eloader},
      {'name': '3 Wheeler', 'dimension': '6ft x 4.6 ft x 5ft', 'image': Images.three_wheeler},
      {'name': 'Tata Ace', 'dimension': '7ft x 4ft x 5ft', 'image': Images.tatace},
      {'name': '8 Feet', 'dimension': '8ft x 4.5ft x 5.5ft', 'image': Images.eightfeets},
      {'name': '10 Feet', 'dimension': '10.0ft x 5.5ft x 5.5ft', 'image': Images.tenfeets},
      {'name': '14 Feet', 'dimension': '14.0ft x 6.0ft x 6.0ft', 'image': Images.forteenfeets},
      {'name': '17 Feet', 'dimension': '17.0ft x 6.5ft x 6.5ft', 'image': Images.seventeenfeets},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Colors.grey.shade200],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              boxShadow: [
                BoxShadow(color: Colors.black, blurRadius: 10.r, offset: Offset(0, -2)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Vehicle Types',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.blueAccent,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20.sp, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                ...vehicles.map((vehicle) {
                  final isSelected = _selectedVehicleTypes.contains(vehicle['name']);
                  return GestureDetector(
                    onTap: () {
                      setModalState(() {
                        if (isSelected) {
                          _selectedVehicleTypes.remove(vehicle['name']);
                          _vehicleNumberControllers[vehicle['name']]?.removeListener(() {});
                          _vehicleNumberControllers.remove(vehicle['name']);
                          _rcImages.remove(vehicle['name']);
                          _cubit.removeRcImage(vehicle['name']!);
                        } else {
                          _selectedVehicleTypes.add(vehicle['name']!);
                          _vehicleNumberControllers[vehicle['name']!] = TextEditingController(
                            text: _cubit.state.vehicleNumbers[vehicle['name']] ?? '',
                          );
                          _vehicleNumberControllers[vehicle['name']!]!.addListener(() {
                            final value = _vehicleNumberControllers[vehicle['name']!]!.text;
                            _cubit.updateVehicleNumber(vehicle['name']!, value);
                          });
                        }
                      });
                      _cubit.updateField('vehicleTypes', _selectedVehicleTypes.join(', '));
                      _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
                      debugPrint('Vehicle types updated: ${_selectedVehicleTypes.join(', ')}');
                    },
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 4.h),
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blueAccent : Colors.white,
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(
                          color: isSelected ? Colors.blueAccent : Colors.grey,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4.r),
                        ],
                      ),
                      child: Row(
                        children: [
                          Image.asset(
                            vehicle['image']!,
                            width: 40.w,
                            height: 40.h,
                            fit: BoxFit.contain,
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle['name']!,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  vehicle['dimension']!,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w400,
                                    color: isSelected ? Colors.white70 : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: isSelected,
                            onChanged: (val) {
                              setModalState(() {
                                if (val == true) {
                                  _selectedVehicleTypes.add(vehicle['name']!);
                                  _vehicleNumberControllers[vehicle['name']!] = TextEditingController(
                                    text: _cubit.state.vehicleNumbers[vehicle['name']] ?? '',
                                  );
                                  _vehicleNumberControllers[vehicle['name']!]!.addListener(() {
                                    final value = _vehicleNumberControllers[vehicle['name']!]!.text;
                                    _cubit.updateVehicleNumber(vehicle['name']!, value);
                                  });
                                } else {
                                  _selectedVehicleTypes.remove(vehicle['name']);
                                  _vehicleNumberControllers[vehicle['name']]?.removeListener(() {});
                                  _vehicleNumberControllers.remove(vehicle['name']);
                                  _rcImages.remove(vehicle['name']);
                                  _cubit.removeRcImage(vehicle['name']!);
                                }
                              });
                              _cubit.updateField('vehicleTypes', _selectedVehicleTypes.join(', '));
                              _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
                              debugPrint('Vehicle types updated via checkbox: ${_selectedVehicleTypes.join(', ')}');
                            },
                            activeColor: Colors.blueAccent,
                            checkColor: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8.h),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PhoneAuthCubit, PhoneAuthState>(
      listener: (context, state) {
        debugPrint('BlocListener triggered: isCodeSent=${state.isCodeSent}, '
            'phoneNumber=${state.phoneNumber}, verificationId=${state.verificationId}, '
            'statusMessage=${state.statusMessage}, fields=${state.fields}');
        if (state.user != null) {
          debugPrint('Navigating to /home');
          context.go('/home');
        } else if (state.isCodeSent && state.phoneNumber != null && state.verificationId != null) {
          debugPrint('Navigating to /otp with phoneNumber: ${state.phoneNumber}, verificationId: ${state.verificationId}');
          try {
            context.push('/otp', extra: {
              'phoneNumber': state.phoneNumber,
              'verificationId': state.verificationId,
            });
          } catch (e) {
            debugPrint('Navigation error: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Navigation failed: $e'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                margin: EdgeInsets.all(16.w),
              ),
            );
          }
        } else if (state.statusMessage.contains('Error') || state.statusMessage.contains('fix the errors')) {
          debugPrint('Error or validation issue: ${state.statusMessage}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.statusMessage),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              margin: EdgeInsets.all(16.w),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Phone Authentication',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 20.sp,
            ),
          ),
          backgroundColor: Colors.blueAccent,
          elevation: 0,
          toolbarHeight: 60.h,
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blueAccent, Colors.white],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Card(
                  elevation: 8.0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: BlocBuilder<PhoneAuthCubit, PhoneAuthState>(
                      builder: (context, state) {
                        debugPrint('BlocBuilder rebuilding with state: fields=${state.fields}, '
                            'vehicleNumbers=${state.vehicleNumbers}, errors=${state.errors}');
                        for (var vehicleType in _selectedVehicleTypes) {
                          if (!_vehicleNumberControllers.containsKey(vehicleType)) {
                            _vehicleNumberControllers[vehicleType] = TextEditingController(
                              text: state.vehicleNumbers[vehicleType] ?? '',
                            );
                            _vehicleNumberControllers[vehicleType]!.addListener(() {
                              final value = _vehicleNumberControllers[vehicleType]!.text;
                              _cubit.updateVehicleNumber(vehicleType, value);
                            });
                          }
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12.r),
                              child: Image.network(
                                'https://img.freepik.com/free-vector/mobile-login-concept-illustration_114360-135.jpg',
                                height: 150.h,
                                width: 150.w,
                                fit: BoxFit.cover,
                              ),
                            ),
                            SizedBox(height: 24.h),
                            _buildTextField(
                              key: 'name',
                              label: 'Enter name',
                              keyboardType: TextInputType.name,
                              prefixIcon: Icons.person,
                              errorText: state.errors['name'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'phone',
                              label: 'Enter phone number',
                              keyboardType: TextInputType.phone,
                              prefixIcon: Icons.phone,
                              prefixText: '+91 ',
                              errorText: state.errors['phone'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'address',
                              label: 'Enter address',
                              keyboardType: TextInputType.streetAddress,
                              prefixIcon: Icons.location_on,
                              errorText: state.errors['address'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'age',
                              label: 'Enter age',
                              keyboardType: TextInputType.number,
                              prefixIcon: Icons.cake,
                              errorText: state.errors['age'],
                              context: context,
                            ),
                            _buildTextField(
                              key: 'vehicleTypes',
                              label: 'Select vehicle types',
                              keyboardType: TextInputType.none,
                              prefixIcon: Icons.directions_car,
                              errorText: state.errors['vehicleTypes'],
                              context: context,
                              readOnly: true,
                              onTap: _showVehicleBottomSheet,
                              focusNode: _vehicleTypesFocus,
                            ),
                            ..._selectedVehicleTypes.map((vehicleType) {
                              return Column(
                                children: [
                                  _buildTextField(
                                    key: 'vehicleNumber_$vehicleType',
                                    label: 'Vehicle number for $vehicleType',
                                    keyboardType: TextInputType.text,
                                    prefixIcon: Icons.directions_car,
                                    errorText: state.errors['vehicleNumber_$vehicleType'],
                                    context: context,
                                    controller: _vehicleNumberControllers[vehicleType],
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 16.h),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () => _pickImage(vehicleType),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blueAccent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8.r),
                                              ),
                                            ),
                                            child: Text(
                                              'Upload RC for $vehicleType',
                                              style: TextStyle(fontSize: 14.sp, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 8.w),
                                        if (_rcImages[vehicleType] != null)
                                          Icon(Icons.check_circle, color: Colors.green, size: 24.sp),
                                      ],
                                    ),
                                  ),
                                  if (state.errors['rcImage_$vehicleType'] != null)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 8.h),
                                      child: Text(
                                        state.errors['rcImage_$vehicleType']!,
                                        style: TextStyle(color: Colors.red, fontSize: 12.sp),
                                      ),
                                    ),
                                ],
                              );
                            }).toList(),
                            SizedBox(height: 8.h),
                            Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.blueAccent, Colors.cyan],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8.r,
                                    offset: Offset(0, 4.h),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: state.isCodeSent ||
                                        state.statusMessage == 'Sending verification code...' ||
                                        !_canSubmitForm()
                                    ? null
                                    : () {
                                        debugPrint('Submit button pressed');
                                        _vehicleNumberControllers.forEach((vehicleType, controller) {
                                          _cubit.updateVehicleNumber(vehicleType, controller.text);
                                        });
                                        _cubit.submitForm();
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: state.statusMessage == 'Sending verification code...'
                                    ? CircularProgressIndicator(color: Colors.white)
                                    : Text(
                                        'Send Verification Code',
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                            SizedBox(height: 24.h),
                            Text(
                              state.statusMessage,
                              style: TextStyle(
                                fontSize: 16.sp,
                                color: state.statusMessage.contains('Error') || state.statusMessage.contains('fix the errors')
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}