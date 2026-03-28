import 'package:domain/domain.dart';

import 'claim_packet_printer_stub.dart'
    if (dart.library.html) 'claim_packet_printer_web.dart' as printer;

Future<bool> printClaimPacket(AdminClaimPacketData packet) {
  return printer.printClaimPacket(packet);
}
