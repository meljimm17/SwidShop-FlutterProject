import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/listing_model.dart';
import '../../models/notification_model.dart';
import '../../models/swap_offer_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/auth_widgets.dart';
import '../shared/transaction_chat_screen.dart';

/// Confirms, then accepts [offer]: other pending offers on the listing are
/// declined, the listing is sold, a swap deal is created and its chat opens.
/// Returns true when accepted.
Future<bool> acceptSwapOfferFlow(
  BuildContext context, {
  required SwapOfferModel offer,
  required ListingModel? mine,
  required int otherPendingOnListing,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Accept this swap?'),
      content: Text(
        [
          '"${mine?.title ?? 'Your item'}" will be marked as sold.',
          if (otherPendingOnListing > 0)
            '$otherPendingOnListing other pending '
                'offer${otherPendingOnListing == 1 ? '' : 's'} on it will be '
                'declined automatically.',
        ].join(' '),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(d).pop(true),
          child: const Text('Accept'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  try {
    final txnId = await FirestoreService().acceptSwapOffer(offer);
    // Notify the buyer (their Activity + chat entry point).
    try {
      await FirestoreService().addNotification(
        offer.offeredById,
        NotificationModel(
          type: NotificationType.swapAccepted,
          message:
              'Your swap offer for "${mine?.title ?? 'the item'}" was accepted!',
          relatedId: 'transaction:$txnId',
        ),
      );
    } catch (e) {
      debugPrint('notifySwapAccepted: $e');
    }
    if (!context.mounted) return true;
    await showSuccessPopup(
      context,
      title: 'Swap accepted',
      message: 'Opening your chat to arrange the exchange.',
    );
    if (!context.mounted) return true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionChatScreen(transactionId: txnId),
      ),
    );
    return true;
  } catch (e) {
    debugPrint('acceptSwapOffer: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError ? e.message : 'Could not accept. Try again.',
          ),
          backgroundColor: AppColors.red,
        ),
      );
    }
    return false;
  }
}

/// Declines [offer] (status only) and notifies the offerer.
/// Returns true on success.
Future<bool> declineSwapOffer(
  BuildContext context,
  SwapOfferModel offer,
) async {
  try {
    await FirestoreService().updateSwapOfferStatus(
      offer.offerId,
      SwapOfferStatus.declined,
    );
    try {
      await FirestoreService().addNotification(
        offer.offeredById,
        NotificationModel(
          type: NotificationType.swapOffer,
          message: 'Your swap offer was declined by the seller.',
          relatedId: 'offer:${offer.offerId}',
        ),
      );
    } catch (e) {
      debugPrint('notifySwapDeclined: $e');
    }
    return true;
  } catch (e) {
    debugPrint('declineSwapOffer: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not decline. Try again.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
    return false;
  }
}
