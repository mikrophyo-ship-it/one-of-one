import 'dart:async';

import 'package:customer_app/src/authenticity_link_source.dart';
import 'package:customer_app/src/customer_app.dart';
import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'customer app automated verification covers auth, catalog, authenticity, collection, saved items, disputes, restrictions, and relogin',
    (WidgetTester tester) async {
      final DemoCatalog repository = DemoCatalog();
      final _TestAuthService authService = _TestAuthService();
      final MarketplaceWorkflowService workflowService =
          MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const MockPaymentProvider(),
          );

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: workflowService,
          authService: authService,
          checkoutConfig: const CheckoutPresentationConfig(
            successUrl: 'https://example.test/success',
            cancelUrl: 'https://example.test/cancel',
          ),
          enableCameraScanner: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Collect the original.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Create account'));
      await tester.pumpAndSettle();

      await _enterField(tester, 'Display name', 'Avery Collector');
      await _enterField(tester, 'Username', 'averycollector');
      await _enterField(tester, 'Email', 'avery@example.com');
      await _enterField(tester, 'Password', 'password123');
      final Finder createAccountButton = find.widgetWithText(
        ElevatedButton,
        'Create Collector Account',
      );
      await tester.ensureVisible(createAccountButton);
      await tester.tap(createAccountButton);
      await tester.pumpAndSettle();

      expect(find.text('Featured artists'), findsOneWidget);
      expect(find.text('Maya Vale'), findsOneWidget);

      await _tapNav(tester, 'Shop');
      expect(find.text('Afterglow Hand-Finished Tee'), findsOneWidget);
      expect(find.text('Ember Archive Crew'), findsOneWidget);
      expect(find.text('Restricted Study Hoodie'), findsOneWidget);

      await tester.tap(find.text('Afterglow Hand-Finished Tee'));
      await tester.pumpAndSettle();
      expect(find.text('Afterglow No. 01'), findsOneWidget);
      expect(find.text('Provenance proof'), findsOneWidget);
      await _scrollUntilVisible(tester, find.text('Ownership history summary'));
      expect(find.text('Ownership history summary'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bookmark_border).first);
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Vault');
      expect(find.text('Saved items'), findsWidgets);
      expect(find.text('Afterglow Hand-Finished Tee'), findsOneWidget);

      await _tapNav(tester, 'Scan');
      await _enterField(tester, 'QR token', 'qr_ember_02');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify authenticity'));
      await tester.pumpAndSettle();

      expect(find.text('Authenticity verified'), findsOneWidget);
      expect(find.text('OOO-EM-0002'), findsWidgets);
      expect(find.textContaining('Verified resale history:'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continue to scan and claim'),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(tester, find.text('Claim ownership'));
      await _enterField(tester, 'Enter hidden claim code', 'CLAIM-OOO-EM-0002');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Claim ownership'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ownership claim approved'),
        findsAtLeastNWidgets(1),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Vault');
      expect(find.text('Ember Archive Crew'), findsOneWidget);

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Ember Archive Crew'));
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Resell item'));
      expect(find.text('Resell item'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Resell item'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Listing published'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ownership updated:'), findsOneWidget);
      expect(find.textContaining('Listing live:'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ember Archive Crew'));
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Report dispute'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Report dispute'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dispute recorded'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.textContaining('OOO-EM-0002 - disputed'), findsOneWidget);

      await tester.tap(find.text('Restricted Study Hoodie'));
      await tester.pumpAndSettle();
      expect(find.text('Authorize checkout'), findsNothing);
      expect(find.text('Resell item'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Profile');
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Collect the original.'), findsOneWidget);
    },
  );

  testWidgets('customer app signs in with an existing collector account', (
    WidgetTester tester,
  ) async {
    final DemoCatalog repository = DemoCatalog();
    final _TestAuthService authService = _TestAuthService()
      ..seedAccount(
        email: 'sign_in@example.com',
        password: 'password123',
        displayName: 'Sign In Collector',
        username: 'signincollector',
      );

    await tester.pumpWidget(
      OneOfOneCustomerApp(
        repository: repository,
        workflowService: MarketplaceWorkflowService(
          repository: repository,
          paymentProvider: const MockPaymentProvider(),
        ),
        authService: authService,
        enableCameraScanner: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
    await tester.pumpAndSettle();
    await _enterField(tester, 'Email', 'sign_in@example.com');
    await _enterField(tester, 'Password', 'password123');
    final Finder signInButton = find.widgetWithText(ElevatedButton, 'Sign In');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pumpAndSettle();

    expect(find.text('Featured artists'), findsOneWidget);
    await _tapNav(tester, 'Profile');
    expect(find.text('sign_in@example.com'), findsOneWidget);
  });

  testWidgets(
    'customer app restores an existing collector session on startup',
    (WidgetTester tester) async {
      final DemoCatalog repository = DemoCatalog();
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'user_existing',
          email: 'existing@example.com',
          displayName: 'Existing Collector',
          username: 'existingcollector',
        ),
      );

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const MockPaymentProvider(),
          ),
        authService: authService,
        enableCameraScanner: false,
      ),
    );
      await tester.pumpAndSettle();

      expect(find.text('Collect the original.'), findsNothing);
      expect(find.text('Featured artists'), findsOneWidget);
      expect(find.text('Existing Collector'), findsNothing);

      await _tapNav(tester, 'Profile');
      expect(find.text('existing@example.com'), findsOneWidget);
    },
  );

  testWidgets(
    'customer app opens the public authenticity route from a deep link before sign in',
    (WidgetTester tester) async {
      final DemoCatalog repository = DemoCatalog();

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const MockPaymentProvider(),
          ),
          authService: _TestAuthService(),
          authenticityLinkSource: FakeAuthenticityLinkSource(
            initialUri: Uri.parse(
              'https://oneofone.test/authenticity?qr=qr_afterglow_01',
            ),
          ),
          enableCameraScanner: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Authenticity verified'), findsOneWidget);
      expect(find.text('OOO-AG-0001'), findsWidgets);
      expect(find.text('Collect the original.'), findsNothing);
      expect(find.text('Back to collector sign in'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Back to collector sign in'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Collect the original.'), findsOneWidget);
    },
  );
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final Finder field = find.byWidgetPredicate((Widget widget) {
    return widget is TextField &&
        widget.decoration?.labelText == label;
  });
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      field,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Session _buildSession({
  required String id,
  required String email,
  required String displayName,
  required String username,
}) {
  return Session(
    accessToken: 'test-token',
    refreshToken: 'refresh-token',
    tokenType: 'bearer',
    user: User(
      id: id,
      appMetadata: const <String, dynamic>{},
      userMetadata: <String, dynamic>{
        'display_name': displayName,
        'username': username,
      },
      aud: 'authenticated',
      email: email,
      createdAt: DateTime(2026, 3, 26).toIso8601String(),
      emailConfirmedAt: DateTime(2026, 3, 26).toIso8601String(),
    ),
  );
}

class _TestAuthService extends SupabaseAuthService {
  _TestAuthService({Session? initialSession})
    : _session = initialSession,
      super(configurationError: null);

  final Map<String, _TestAccount> _accounts = <String, _TestAccount>{};
  Session? _session;

  @override
  bool get isConfigured => true;

  @override
  User? get currentUser => _session?.user;

  @override
  Session? get currentSession => _session;

  @override
  Stream<AuthState> authStateChanges() => const Stream<AuthState>.empty();

  @override
  Future<AuthActionResult> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final _TestAccount? account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      return const AuthActionResult(
        success: false,
        message: 'Email or password was not accepted.',
      );
    }

    _session = _buildSession(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      username: account.username,
    );
    return const AuthActionResult(
      success: true,
      message: 'Signed in and collector profile synced.',
    );
  }

  @override
  Future<AuthActionResult> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    final String normalizedEmail = email.trim().toLowerCase();
    if (_accounts.containsKey(normalizedEmail)) {
      return const AuthActionResult(
        success: false,
        message: 'An account with this email already exists. Try signing in instead.',
      );
    }

    final _TestAccount account = _TestAccount(
      id: 'collector_${_accounts.length + 1}',
      email: normalizedEmail,
      password: password,
      displayName: displayName.trim(),
      username: username.trim().toLowerCase(),
    );
    _accounts[normalizedEmail] = account;
    _session = _buildSession(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      username: account.username,
    );
    return const AuthActionResult(
      success: true,
      message: 'Collector account created and profile synced.',
    );
  }

  @override
  Future<AuthActionResult> sendPasswordReset({required String email}) async {
    return const AuthActionResult(
      success: true,
      message:
          'Password reset instructions sent if that collector account exists.',
    );
  }

  @override
  Future<void> signOut() async {
    _session = null;
  }

  void seedAccount({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) {
    final String normalizedEmail = email.trim().toLowerCase();
    _accounts[normalizedEmail] = _TestAccount(
      id: 'collector_${_accounts.length + 1}',
      email: normalizedEmail,
      password: password,
      displayName: displayName.trim(),
      username: username.trim().toLowerCase(),
    );
  }
}

class _TestAccount {
  const _TestAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.displayName,
    required this.username,
  });

  final String id;
  final String email;
  final String password;
  final String displayName;
  final String username;
}
