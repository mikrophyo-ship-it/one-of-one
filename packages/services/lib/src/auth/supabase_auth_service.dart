import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_action_result.dart';

class SupabaseAuthService {
  SupabaseAuthService({SupabaseClient? client, String? configurationError})
    : _client = client,
      _configurationError = configurationError;

  final SupabaseClient? _client;
  final String? _configurationError;

  bool get isConfigured => _client != null;

  User? get currentUser => _client?.auth.currentUser;

  Session? get currentSession => _client?.auth.currentSession;

  Stream<AuthState> authStateChanges() {
    if (_client == null) {
      return const Stream<AuthState>.empty();
    }
    return _client!.auth.onAuthStateChange;
  }

  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final String? configurationMessage = _requireConfigured();
    if (configurationMessage != null) {
      return AuthActionResult(success: false, message: configurationMessage);
    }

    try {
      final AuthResponse response = await _client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        return const AuthActionResult(
          success: false,
          message: 'Sign-in did not return a collector session.',
        );
      }

      await _upsertProfileForCurrentUser();
      return const AuthActionResult(
        success: true,
        message: 'Signed in and collector profile synced.',
      );
    } on AuthException catch (error) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(error.message),
      );
    } on PostgrestException catch (error) {
      return AuthActionResult(
        success: false,
        message: _friendlyBackendMessage(error.message),
      );
    }
  }

  Future<AuthActionResult> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    final String? configurationMessage = _requireConfigured();
    if (configurationMessage != null) {
      return AuthActionResult(success: false, message: configurationMessage);
    }

    final String normalizedUsername = _normalizeUsername(username);
    try {
      final AuthResponse response = await _client!.auth.signUp(
        email: email.trim(),
        password: password,
        data: <String, dynamic>{
          'display_name': displayName.trim(),
          'username': normalizedUsername,
        },
      );

      if (response.user == null) {
        return const AuthActionResult(
          success: false,
          message: 'Account creation did not return a collector identity.',
        );
      }

      if (response.session == null) {
        return const AuthActionResult(
          success: true,
          requiresEmailConfirmation: true,
          message:
              'Account created. Check your inbox to confirm your email before signing in.',
        );
      }

      await _upsertProfileForCurrentUser(
        displayName: displayName,
        username: normalizedUsername,
      );
      return const AuthActionResult(
        success: true,
        message: 'Collector account created and profile synced.',
      );
    } on AuthException catch (error) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(error.message),
      );
    } on PostgrestException catch (error) {
      return AuthActionResult(
        success: false,
        message: _friendlyBackendMessage(error.message),
      );
    }
  }

  Future<AuthActionResult> sendPasswordReset({required String email}) async {
    final String? configurationMessage = _requireConfigured();
    if (configurationMessage != null) {
      return AuthActionResult(success: false, message: configurationMessage);
    }

    try {
      await _client!.auth.resetPasswordForEmail(email.trim());
      return const AuthActionResult(
        success: true,
        message:
            'Password reset instructions sent if that collector account exists.',
      );
    } on AuthException catch (error) {
      return AuthActionResult(
        success: false,
        message: _friendlyAuthMessage(error.message),
      );
    }
  }

  Future<void> signOut() async {
    if (_client == null) {
      return;
    }
    await _client!.auth.signOut();
  }

  Future<void> upsertProfile({
    required String displayName,
    required String username,
    String? avatarUrl,
  }) async {
    final String? configurationMessage = _requireConfigured();
    if (configurationMessage != null) {
      throw StateError(configurationMessage);
    }

    await _client!.rpc(
      'upsert_my_profile',
      params: <String, dynamic>{
        'p_display_name': displayName.trim(),
        'p_username': _normalizeUsername(username),
        'p_avatar_url': avatarUrl,
      },
    );
  }

  Future<void> _upsertProfileForCurrentUser({
    String? displayName,
    String? username,
  }) async {
    final User? user = currentUser;
    if (user == null) {
      return;
    }

    await upsertProfile(
      displayName: _preferredDisplayName(user, displayName),
      username: _preferredUsername(user, username),
      avatarUrl: _optionalString(user.userMetadata?['avatar_url']),
    );
  }

  String _preferredDisplayName(User user, String? explicitDisplayName) {
    final String? metadataDisplayName = _optionalString(
      user.userMetadata?['display_name'],
    );
    final String candidate =
        (explicitDisplayName ??
                metadataDisplayName ??
                _emailLocalPart(user.email) ??
                'Collector')
            .trim();
    if (candidate.isEmpty) {
      return 'Collector';
    }
    return candidate;
  }

  String _preferredUsername(User user, String? explicitUsername) {
    final String? metadataUsername = _optionalString(
      user.userMetadata?['username'],
    );
    final String seed =
        explicitUsername ??
        metadataUsername ??
        _emailLocalPart(user.email) ??
        'collector_${user.id.substring(0, 8)}';
    final String normalized = _normalizeUsername(seed);
    if (normalized.isEmpty) {
      return 'collector_${user.id.substring(0, 8)}';
    }
    return normalized;
  }

  String _normalizeUsername(String value) {
    final String sanitized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return sanitized.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String? _emailLocalPart(String? email) {
    if (email == null || !email.contains('@')) {
      return null;
    }
    return email.split('@').first;
  }

  String? _optionalString(dynamic value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _requireConfigured() {
    if (_client == null) {
      return _configurationError ?? 'Supabase is not configured for this app.';
    }
    return null;
  }

  String _friendlyAuthMessage(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Email or password was not accepted.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Confirm your email before signing in.';
    }
    if (message.contains('User already registered')) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (message.contains('Password should be at least')) {
      return 'Password must be at least 8 characters.';
    }
    return message;
  }

  String _friendlyBackendMessage(String message) {
    if (message.contains('Display name is required')) {
      return 'Display name is required to finish collector setup.';
    }
    if (message.contains('Username is required')) {
      return 'Choose a username to finish collector setup.';
    }
    if (message.contains('duplicate key')) {
      return 'That username is already taken.';
    }
    return message;
  }
}
