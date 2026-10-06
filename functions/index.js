/**
 * SwidShop Cloud Functions — Node.js 20 runtime.
 *
 * Responsibilities:
 *  1. trust-badge  : recompute a seller's rating/completion stats and award
 *                    the "Trusted" badge.
 *  2. auction-close: close expired auctions and create the winning transaction.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
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

// ---------------------------------------------------------------------------
// Demo monetization — WRITTEN BUT NOT DEPLOYED YET (professor's rule).
// The app runs the same logic client-side (FirestoreService.
// runSellerMaintenance when a seller opens the Seller Centre), so the demo
// works without these. Keep the numbers in sync with lib/core/constants.dart.
// ---------------------------------------------------------------------------

const FEE_RATES = { free: 0.05, plus: 0.04, pro: 0.03 };
const FEE_DUE_DAYS = 7;
const FEE_REMINDER_DAYS = [1, 3, 6];
const DAY_MS = 86400000;

/** Plan that applies now: a lapsed (or unknown) plan counts as free. */
function effectivePlan(user) {
  const plan = (user && user.plan) || "free";
  if (plan !== "plus" && plan !== "pro") return "free";
  const until = user.planUntil && user.planUntil.toDate
    ? user.planUntil.toDate()
    : null;
  if (until && until.getTime() <= Date.now()) return "free";
  return plan;
}

/** Fee in pesos rounded to centavos (same as Fees.amountFor in Dart). */
function feeFor(amount, rate) {
  return Math.round(amount * rate * 100) / 100;
}

/** In-app notification doc (same shape as NotificationModel). */
async function notify(uid, message, relatedId) {
  await db
    .collection("notifications")
    .doc(uid)
    .collection("items")
    .add({
      type: "transactionUpdate",
      message,
      relatedId,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

/** Push to the seller's device (token saved privately by the app). */
async function push(uid, title, body, relatedId) {
  try {
    const priv = await db
      .collection("users")
      .doc(uid)
      .collection("private")
      .doc("details")
      .get();
    const token = priv.exists ? priv.get("fcmToken") : null;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: { relatedId },
      android: { priority: "high" },
    });
  } catch (e) {
    // Stale/invalid token or no Play services: in-app notice still exists.
    logger.warn("push failed", { uid, error: String(e) });
  }
}

/** Sets `hidden` on a seller's ACTIVE listings (batched). */
async function setListingsHidden(sellerId, hidden) {
  const mine = await db
    .collection("listings")
    .where("sellerId", "==", sellerId)
    .where("status", "==", "active")
    .get();
  const docs = mine.docs.filter((d) => (d.get("hidden") === true) !== hidden);
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach((d) => batch.update(d.ref, { hidden }));
    await batch.commit();
  }
}

/**
 * Daily: push + in-app reminder for each unpaid fee on days 1/3/6 after
 * the deal, and every day once overdue. Then applies the automatic fee
 * hold (overdue → on_hold + hide listings) and lifts it when nothing is
 * overdue any more. Never touches suspended/banned accounts, and never
 * lifts an admin's manual hold (holdManual).
 */
exports.feeReminders = onSchedule(
  { schedule: "every day 09:00", timeZone: "Asia/Manila" },
  async () => {
    const now = Date.now();
    const unpaid = await db
      .collection("transactions")
      .where("feeStatus", "==", "unpaid")
      .get();
    logger.info(`feeReminders: ${unpaid.size} unpaid fee(s) to check`);

    const overdueSellers = new Set();
    for (const doc of unpaid.docs) {
      const t = doc.data();
      if (t.status === "cancelled" || !t.sellerId) continue;
      const created = t.createdAt && t.createdAt.toDate
        ? t.createdAt.toDate()
        : null;
      const due = t.feeDueAt && t.feeDueAt.toDate ? t.feeDueAt.toDate() : null;
      if (!created) continue;
      const ageDays = Math.floor((now - created.getTime()) / DAY_MS);
      const overdue = !!due && due.getTime() <= now;
      if (overdue) overdueSellers.add(t.sellerId);
      if (!overdue && !FEE_REMINDER_DAYS.includes(ageDays)) continue;

      const title = t.listingTitle ? `"${t.listingTitle}"` : "a deal";
      const amount = `₱${Number(t.feeAmount || 0).toFixed(2)}`;
      const dueText = due
        ? due.toLocaleDateString("en-PH", {
          month: "short",
          day: "numeric",
          timeZone: "Asia/Manila",
        })
        : "soon";
      const message = overdue
        ? `Platform fee ${amount} for ${title} is OVERDUE — pay now to ` +
          "lift the hold on your shop."
        : `Reminder: platform fee ${amount} for ${title} is due ${dueText}.`;
      const relatedId = `transaction:${doc.id}`;
      await notify(t.sellerId, message, relatedId);
      await push(
        t.sellerId,
        overdue ? "Platform fee overdue" : "Platform fee reminder",
        message,
        relatedId
      );
    }

    // Apply holds.
    for (const sellerId of overdueSellers) {
      const ref = db.collection("users").doc(sellerId);
      const snap = await ref.get();
      if (!snap.exists) continue;
      const status = snap.get("accountStatus") || "active";
      if (status !== "active") continue; // never replace suspended/banned
      await ref.update({ accountStatus: "on_hold" });
      await setListingsHidden(sellerId, true);
    }

    // Lift automatic holds with nothing overdue left.
    const held = await db
      .collection("users")
      .where("accountStatus", "==", "on_hold")
      .get();
    for (const doc of held.docs) {
      if (doc.get("holdManual") === true) continue;
      if (overdueSellers.has(doc.id)) continue;
      await doc.ref.update({ accountStatus: "active" });
      await setListingsHidden(doc.id, false);
    }
    logger.info(
      `feeReminders: done (${overdueSellers.size} seller(s) overdue)`
    );
    return null;
  }
);

/**
 * Hourly: clear expired boosts / featured slots / highlights, reset lapsed
 * plans to free, and switch ended partner ads off.
 */
exports.expirePerks = onSchedule("every hour", async () => {
  const now = admin.firestore.Timestamp.now();
  let cleared = 0;

  const boosted = await db
    .collection("users")
    .where("boostedUntil", "<=", now)
    .get();
  for (const doc of boosted.docs) {
    await doc.ref.update({ boostedUntil: null });
    cleared++;
  }

  for (const field of ["featuredUntil", "highlightUntil"]) {
    const ended = await db
      .collection("listings")
      .where(field, "<=", now)
      .get();
    for (const doc of ended.docs) {
      await doc.ref.update({ [field]: null });
      cleared++;
    }
  }

  const lapsed = await db
    .collection("users")
    .where("planUntil", "<=", now)
    .get();
  for (const doc of lapsed.docs) {
    if ((doc.get("plan") || "free") !== "free") {
      await doc.ref.update({ plan: "free", planUntil: null });
      cleared++;
    }
  }

  const ads = await db
    .collection("partnerAds")
    .where("active", "==", true)
    .get();
  for (const doc of ads.docs) {
    const end = doc.get("endsAt");
    if (end && end.toMillis() <= now.toMillis()) {
      await doc.ref.update({ active: false });
      cleared++;
    }
  }

  logger.info(`expirePerks: cleared ${cleared} perk(s)`);
  return null;
});

/**
 * Scheduled: close auctions whose `auctionEndAt` has passed and create a
 * winning transaction for the highest bid (if any), with the platform fee
 * stamped at the seller's plan rate (needs the listings type+status+
 * auctionEndAt composite index in firestore.indexes.json).
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
      // ALL reads before any write (Firestore transaction rule).
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.get("status") !== "active") return;
      const listing = fresh.data();
      const sellerDoc = listing.sellerId
        ? await tx.get(db.collection("users").doc(listing.sellerId))
        : null;

      const winningBid = bidsSnap.empty ? null : bidsSnap.docs[0].data();
      const reserve = listing.reservePrice;
      // No bids, or hidden reserve not met → ends unsold.
      if (!winningBid || (reserve != null && winningBid.amount < reserve)) {
        tx.update(doc.ref, { status: "expired" });
        return;
      }

      const plan = effectivePlan(
        sellerDoc && sellerDoc.exists ? sellerDoc.data() : null
      );
      const feeRate = FEE_RATES[plan] ?? FEE_RATES.free;
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
        swapItemTitle: "",
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        feeRate,
        feeAmount: feeFor(winningBid.amount, feeRate),
        feeStatus: "unpaid",
        feeDueAt: admin.firestore.Timestamp.fromMillis(
          Date.now() + FEE_DUE_DAYS * DAY_MS
        ),
        paidAt: null,
      });
    });
  }
  return null;
});
