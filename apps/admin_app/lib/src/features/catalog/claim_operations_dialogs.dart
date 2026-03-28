import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../claim_packet_printer.dart';

Future<String?> promptSensitiveClaimReason(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final TextEditingController reasonController = TextEditingController();
  final String? reason = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      String? validationMessage;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1712),
            title: Text(title),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(body),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Record why this sensitive action is required',
                        errorText: validationMessage,
                      ),
                      onChanged: (_) {
                        if (validationMessage != null) {
                          setDialogState(() {
                            validationMessage = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (reasonController.text.trim().isEmpty) {
                    setDialogState(() {
                      validationMessage = 'Reason is required.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(reasonController.text.trim());
                },
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
  return reason;
}

Future<bool?> showClaimPacketDialog(
  BuildContext context,
  AdminClaimPacketData packet, {
  required String title,
  required String subtitle,
  bool emphasizePrint = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF120F0B),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        title: Text(title),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(subtitle),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F0E2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB8912C), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ONE OF ONE CLAIM PACKET',
                        style: TextStyle(
                          color: Color(0xFF8A6507),
                          letterSpacing: 3,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFE2D0A0)),
                            ),
                            child: QrImageView(
                              data: packet.verificationUri,
                              size: 164,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF101010),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Color(0xFF101010),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  packet.artworkTitle,
                                  style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                                    color: const Color(0xFF16110A),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  packet.artistName,
                                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                                    color: const Color(0xFF4E3A0C),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _ClaimPacketDetailRow(label: 'Serial', value: packet.serialNumber),
                                _ClaimPacketDetailRow(label: 'Garment', value: packet.garmentName),
                                _ClaimPacketDetailRow(label: 'Public QR token', value: packet.publicQrToken),
                                _ClaimPacketDetailRow(label: 'Verification URI', value: packet.verificationUri),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF5D8),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFB8912C), width: 1.4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Hidden claim code',
                              style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                                color: const Color(0xFF4E3A0C),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Keep this code concealed inside the package. Do not place it on the public QR label.',
                              style: TextStyle(color: Color(0xFF46340C)),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              packet.hiddenClaimCode,
                              style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                                color: const Color(0xFF120F0B),
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final bool didPrint = await printClaimPacket(packet);
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.of(dialogContext).pop(didPrint);
            },
            icon: Icon(emphasizePrint ? Icons.print : Icons.local_printshop_outlined),
            label: Text(emphasizePrint ? 'Print packet' : 'Print'),
          ),
        ],
      );
    },
  );
}

class _ClaimPacketDetailRow extends StatelessWidget {
  const _ClaimPacketDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF8A6507),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF120F0B),
            ),
          ),
        ],
      ),
    );
  }
}
