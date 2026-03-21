import 'package:admin_app/src/admin_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin app shows configuration state without Supabase config', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OneOfOneAdminApp());
    await tester.pumpAndSettle();

    expect(find.text('Admin configuration required'), findsOneWidget);
    expect(
      find.textContaining('Provide SUPABASE_URL and SUPABASE_ANON_KEY'),
      findsOneWidget,
    );
  });
}
