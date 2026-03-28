// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui';

import 'package:domain/domain.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<bool> printClaimPacket(AdminClaimPacketData packet) async {
  final QrPainter painter = QrPainter(
    data: packet.verificationUri,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF101010),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF101010),
    ),
  );
  final ByteData? imageData = await painter.toImageData(560);
  if (imageData == null) {
    return false;
  }

  final String qrBase64 = base64Encode(imageData.buffer.asUint8List());
  final dynamic popup = html.window.open('', '_blank');
  if (popup == null) {
    return false;
  }

  final String escapedCode = const HtmlEscape().convert(packet.hiddenClaimCode);
  final String escapedToken = const HtmlEscape().convert(packet.publicQrToken);
  final String escapedSerial = const HtmlEscape().convert(packet.serialNumber);
  final String escapedArtist = const HtmlEscape().convert(packet.artistName);
  final String escapedArtwork = const HtmlEscape().convert(packet.artworkTitle);
  final String escapedGarment = const HtmlEscape().convert(packet.garmentName);
  final String escapedUri = const HtmlEscape().convert(packet.verificationUri);

  final String htmlMarkup = '''<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>One of One Claim Packet</title>
    <style>
      body { background: #f6f0e2; color: #101010; font-family: Georgia, "Times New Roman", serif; margin: 0; padding: 24px; }
      .packet { border: 2px solid #b8912c; padding: 28px; max-width: 860px; margin: 0 auto; background: #fffaf0; }
      .brand { font-size: 13px; letter-spacing: 0.28em; text-transform: uppercase; color: #7e5d0b; margin-bottom: 20px; }
      .hero { display: flex; gap: 28px; align-items: flex-start; }
      .qr { width: 240px; text-align: center; }
      .qr img { width: 220px; height: 220px; border: 12px solid #f1e6c7; background: white; }
      .meta { flex: 1; }
      h1 { margin: 0 0 10px; font-size: 34px; }
      .label { font-size: 12px; text-transform: uppercase; letter-spacing: 0.16em; color: #7e5d0b; }
      .value { font-size: 18px; margin-top: 4px; }
      .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; margin-top: 16px; }
      .secret { margin-top: 26px; padding: 20px; border: 2px dashed #b8912c; background: #fff4d5; }
      .secret .code { margin-top: 12px; font-size: 28px; letter-spacing: 0.12em; font-weight: 700; }
      .note { margin-top: 20px; font-size: 14px; line-height: 1.6; }
    </style>
  </head>
  <body>
    <div class="packet">
      <div class="brand">One of One Claim Packet</div>
      <div class="hero">
        <div class="qr">
          <img src="data:image/png;base64,$qrBase64" alt="Verification QR" />
          <div class="note">Scan this verification QR in One of One or enter the token manually.</div>
        </div>
        <div class="meta">
          <h1>$escapedArtwork</h1>
          <div class="value">$escapedArtist</div>
          <div class="grid">
            <div><div class="label">Serial number</div><div class="value">$escapedSerial</div></div>
            <div><div class="label">Garment</div><div class="value">$escapedGarment</div></div>
            <div><div class="label">Public QR token</div><div class="value">$escapedToken</div></div>
            <div><div class="label">Verification URI</div><div class="value">$escapedUri</div></div>
          </div>
          <div class="secret">
            <div class="label">Hidden claim code</div>
            <div class="note">Keep this section concealed inside the package. The public QR token and the hidden claim code must stay separate.</div>
            <div class="code">$escapedCode</div>
          </div>
        </div>
      </div>
    </div>
    <script>window.focus(); window.print();</script>
  </body>
</html>''';

  popup.document.write(htmlMarkup);
  popup.document.close();
  return true;
}
