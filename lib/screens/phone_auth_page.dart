import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/constants/images.dart';
import 'package:phone_authentication/screens/custom_text_field.dart';
import '../bloc/profile_cubit.dart';

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key});

  @override
  _PhoneAuthPageState createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final _controllers = {
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'address': TextEditingController(),
    'age': TextEditingController(),
    'vehicle': TextEditingController(), // Changed to vehicle
    'vehicleTypes': TextEditingController(),
  };
  List<String> _selectedVehicleTypes = [];
  final _vehicleTypesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controllers['phone']!.selection = TextSelection.fromPosition(
      const TextPosition(offset: 0),
    );
    // Initialize vehicleTypes from cubit state if available
    final initialVehicleTypes = context.read<PhoneAuthCubit>().state.fields['vehicleTypes'] as String?;
    if (initialVehicleTypes != null && initialVehicleTypes.isNotEmpty) {
      _selectedVehicleTypes = initialVehicleTypes.split(', ').toList();
    }
    _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
  }

  @override
  void dispose() {
    _controllers.forEach((_, controller) {
      controller.removeListener(() {});
      controller.dispose();
    });
    _vehicleTypesFocus.dispose();
    super.dispose();
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
  }) {
    _controllers[key]!.text = context.read<PhoneAuthCubit>().state.fields[key] ?? (key == 'vehicleTypes' ? _selectedVehicleTypes.join(', ') : '');
    if (key != 'vehicleTypes') {
      _controllers[key]!.addListener(() {
        context.read<PhoneAuthCubit>().updateField(key, _controllers[key]!.text);
      });
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: CustomTextField(
        controller: _controllers[key]!,
        labelText: label,
        prefixIcon: prefixIcon,
        keyboardType: keyboardType,
        prefixText: prefixText,
        errorText: errorText,
        readOnly: readOnly,
        onTap: onTap,
        focusNode: focusNode,
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
      {'name': '2 Wheeler', 'price': '₹50/km', 'image': Images.bike},
      {'name': 'Tata Ace', 'price': '₹100/km', 'image': Images.tatace},
      {'name': '10 Feet', 'price': '₹150/km', 'image': Images.tenfeets},
      {'name': '17 Feet', 'price': '₹220/km', 'image': Images.seventeenfeets},
      {'name': '3 Wheeler', 'price': '₹120/km', 'image': Images.three_wheeler},
      {'name': 'E-Loader', 'price': '₹130/km', 'image': Images.eloader},
      {'name': '14 Feet', 'price': '₹140/km', 'image': Images.forteenfeets},
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
                        } else {
                          _selectedVehicleTypes.add(vehicle['name']!);
                        }
                      });
                      setState(() {
                        _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
                        context.read<PhoneAuthCubit>().updateField('vehicleTypes', _selectedVehicleTypes.join(', '));
                      });
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
                                  vehicle['price']!,
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
                                } else {
                                  _selectedVehicleTypes.remove(vehicle['name']);
                                }
                              });
                              setState(() {
                                _controllers['vehicleTypes']!.text = _selectedVehicleTypes.join(', ');
                                context.read<PhoneAuthCubit>().updateField('vehicleTypes', _selectedVehicleTypes.join(', '));
                              });
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
        if (state.user != null) {
          context.go('/home');
        } else if (state.isCodeSent && state.phoneNumber != null && state.verificationId != null) {
          debugPrint('Navigating with phone number: ${state.phoneNumber}, verificationId: ${state.verificationId}');
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
        } else if (state.statusMessage.contains('Error')) {
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
                              key: 'vehicle', // Changed to vehicle
                              label: 'Enter vehicle number',
                              keyboardType: TextInputType.text,
                              prefixIcon: Icons.directions_car,
                              errorText: state.errors['vehicle'],
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
                                onPressed: state.isCodeSent
                                    ? null
                                    : () => context.read<PhoneAuthCubit>().submitForm(),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                ),
                                child: Text(
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
                                color: state.statusMessage.contains('Error') ? Colors.red : Colors.green,
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