import 'package:flutter_test/flutter_test.dart';
import 'package:services/services.dart';

void main() {
  test('parses a raw QR token', () {
    final AuthenticityRouteMatch? match = AuthenticityRouteParser.parseRaw(
      'qr_afterglow_01',
    );

    expect(match, isNotNull);
    expect(match!.qrToken, 'qr_afterglow_01');
    expect(match.sourceUri, isNull);
  });

  test('parses a public authenticity link query parameter', () {
    final AuthenticityRouteMatch? match = AuthenticityRouteParser.parseRaw(
      'https://oneofone.test/authenticity?qr=qr_ember_02',
    );

    expect(match, isNotNull);
    expect(match!.qrToken, 'qr_ember_02');
    expect(match.sourceUri, isNotNull);
  });

  test('parses a custom-scheme deep link', () {
    final AuthenticityRouteMatch? match = AuthenticityRouteParser.parseUri(
      Uri.parse('oneofone://authenticity/item?token=qr_restricted_03'),
    );

    expect(match, isNotNull);
    expect(match!.qrToken, 'qr_restricted_03');
  });

  test('rejects empty or whitespace-only input', () {
    expect(AuthenticityRouteParser.parseRaw('   '), isNull);
  });
}
