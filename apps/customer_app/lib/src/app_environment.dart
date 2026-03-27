import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnvironment {
  const AppEnvironment._();

  static String get supabaseUrl => _readValue(
    key: 'SUPABASE_URL',
    fromDefine: const String.fromEnvironment('SUPABASE_URL'),
  );

  static String get supabaseAnonKey => _readValue(
    key: 'SUPABASE_ANON_KEY',
    fromDefine: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String _readValue({
    required String key,
    required String fromDefine,
  }) {
    if (fromDefine.trim().isNotEmpty) {
      return fromDefine.trim();
    }

    final String fromEnv = dotenv.maybeGet(key)?.trim() ?? '';
    return fromEnv;
  }
}
