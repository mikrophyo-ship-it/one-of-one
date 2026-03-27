import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app_environment.dart';
import 'src/customer_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await _initializeSupabaseIfConfigured();
  runApp(const OneOfOneCustomerApp());
}

Future<void> _initializeSupabaseIfConfigured() async {
  if (!AppEnvironment.hasSupabaseConfig) {
    return;
  }

  await Supabase.initialize(
    url: AppEnvironment.supabaseUrl,
    anonKey: AppEnvironment.supabaseAnonKey,
  );
}
