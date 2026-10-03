/**
 * SwidShop Cloud Functions — Node.js 20 runtime.
 *
 * Responsibilities:
 *  1. trust-badge  : recompute a seller's rating/completion stats and award
 *                    the "Trusted" badge.
 *  2. auction-close: close expired auctions and create the winning transaction.
 */
const { onCall, onSchedule, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Trust thresholds for awarding the badge.
const TRUST = {
  minCompletedTransactions: 5,
  minCompletionRate: 0.9,
  minAvgRating: 4.5,
};

/**
 * Recomputes a user's aggregate stats (avgRating, completedTransactions,
 * completionRate) and sets `trustedBadge` when thresholds are met.
 */
async function recomputeTrust(uid) {
  const ratingsSnap = await db
    .collection("ratings")
    .where("ratedUserId", "==", uid)
    .get();

  let sum = 0;
  ratingsSnap.forEach((doc) => {
    sum += Number(doc.get("stars") || 0);
  });
  const avgRating = ratingsSnap.size > 0 ? sum / ratingsSnap.size : 0;

  const txnsSnap = await db
    .collection("transactions")
    .where("sellerId", "==", uid)
    .get();

  let completed = 0;
  let resolved = 0;
  txnsSnap.forEach((doc) => {
    const status = doc.get("status");
    if (status === "completed") {
      completed += 1;
      resolved += 1;
    } else if (status === "cancelled" || status === "disputed") {
      resolved += 1;
    }
  });

  const completionRate = resolved > 0 ? completed / resolved : 0;
  const trustedBadge =
    completed >= TRUST.minCompletedTransactions &&
    completionRate >= TRUST.minCompletionRate &&
    avgRating >= TRUST.minAvgRating;

  await db.collection("users").doc(uid).set(
    {
      avgRating: Math.round(avgRating * 10) / 10,
      completedTransactions: completed,
      completionRate,
      trustedBadge,
    },
    { merge: true }
  );

  logger.info("recomputeTrust", { uid, avgRating, completed, completionRate, trustedBadge });
  return { avgRating, completed, completionRate, trustedBadge };
}

/**
 * Callable: recompute a user's trust stats.
 * Payload: { uid }  (defaults to the caller's uid)
 */
exports.computeTrustBadge = onCall(async (request) => {
  const uid = (request.data && request.data.uid) || request.auth?.uid;
  if (!uid) {
    throw new HttpsError("invalid-argument", "A uid is required.");
  }
  return recomputeTrust(uid);
});

/**
 * Firestore trigger: when a transaction's status changes, refresh the trust
 * stats of both parties.
 */
exports.onTransactionWritten = onDocumentWritten(
  "transactions/{transactionId}",
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    const { buyerId, sellerId } = after;
    const tasks = [];
    if (sellerId) tasks.push(recomputeTrust(sellerId));
    if (buyerId) tasks.push(recomputeTrust(buyerId));
    await Promise.all(tasks);
  }
);

/**
 * Scheduled: close auctions whose `auctionEndAt` has passed and create a
 * winning transaction for the highest bid (if any).
 */
exports.closeAuctions = onSchedule("every 15 minutes", async () => {
  const now = admin.firestore.Timestamp.now();
  const expired = await db
    .collection("listings")
    .where("type", "==", "bid")
    .where("status", "==", "active")
    .where("auctionEndAt", "<=", now)
    .get();

  logger.info(`closeAuctions: ${expired.size} listing(s) to close`);

  for (const doc of expired.docs) {
    const bidsSnap = await db
      .collection("bids")
      .where("listingId", "==", doc.id)
      .orderBy("amount", "desc")
      .limit(1)
      .get();

    // Same fixed id and in-transaction status check as the app's
    // FirestoreService.closeAuctionIfEnded, so whichever runs first wins
    // and the other is a no-op (no duplicate transactions).
    const txnRef = db.collection("transactions").doc(`auction_${doc.id}`);
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.get("status") !== "active") return;
      const listing = fresh.data();

      const winningBid = bidsSnap.empty ? null : bidsSnap.docs[0].data();
      const reserve = listing.reservePrice;
      // No bids, or hidden reserve not met → ends unsold.
      if (!winningBid || (reserve != null && winningBid.amount < reserve)) {
        tx.update(doc.ref, { status: "expired" });
        return;
      }

      tx.update(doc.ref, {
        status: "sold",
        currentHighestBid: winningBid.amount,
      });
      tx.set(txnRef, {
        transactionId: txnRef.id,
        listingId: doc.id,
        buyerId: winningBid.bidderId,
        sellerId: listing.sellerId,
        type: "bid",
        amount: winningBid.amount,
        listingTitle: listing.title || "",
        listingImage: (listing.images && listing.images[0]) || "",
        offerId: "",
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
});
