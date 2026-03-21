import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/src/customer_app.dart';

void main() {
  testWidgets('customer app boots into auth screen without Supabase config', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OneOfOneCustomerApp());
    await tester.pumpAndSettle();

    expect(find.text('Collect the original.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.textContaining('Supabase configuration is required'),
      findsOneWidget,
    );
  });
}
