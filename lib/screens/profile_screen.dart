import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';
import 'package:phone_authentication/core/validators.dart';
import 'package:phone_authentication/constants/images.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _ageController;
  late TextEditingController _vehicleTypesController;
  late TextEditingController _aadharNumberController;
  Map<String, TextEditingController> _vehicleNumberControllers = {};
  List<String> _selectedVehicleTypes = [];
  final _vehicleTypesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    debugPrint('ProfileScreen: Initializing controllers');
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _ageController = TextEditingController();
    _vehicleTypesController = TextEditingController();
    _aadharNumberController = TextEditingController();
    debugPrint('ProfileScreen: Controllers initialized');
  }

  @override
  void dispose() {
    debugPrint('ProfileScreen: Disposing controllers');
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _ageController.dispose();
    _vehicleTypesController.dispose();
    _aadharNumberController.dispose();
    _vehicleNumberControllers.forEach((_, controller) => controller.dispose());
    _vehicleTypesFocus.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('ProfileScreen: No user logged in');
      return null;
    }

    try {
      debugPrint('ProfileScreen: Fetching data for user: ${user.uid}');
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        debugPrint('ProfileScreen: Fetched user data: $data');
        _nameController.text = data['name'] ?? '';
        _phoneController.text = data['phone']?.replaceFirst('+91', '') ?? '';
        _addressController.text = data['address'] ?? '';
        _ageController.text = data['age'] ?? '';
        _aadharNumberController.text = data['aadharNumber'] ?? '';
        _selectedVehicleTypes = (data['vehicleTypes'] as String?)?.isNotEmpty ?? false
            ? data['vehicleTypes'].split(', ').toList()
            : [];
        _vehicleTypesController.text = _selectedVehicleTypes.join(', ');
        _vehicleNumberControllers = {};
        final vehicleNumbers = data['vehicleNumbers'] as Map<String, dynamic>? ?? {};
        vehicleNumbers.forEach((vehicleType, number) {
          _vehicleNumberControllers[vehicleType] = TextEditingController(text: number);
        });
        debugPrint('ProfileScreen: Initialized controllers with data');
        return data;
      } else {
        debugPrint('ProfileScreen: No profile data found for user: ${user.uid}');
        return null;
      }
    } catch (e) {
      debugPrint('ProfileScreen: Error fetching user data: $e');
      return null;
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _formKey.currentState?.reset();
      }
      debugPrint('ProfileScreen: Edit mode toggled to: $_isEditing');
    });
  }

  void _saveProfile(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      final cubit = context.read<PhoneAuthCubit>();
      final fields = {
        'name': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'age': _ageController.text,
        'vehicleTypes': _vehicleTypesController.text,
        'aadharNumber': _aadharNumberController.text,
      };

      debugPrint('ProfileScreen: Updating cubit with fields: $fields');
      fields.forEach((key, value) {
        cubit.updateField(key, value);
      });

      _vehicleNumberControllers.forEach((vehicleType, controller) {
        cubit.updateVehicleNumber(vehicleType, controller.text);
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final data = {
            'name': _nameController.text,
            'phone': _phoneController.text.startsWith('+91') ? _phoneController.text : '+91${_phoneController.text}',
            'address': _addressController.text,
            'age': _ageController.text,
            'vehicleTypes': _vehicleTypesController.text,
            'aadharNumber': _aadharNumberController.text,
            'vehicleNumbers': _vehicleNumberControllers.map((key, controller) => MapEntry(key, controller.text)),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          debugPrint('ProfileScreen: Saving profile data to Firestore: $data');
          await FirebaseFirestore.instance.collection('drivers').doc(user.uid).set(data, SetOptions(merge: true));

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 18.r),
                  SizedBox(width: 8.w),
                  Text('Profile updated!', style: TextStyle(fontSize: 14.sp)),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              margin: EdgeInsets.all(10.w),
              duration: const Duration(seconds: 2),
            ),
          );
          _toggleEditMode();
        } else {
          debugPrint('ProfileScreen: No user logged in during save');
        }
      } catch (e) {
        debugPrint('ProfileScreen: Error saving profile: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white, size: 18.r),
                SizedBox(width: 8.w),
                Expanded(child: Text('Error: $e', style: TextStyle(fontSize: 14.sp))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            margin: EdgeInsets.all(10.w),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      debugPrint('ProfileScreen: Form validation failed');
    }
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
                          _vehicleNumberControllers.remove(vehicle['name'])?.dispose();
                        } else {
                          _selectedVehicleTypes.add(vehicle['name']!);
                          _vehicleNumberControllers[vehicle['name']!] = TextEditingController();
                        }
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
                                  _vehicleNumberControllers[vehicle['name']!] = TextEditingController();
                                } else {
                                  _selectedVehicleTypes.remove(vehicle['name']);
                                  _vehicleNumberControllers.remove(vehicle['name'])?.dispose();
                                }
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
    ).then((_) {
      setState(() {
        _vehicleTypesController.text = _selectedVehicleTypes.join(', ');
        debugPrint('ProfileScreen: Vehicle types updated: ${_vehicleTypesController.text}');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context, designSize: const Size(360, 640), minTextAdapt: true);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Driver Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18.sp),
        ),
        backgroundColor: const Color(0xFF1565C0),
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 44.h,
        actions: [
          if (user != null && !_isEditing)
            IconButton(
              onPressed: _toggleEditMode,
              icon: Icon(Icons.edit, color: Colors.white, size: 20.r),
              tooltip: 'Edit Profile',
              padding: EdgeInsets.all(6.w),
            ),
        ],
      ),
      body: user == null
          ? _buildLoginPrompt(context)
          : FutureBuilder<Map<String, dynamic>?>(
              future: _fetchUserData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  debugPrint('ProfileScreen: Waiting for user data');
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
                      strokeWidth: 2.w,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  debugPrint('ProfileScreen: Snapshot error: ${snapshot.error}');
                  return _buildErrorState();
                }
                if (!snapshot.hasData || snapshot.data == null) {
                  debugPrint('ProfileScreen: No profile data in snapshot');
                  return _buildNoDataState();
                }

                return _buildProfileContent();
              },
            ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_off, size: 40.r, color: Colors.red),
            ),
            SizedBox(height: 10.h),
            Text(
              'Authentication Required',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: const Color(0xFF1565C0)),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please log in to access your profile.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600], height: 1.2),
            ),
            SizedBox(height: 14.h),
            SizedBox(
              width: 180.w,
              child: ElevatedButton(
                onPressed: () => context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                  elevation: 1,
                ),
                child: Text('Go to Login', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 40.r, color: Colors.red),
            ),
            SizedBox(height: 10.h),
            Text(
              'Something went wrong',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            SizedBox(height: 8.h),
            Text(
              'Unable to load profile data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_search, size: 40.r, color: Colors.orange),
            ),
            SizedBox(height: 10.h),
            Text(
              'Profile Not Found',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please complete your profile setup.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        final baseFontSize = isKeyboardOpen ? 0.85 : 1.0;

        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileHeader(baseFontSize),
                  SizedBox(height: 6.h),
                  _buildProfileDetailsCard(baseFontSize),
                  if (_isEditing) Padding(padding: EdgeInsets.only(top: 6.h), child: _buildActionButtons(baseFontSize)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(double fontScale) {
    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1565C0).withOpacity(0.2), blurRadius: 4.r, offset: Offset(0, 1.h)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.h,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 3.r, offset: Offset(0, 1.h))],
            ),
            child: Center(
              child: Text(
                _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'D',
                style: TextStyle(fontSize: 20.sp * fontScale, fontWeight: FontWeight.bold, color: const Color(0xFF1565C0)),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: _isEditing
                ? TextFormField(
                    controller: _nameController,
                    decoration: _buildInputDecoration('Full Name', fontScale),
                    validator: (value) => validateField('name', value ?? ''),
                    style: TextStyle(fontSize: 16.sp * fontScale, fontWeight: FontWeight.w600),
                  )
                : Text(
                    _nameController.text.isNotEmpty ? _nameController.text : 'Driver Name',
                    style: TextStyle(fontSize: 16.sp * fontScale, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              'Driver',
              style: TextStyle(fontSize: 10.sp * fontScale, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetailsCard(double fontScale) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4.r, offset: Offset(0, 1.h))],
      ),
      child: Padding(
        padding: EdgeInsets.all(10.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Personal Information',
                style: TextStyle(fontSize: 14.sp * fontScale, fontWeight: FontWeight.bold, color: const Color(0xFF1565C0)),
              ),
              SizedBox(height: 6.h),
              _buildModernProfileField(
                icon: Icons.phone,
                label: 'Phone',
                value: _phoneController.text,
                controller: _phoneController,
                enabled: false,
                fontScale: fontScale,
              ),
              SizedBox(height: 6.h),
              _buildModernProfileField(
                icon: Icons.location_on,
                label: 'Address',
                value: _addressController.text,
                controller: _addressController,
                enabled: _isEditing,
                validator: (value) => validateField('address', value ?? ''),
                fontScale: fontScale,
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Expanded(
                    child: _buildModernProfileField(
                      icon: Icons.cake,
                      label: 'Age',
                      value: _ageController.text,
                      controller: _ageController,
                      enabled: _isEditing,
                      validator: (value) => validateField('age', value ?? ''),
                      keyboardType: TextInputType.number,
                      fontScale: fontScale,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: _buildModernProfileField(
                      icon: Icons.credit_card,
                      label: 'Aadhar Number',
                      value: _aadharNumberController.text,
                      controller: _aadharNumberController,
                      enabled: _isEditing,
                      validator: (value) => validateField('aadharNumber', value ?? '', validateAadharNumber: true),
                      keyboardType: TextInputType.number,
                      fontScale: fontScale,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              _buildModernProfileField(
                icon: Icons.directions_car,
                label: 'Vehicle Types',
                value: _vehicleTypesController.text,
                controller: _vehicleTypesController,
                enabled: _isEditing,
                validator: (value) => validateField('vehicleTypes', value ?? ''),
                keyboardType: TextInputType.none,
                onTap: _isEditing ? _showVehicleBottomSheet : null,
                focusNode: _vehicleTypesFocus,
                showArrow: _isEditing,
                fontScale: fontScale,
              ),
              ..._selectedVehicleTypes.map((vehicleType) {
                return Column(
                  children: [
                    SizedBox(height: 6.h),
                    _buildModernProfileField(
                      icon: Icons.directions_car,
                      label: 'Vehicle Number ($vehicleType)',
                      value: _vehicleNumberControllers[vehicleType]?.text ?? '',
                      controller: _vehicleNumberControllers[vehicleType],
                      enabled: _isEditing,
                      validator: (value) => validateField('vehicleNumber_$vehicleType', value ?? '', validateVehicleNumber: true),
                      fontScale: fontScale,
                    ),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(double fontScale) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _toggleEditMode,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              padding: EdgeInsets.symmetric(vertical: 8.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            child: Text('Cancel', style: TextStyle(fontSize: 12.sp * fontScale, fontWeight: FontWeight.w600)),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _saveProfile(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 8.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              elevation: 1,
            ),
            child: Text('Save', style: TextStyle(fontSize: 12.sp * fontScale, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String label, double fontScale) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 10.sp * fontScale),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: const Color(0xFF1565C0), width: 1.w),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: BorderSide(color: Colors.red, width: 1.w),
      ),
      filled: true,
      fillColor: _isEditing ? Colors.grey[50] : Colors.grey[100],
      contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      suffixIcon: label == 'Vehicle Types' && _isEditing
          ? Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 20.r)
          : null,
    );
  }

  Widget _buildModernProfileField({
    required IconData icon,
    required String label,
    required String value,
    TextEditingController? controller,
    bool enabled = true,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    required double fontScale,
    VoidCallback? onTap,
    FocusNode? focusNode,
    bool showArrow = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Icon(icon, color: const Color(0xFF1565C0), size: 18.r),
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(fontSize: 10.sp * fontScale, fontWeight: FontWeight.w600, color: Colors.grey[700]),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        SizedBox(height: 4.h),
        _isEditing && enabled
            ? TextFormField(
                controller: controller,
                decoration: _buildInputDecoration(label, fontScale),
                validator: validator,
                keyboardType: keyboardType,
                enabled: enabled,
                readOnly: label == 'Vehicle Types',
                onTap: onTap,
                focusNode: focusNode,
                style: TextStyle(fontSize: 14.sp * fontScale),
              )
            : Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Text(
                  value.isNotEmpty ? value : 'Not specified',
                  style: TextStyle(
                    fontSize: 14.sp * fontScale,
                    fontWeight: FontWeight.w500,
                    color: value.isNotEmpty ? Colors.black87 : Colors.grey[500],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ],
    );
  }
}