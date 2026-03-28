import 'dart:async';
import 'dart:typed_data';

import 'package:customer_app/src/authenticity_link_source.dart';
import 'package:customer_app/src/customer_app.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'customer app automated verification covers auth, catalog, authenticity, collection, saved items, disputes, restrictions, and relogin',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      await tester.tap(find.text('Maya Vale').first);
      await tester.pumpAndSettle();
      expect(find.text('Artist statement'), findsOneWidget);
      expect(find.text('Available works'), findsOneWidget);
      expect(find.text('Afterglow No. 01'), findsAtLeastNWidgets(1));
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Shop');
      expect(find.text('Afterglow Hand-Finished Tee'), findsOneWidget);
      expect(find.text('Ember Archive Crew'), findsOneWidget);
      expect(find.text('Restricted Study Hoodie'), findsOneWidget);

      final Finder afterglowCard = find
          .ancestor(
            of: find.text('Afterglow Hand-Finished Tee'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(afterglowCard);
      await tester.tap(afterglowCard);
      await tester.pumpAndSettle();
      expect(find.text('Afterglow No. 01'), findsOneWidget);
      expect(find.text('Provenance proof'), findsOneWidget);
      await _scrollUntilVisible(tester, find.text('Ownership history summary'));
      expect(find.text('Ownership history summary'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byIcon(Icons.bookmark_border).first,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border).first);
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Vault');
      expect(find.text('Saved items'), findsWidgets);
      expect(find.text('Afterglow Hand-Finished Tee'), findsOneWidget);

      await _tapNav(tester, 'Scan');
      await _enterField(tester, 'QR token', 'qr_ember_02');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Verify authenticity'),
      );
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
      await tester.tap(find.widgetWithText(FilledButton, 'Manage resale'));
      await tester.pumpAndSettle();
      expect(find.text('Ember Archive Crew'), findsAtLeastNWidgets(1));
      await _scrollUntilVisible(tester, find.text('Resell item'));
      expect(find.text('Resell item'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Resell item'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Listing published'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Shop');
      final Finder emberCard = find
          .ancestor(
            of: find.text('Ember Archive Crew'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(emberCard);
      await tester.tap(emberCard);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('customer-notifications-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Ownership updated'), findsOneWidget);
      expect(find.text('Listing live'), findsOneWidget);
      await tester.tap(find.text('Ownership updated').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Ownership refreshed for OOO-EM-0002.'),
        findsAtLeastNWidgets(1),
      );
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity').last);
      await tester.pumpAndSettle();
      expect(find.text('Ownership recorded'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey<String>('customer-notifications-button')),
      );
      await tester.pump();

      await tester.ensureVisible(emberCard);
      await tester.tap(emberCard);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Report dispute'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Report dispute'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dispute recorded'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Vault');
      expect(find.text('Ember Archive Crew'), findsOneWidget);
      expect(find.text('Certificate active'), findsAtLeastNWidgets(1));
      expect(find.text('disputed'), findsOneWidget);

      await _tapNav(tester, 'Shop');
      final Finder restrictedCard = find
          .ancestor(
            of: find.text('Restricted Study Hoodie'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.ensureVisible(restrictedCard);
      await tester.tap(restrictedCard);
      await tester.pumpAndSettle();
      expect(find.text('Authorize checkout'), findsNothing);
      expect(find.text('Resell item'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('customer app signs in with an existing collector account', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

  testWidgets(
    'vault owners cannot authorize checkout on their own resale item',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final DemoCatalog repository = DemoCatalog();
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'user_collector_1',
          email: 'owner@example.com',
          displayName: 'Owner Collector',
          username: 'ownercollector',
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

      await _tapNav(tester, 'Vault');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Report dispute'));

      expect(find.text('Authorize checkout'), findsNothing);
      expect(find.text('Resell item'), findsNothing);
    },
  );

  testWidgets(
    'manual payment proof submission shows progress, blocks duplicate submits, and updates status',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Completer<void> gate = Completer<void>();
      final _ControlledManualPaymentDemoCatalog repository =
          _ControlledManualPaymentDemoCatalog(gate: gate);
      int pickerCalls = 0;
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'buyer_manual',
          email: 'buyer@example.com',
          displayName: 'Buyer Collector',
          username: 'buyercollector',
        ),
      );

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const ManualPaymentProvider(),
          ),
          authService: authService,
          paymentProofPicker: () async {
            pickerCalls += 1;
            return SelectedPaymentProof(
              bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
              fileName: 'payment-proof.png',
              contentType: 'image/png',
              sizeBytes: 4,
            );
          },
          enableCameraScanner: false,
        ),
      );
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Start payment'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Start payment'));
      await tester.pumpAndSettle();

      expect(find.text('Manual payment verification'), findsOneWidget);
      expect(find.textContaining('Amount due:'), findsWidgets);

      await _enterField(tester, 'Payer name', 'Buyer Collector');
      await _enterField(tester, 'Payer phone', '09123456789');
      await _enterField(tester, 'Paid amount (MMK)', '180000');
      await _enterField(tester, 'Paid time', '2026-03-28 10:15');
      await _enterField(
        tester,
        'Transaction / reference number (optional)',
        'WAVE-12345',
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Upload payment screenshot'),
      );
      await tester.pumpAndSettle();
      expect(pickerCalls, 1);
      expect(find.text('payment-proof.png'), findsOneWidget);
      expect(find.text('Payment screenshot selected.'), findsOneWidget);

      final Finder submitButton = find.widgetWithText(
        FilledButton,
        'Submit payment proof',
      );
      await tester.tap(submitButton);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.text('Submitting...')));
      await tester.pump();

      expect(repository.submitProofCalls, 1);
      expect(find.text('Submitting...'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Manual payment verification'), findsNothing);
      expect(find.text('Payment verification'), findsOneWidget);
      expect(find.text('under_review'), findsOneWidget);
      expect(
        find.text('Payment proof submitted. Admin review is in progress.'),
        findsOneWidget,
      );
      expect(find.text('Method: WavePay'), findsOneWidget);
      expect(find.text('Payer: Buyer Collector'), findsOneWidget);
      expect(find.text('Phone: 09123456789'), findsOneWidget);
    },
  );

  testWidgets(
    'manual payment sheet can be cancelled and reopened with a continue payment CTA',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final DemoCatalog repository = DemoCatalog();
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'buyer_manual',
          email: 'buyer@example.com',
          displayName: 'Buyer Collector',
          username: 'buyercollector',
        ),
      );

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const ManualPaymentProvider(),
          ),
          authService: authService,
          paymentProofPicker: () async => SelectedPaymentProof(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            fileName: 'proof.png',
            contentType: 'image/png',
            sizeBytes: 3,
          ),
          enableCameraScanner: false,
        ),
      );
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Start payment'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Start payment'));
      await tester.pumpAndSettle();
      expect(find.text('Manual payment verification'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Manual payment verification'), findsNothing);
      expect(find.text('Payment verification'), findsOneWidget);
      expect(find.text('Continue payment'), findsWidgets);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Continue payment'));
      expect(find.text('Continue payment'), findsWidgets);
    },
  );

  testWidgets(
    'manual payment proof picker shows clear validation feedback for invalid files',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final DemoCatalog repository = DemoCatalog();
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'buyer_manual',
          email: 'buyer@example.com',
          displayName: 'Buyer Collector',
          username: 'buyercollector',
        ),
      );

      await tester.pumpWidget(
        OneOfOneCustomerApp(
          repository: repository,
          workflowService: MarketplaceWorkflowService(
            repository: repository,
            paymentProvider: const ManualPaymentProvider(),
          ),
          authService: authService,
          paymentProofPicker: () async => SelectedPaymentProof(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            fileName: 'proof.pdf',
            contentType: 'application/pdf',
            sizeBytes: 3,
          ),
          enableCameraScanner: false,
        ),
      );
      await tester.pumpAndSettle();

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Start payment'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Start payment'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Upload payment screenshot'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Choose a PNG, JPG, WEBP, or GIF screenshot.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Submit payment proof'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'comment composer shows posting feedback, blocks duplicate submits, and renders the real commenter name',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Completer<void> gate = Completer<void>();
      final _ControlledCommentDemoCatalog repository =
          _ControlledCommentDemoCatalog(
            gate: gate,
            commenterName: 'Avery Collector',
          );
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'collector_commenter',
          email: 'avery@example.com',
          displayName: 'Avery Collector',
          username: 'averycollector',
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

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Collector conversation'));

      await _enterField(
        tester,
        'Share your thoughts on this collectible',
        'Love the finish on this release.',
      );

      final Finder postCommentButton = find.widgetWithText(
        FilledButton,
        'Post comment',
      );
      await tester.tap(postCommentButton);
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.text('Posting...')));
      await tester.pump();

      expect(repository.addCommentCalls, 1);
      expect(find.text('Posting...'), findsOneWidget);
      expect(
        find.textContaining('verified collector conversation'),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.text('Comment posted to the collector conversation.'),
        findsOneWidget,
      );
      expect(find.text('Love the finish on this release.'), findsOneWidget);
      expect(find.text('Avery Collector'), findsOneWidget);
    },
  );

  testWidgets(
    'backing out during comment submission does not leave a stuck loading spinner',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Completer<void> gate = Completer<void>();
      final _ControlledCommentDemoCatalog repository =
          _ControlledCommentDemoCatalog(gate: gate);
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'collector_commenter',
          email: 'avery@example.com',
          displayName: 'Avery Collector',
          username: 'averycollector',
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

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Collector conversation'));

      await _enterField(
        tester,
        'Share your thoughts on this collectible',
        'Posting while leaving the screen.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Post comment'));
      await tester.pump();

      expect(repository.addCommentCalls, 1);
      expect(find.text('Posting...'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Collector conversation'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comment composer surfaces failures and allows retry after the request finishes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final Completer<void> gate = Completer<void>()..complete();
      final _ControlledCommentDemoCatalog repository =
          _ControlledCommentDemoCatalog(
            gate: gate,
            failMessage: 'Comment service unavailable right now.',
          );
      final _TestAuthService authService = _TestAuthService(
        initialSession: _buildSession(
          id: 'collector_commenter',
          email: 'avery@example.com',
          displayName: 'Avery Collector',
          username: 'averycollector',
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

      await _tapNav(tester, 'Shop');
      await tester.tap(find.text('Afterglow Hand-Finished Tee').first);
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Collector conversation'));

      await _enterField(
        tester,
        'Share your thoughts on this collectible',
        'This should fail once.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Post comment'));
      await tester.pumpAndSettle();

      expect(
        find.text('Comment service unavailable right now.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Post comment'), findsOneWidget);
      expect(repository.addCommentCalls, 1);
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
    return widget is TextField && widget.decoration?.labelText == label;
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
        message:
            'An account with this email already exists. Try signing in instead.',
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

class _ControlledCommentDemoCatalog extends DemoCatalog {
  _ControlledCommentDemoCatalog({
    required this.gate,
    this.commenterName = 'Avery Collector',
    this.failMessage,
  });

  final Completer<void> gate;
  final String commenterName;
  final String? failMessage;
  final List<ItemComment> _postedComments = <ItemComment>[];

  int addCommentCalls = 0;

  @override
  List<ItemComment> commentsForItem(String itemId) =>
      List<ItemComment>.unmodifiable(<ItemComment>[
        ..._postedComments.where(
          (ItemComment comment) => comment.itemId == itemId,
        ),
        ...super.commentsForItem(itemId),
      ]);

  @override
  Future<MarketplaceActionResult<ItemComment>> addItemComment({
    required String itemId,
    required String body,
  }) async {
    addCommentCalls += 1;
    await gate.future;

    final String trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return const MarketplaceActionResult<ItemComment>(
        success: false,
        message: 'Write a comment before posting.',
      );
    }

    if (failMessage != null) {
      return MarketplaceActionResult<ItemComment>(
        success: false,
        message: failMessage!,
      );
    }

    final ItemComment comment = ItemComment(
      id: 'controlled_comment_$addCommentCalls',
      itemId: itemId,
      userDisplayName: commenterName,
      body: trimmedBody,
      createdAt: DateTime(2026, 3, 28),
    );
    _postedComments.insert(0, comment);
    return MarketplaceActionResult<ItemComment>(
      success: true,
      message: 'Comment posted to the collectible conversation.',
      data: comment,
    );
  }
}

class _ControlledManualPaymentDemoCatalog extends DemoCatalog {
  _ControlledManualPaymentDemoCatalog({required this.gate});

  final Completer<void> gate;
  int submitProofCalls = 0;

  @override
  Future<MarketplaceActionResult<ManualPaymentOrder>> submitManualPaymentProof({
    required String orderId,
    required String paymentMethod,
    required String payerName,
    required String payerPhone,
    required int paidAmountCents,
    required DateTime paidAt,
    required String? transactionReference,
    required Uint8List proofBytes,
    required String proofFileName,
    required String proofContentType,
  }) async {
    submitProofCalls += 1;
    await gate.future;
    return super.submitManualPaymentProof(
      orderId: orderId,
      paymentMethod: paymentMethod,
      payerName: payerName,
      payerPhone: payerPhone,
      paidAmountCents: paidAmountCents,
      paidAt: paidAt,
      transactionReference: transactionReference,
      proofBytes: proofBytes,
      proofFileName: proofFileName,
      proofContentType: proofContentType,
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
