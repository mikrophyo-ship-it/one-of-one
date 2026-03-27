class AuthenticityRouteMatch {
  const AuthenticityRouteMatch({
    required this.qrToken,
    required this.rawInput,
    this.sourceUri,
  });

  final String qrToken;
  final String rawInput;
  final Uri? sourceUri;
}

class AuthenticityRouteParser {
  const AuthenticityRouteParser._();

  static const List<String> _tokenParameterNames = <String>[
    'qr',
    'qr_token',
    'token',
    'authenticity',
  ];

  static AuthenticityRouteMatch? parseRaw(String rawInput) {
    final String trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final Uri? parsedUri = Uri.tryParse(trimmed);
    if (parsedUri != null && parsedUri.scheme.isNotEmpty) {
      final AuthenticityRouteMatch? fromUri = parseUri(parsedUri);
      if (fromUri != null) {
        return fromUri;
      }
    }

    final String? token = _normalizeToken(trimmed);
    if (token == null) {
      return null;
    }
    return AuthenticityRouteMatch(qrToken: token, rawInput: trimmed);
  }

  static AuthenticityRouteMatch? parseUri(Uri uri) {
    final String? tokenFromQuery = _extractTokenFromMap(uri.queryParameters);
    if (tokenFromQuery != null) {
      return AuthenticityRouteMatch(
        qrToken: tokenFromQuery,
        rawInput: uri.toString(),
        sourceUri: uri,
      );
    }

    if (uri.fragment.isNotEmpty) {
      final Uri fragmentUri = Uri.parse(
        uri.fragment.startsWith('?') ? uri.fragment : '?${uri.fragment}',
      );
      final String? tokenFromFragment = _extractTokenFromMap(
        fragmentUri.queryParameters,
      );
      if (tokenFromFragment != null) {
        return AuthenticityRouteMatch(
          qrToken: tokenFromFragment,
          rawInput: uri.toString(),
          sourceUri: uri,
        );
      }
    }

    if (uri.pathSegments.isNotEmpty) {
      final int authenticityIndex = uri.pathSegments.lastIndexOf('authenticity');
      if (authenticityIndex != -1 &&
          authenticityIndex + 1 < uri.pathSegments.length) {
        final String? pathToken = _normalizeToken(
          uri.pathSegments[authenticityIndex + 1],
        );
        if (pathToken != null) {
          return AuthenticityRouteMatch(
            qrToken: pathToken,
            rawInput: uri.toString(),
            sourceUri: uri,
          );
        }
      }

      final String? trailingToken = _normalizeToken(uri.pathSegments.last);
      if (trailingToken != null) {
        return AuthenticityRouteMatch(
          qrToken: trailingToken,
          rawInput: uri.toString(),
          sourceUri: uri,
        );
      }
    }

    return null;
  }

  static String? _extractTokenFromMap(Map<String, String> parameters) {
    for (final String name in _tokenParameterNames) {
      final String? value = parameters[name];
      final String? normalized = _normalizeToken(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  static String? _normalizeToken(String? value) {
    if (value == null) {
      return null;
    }

    final String trimmed = Uri.decodeComponent(value.trim());
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }

    return trimmed;
  }
}
