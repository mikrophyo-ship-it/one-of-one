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

    final PaymentIntentResult payment = await _paymentProvider.charge(
      orderId: 'order-$itemId-$buyerUserId',
      amount: item.askingPrice!,
    );
    if (!payment.success) {
      return const MarketplaceActionResult<UniqueItem>(
        success: false,
        message: 'Payment failed. Ownership remains unchanged.',
      );
    }

    return _repository.buyResaleItem(
      itemId: itemId,
      buyerUserId: buyerUserId,
      providerReference: payment.reference,
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
