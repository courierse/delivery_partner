import 'package:get_it/get_it.dart';
import 'package:phone_authentication/bloc/location_cubit/location_cubit.dart';

final GetIt locator = GetIt.instance;

void setupLocator() {
  locator.registerFactory(() => LocationCubit());
}