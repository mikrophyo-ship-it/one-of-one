import 'dart:async';

import 'package:app_links/app_links.dart';

abstract class AuthenticityLinkSource {
  Future<Uri?> getInitialUri();

  Stream<Uri> get uriStream;
}

class AppAuthenticityLinkSource implements AuthenticityLinkSource {
  AppAuthenticityLinkSource({AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  @override
  Future<Uri?> getInitialUri() async {
    try {
      return await _appLinks.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Uri> get uriStream => _appLinks.uriLinkStream.handleError((_) {});
}

class FakeAuthenticityLinkSource implements AuthenticityLinkSource {
  FakeAuthenticityLinkSource({
    Uri? initialUri,
    Stream<Uri>? uriStream,
  }) : _initialUri = initialUri,
       _uriStream = uriStream ?? const Stream<Uri>.empty();

  final Uri? _initialUri;
  final Stream<Uri> _uriStream;

  @override
  Future<Uri?> getInitialUri() async => _initialUri;

  @override
  Stream<Uri> get uriStream => _uriStream;
}
