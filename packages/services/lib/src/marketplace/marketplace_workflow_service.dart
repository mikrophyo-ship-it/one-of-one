import 'package:data/data.dart';
import 'package:domain/domain.dart';

import '../payments/payment_provider.dart';

class MarketplaceWorkflowService {
  const MarketplaceWorkflowService({
    required MarketplaceRepository repository,
    required PaymentProvider paymentProvider,
  }) : _repository = repository,
       _paymentProvider = paymentProvider;

  final MarketplaceRepository _repository;
  final PaymentProvider _paymentProvider;

  Future<MarketplaceActionResult<PublicAuthenticityRecord>>
  lookupPublicAuthenticity({required String qrToken}) async {
    return _repository.lookupPublicAuthenticity(qrToken: qrToken);
  }

  Future<MarketplaceActionResult<UniqueItem>> claimOwnership({
    required String itemId,
    required String claimCode,
    required String userId,
  }) async {
    return _repository.claimOwnership(
      itemId: itemId,
      claimCode: claimCode,
      userId: userId,
    );
  }

  Future<MarketplaceActionResult<UniqueItem>> claimOwnershipByQrToken({
    required String qrToken,
    required String claimCode,
    required String userId,
  }) async {
    return _repository.claimOwnershipByQrToken(
      qrToken: qrToken,
      claimCode: claimCode,
      userId: userId,
    );
  }

  Future<MarketplaceActionResult<Listing>> createResaleListing({
    required String itemId,
    required String userId,
    required int priceCents,
  }) async {
    return _repository.createResaleListing(
      itemId: itemId,
      userId: userId,
      priceCents: priceCents,
    );
  }

  Future<MarketplaceActionResult<ResaleCheckoutSession>> startResaleCheckout({
    required String itemId,
    required String buyerUserId,
    String? successUrl,
    String? cancelUrl,
  }) {
    return _repository.startResaleCheckout(
      itemId: itemId,
      buyerUserId: buyerUserId,
      provider: _paymentProvider.providerKey,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );
  }

  Future<MarketplaceActionResult<UniqueItem>> finalizeResaleCheckout({
    required String orderId,
    required String buyerUserId,
    required String providerReference,
    required int amountCents,
  }) {
    return _repository.finalizeResaleCheckout(
      orderId: orderId,
      buyerUserId: buyerUserId,
      provider: _paymentProvider.providerKey,
      providerReference: providerReference,
      amountCents: amountCents,
    );
  }

  Future<MarketplaceActionResult<ShipmentEvent>> recordShipmentEvent({
    required String orderId,
    required String shipmentStatus,
    String? carrier,
    String? trackingNumber,
    String? note,
  }) {
    return _repository.recordShipmentEvent(
      orderId: orderId,
      shipmentStatus: shipmentStatus,
      carrier: carrier,
      trackingNumber: trackingNumber,
      note: note,
    );
  }

  Future<MarketplaceActionResult<UniqueItem>> confirmDelivery({
    required String orderId,
    required String userId,
    String? note,
  }) {
    return _repository.confirmDelivery(
      orderId: orderId,
      userId: userId,
      note: note,
    );
  }

  Future<MarketplaceActionResult<RefundRecord>> issueRefund({
    required String orderId,
    required int amountCents,
    required String reason,
    String? note,
  }) {
    return _repository.issueRefund(
      orderId: orderId,
      amountCents: amountCents,
      reason: reason,
      note: note,
    );
  }

  Future<MarketplaceActionResult<List<SavedCollectible>>> fetchSavedItems() {
    return _repository.fetchSavedItems();
  }

  Future<MarketplaceActionResult<List<CollectorNotification>>>
  fetchNotifications() {
    return _repository.fetchNotifications();
  }

  Future<MarketplaceActionResult<void>> saveItem({required String itemId}) {
    return _repository.saveItem(itemId: itemId);
  }

  Future<MarketplaceActionResult<void>> removeSavedItem({required String itemId}) {
    return _repository.removeSavedItem(itemId: itemId);
  }

  Future<MarketplaceActionResult<UniqueItem>> buyResaleItem({
    required String itemId,
    required String buyerUserId,
  }) async {
    final UniqueItem? item = _repository.itemById(itemId);
    if (item == null || item.askingPrice == null) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Item is not available for resale checkout.',
      );
    }

    final MarketplaceActionResult<ResaleCheckoutSession> checkout =
        await startResaleCheckout(itemId: itemId, buyerUserId: buyerUserId);
    if (!checkout.success || checkout.data == null) {
      return MarketplaceActionResult<UniqueItem>(
        success: false,
        message: checkout.message,
      );
    }

    return finalizeResaleCheckout(
      orderId: checkout.data!.orderId,
      buyerUserId: buyerUserId,
      providerReference: checkout.data!.providerReference,
      amountCents: item.askingPrice!,
    );
  }

  Future<MarketplaceActionResult<UniqueItem>> openDispute({
    required String itemId,
    required String userId,
    required String reason,
    required bool freeze,
  }) async {
    return _repository.openDispute(
      itemId: itemId,
      userId: userId,
      reason: reason,
      freeze: freeze,
    );
  }
}
