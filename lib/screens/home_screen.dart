import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_authentication/constants/colors.dart';
import 'package:phone_authentication/bloc/profile_cubit.dart';
import 'package:phone_authentication/screens/history_screen.dart';
import 'alert_screen.dart';
import 'profile_screen.dart';
import 'driver_earnings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    AlertScreen(),
    DeliveryHistoryScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Home',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.buttonTextColor,
            fontSize: 20.sp,
          ),
        ),
        backgroundColor: AppColors.buttonColour,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DriverEarningsScreen(),
                ),
              );
            },
            tooltip: 'Driver Earnings',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.read<PhoneAuthCubit>().signOut();
              context.go('/mobile-entry');
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Alert'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: AppColors.buttonColour,
        unselectedItemColor: AppColors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}
