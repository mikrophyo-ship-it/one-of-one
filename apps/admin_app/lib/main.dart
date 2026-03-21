import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/admin_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeSupabaseIfConfigured();
  runApp(const OneOfOneAdminApp());
}

Future<void> _initializeSupabaseIfConfigured() async {
  const String url = String.fromEnvironment('SUPABASE_URL');
  const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || anonKey.isEmpty) {
    return;
  }

  await Supabase.initialize(url: url, anonKey: anonKey);
}
