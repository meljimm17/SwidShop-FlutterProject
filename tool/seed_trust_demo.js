// Trusted Seller demo top-up — run with: node tool/seed_trust_demo.js
//   optional: node tool/seed_trust_demo.js "Seller Name" 10
//
// Gives ONE seller enough real completed deals (each with its own sold
// listing, chat thread and a 5★ buyer rating) to meet the Trusted Seller
// rules (AppConstants.trustedMin*: 10 deals, 90%+ completion, 4.5★+, no
// unresolved reports), WITHOUT re-running the whole seed.
//
// - Deterministic ids (`seed-*-trust-<uid>-NN`): re-runs add nothing once
//   the seller already has enough completed deals.
// - Resets every existing badge to false: under the 10-deal rule the badge
//   is awarded by an admin only (User Detail → Award Trusted Seller Badge).
// - Leaves `trustedBadgeEligible` false on purpose. The next time the admin
//   console opens, the in-app trust check flags the seller and sends the
//   admin a notification — that is the flow to demo.
//
// Writes LIVE Firestore (open rules for class testing). DELETE THIS FILE
// before any real release, together with tool/seed_demo.js.

const API_KEY = 'AIzaSyCbR6mPi5JcuvmBr_4ZDRwyq_CyDrbo01Q';
const PROJECT = 'swidshop-d8ccf';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const NAME = process.argv[2] || 'Enrico Ocampo';
const TARGET = Number(process.argv[3] || 10);
const COMMENTS = [
  'Smooth deal, item as described!',
  'Fast handover, friendly seller.',
  'Legit seller, will buy again.',
  'Exactly like the photos. Thank you!',
];

const S = (v) => ({ stringValue: v });
const N = (v) => (Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v });
const B = (v) => ({ booleanValue: v });
const TS = (d) => ({ timestampValue: d.toISOString() });
const str = (doc, f) => doc.fields?.[f]?.stringValue;
const idOf = (doc) => doc.name.split('/').pop();

async function listAll(collection) {
  const out = [];
  let token = '';
  do {
    const res = await fetch(
      `${BASE}/${collection}?key=${API_KEY}&pageSize=300${token ? `&pageToken=${token}` : ''}`,
    );
    if (!res.ok) throw new Error(`list ${collection}: ${res.status}`);
    const data = await res.json();
    out.push(...(data.documents || []));
    token = data.nextPageToken || '';
  } while (token);
  return out;
}

async function put(collection, id, fields, mask) {
  let url = `${BASE}/${collection}/${id}?key=${API_KEY}`;
  if (mask) {
    for (const f of mask) url += `&updateMask.fieldPaths=${encodeURIComponent(f)}`;
  }
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) throw new Error(`${collection}/${id}: ${res.status} ${await res.text()}`);
}

async function main() {
  const [users, listings, txns, ratings] = await Promise.all(
    ['users', 'listings', 'transactions', 'ratings'].map(listAll),
  );
  const seller = users.find((u) => str(u, 'name') === NAME);
  if (!seller) throw new Error(`No user named "${NAME}".`);
  const uid = idOf(seller);
  if (str(seller, 'role') !== 'both') {
    throw new Error(`${NAME} is not a Customer + Seller account.`);
  }

  // 1. Badges are admin-awarded from now on: clear every existing one.
  for (const u of users) {
    if (u.fields?.trustedBadge?.booleanValue !== true) continue;
    await put(
      'users',
      idOf(u),
      { trustedBadge: B(false), trustedBadgeEligible: B(false), trustedEligibilityNotified: B(false) },
      ['trustedBadge', 'trustedBadgeEligible', 'trustedEligibilityNotified'],
    );
    console.log(`badge cleared: ${str(u, 'name')}`);
  }

  // 2. Top up completed deals.
  const mine = txns.filter((t) => str(t, 'sellerId') === uid);
  const completed = mine.filter((t) => str(t, 'status') === 'completed').length;
  const need = Math.max(0, TARGET - completed);
  const template = listings.find(
    (l) => str(l, 'sellerId') === uid && str(l, 'type') === 'buyNow',
  ) || listings.find((l) => str(l, 'sellerId') === uid);
  if (need > 0 && !template) throw new Error(`${NAME} has no listing to copy.`);
  const buyers = users.filter(
    (u) => idOf(u) !== uid &&
      ['customer', 'both'].includes(str(u, 'role')) &&
      (str(u, 'accountStatus') || 'active') === 'active' &&
      idOf(u).startsWith('seed-user-'),
  );
  const tag = uid.replace(/[^A-Za-z0-9]/g, '');
  for (let i = 0; i < need; i++) {
    const n = String(completed + i + 1).padStart(2, '0');
    const listingId = `seed-listing-trust-${tag}-${n}`;
    const txnId = `seed-txn-trust-${tag}-${n}`;
    const ratingId = `seed-rating-trust-${tag}-${n}`;
    const buyer = buyers[i % buyers.length];
    const when = new Date(Date.now() - (i + 2) * 86400000);
    const price = 400 + 150 * (i + 1);
    const title = `${(str(template, 'title') || 'Pre-loved item').replace(/ #\d+$/, '')} #T${n}`;
    const image = template.fields.images?.arrayValue?.values?.[0]?.stringValue || '';

    const fields = { ...template.fields };
    for (const f of ['featuredUntil', 'featuredPaymentId', 'highlightUntil', 'bumpedAt', 'hidden', 'currentHighestBid', 'highestBidderId', 'bidCount', 'photoLimit']) {
      delete fields[f];
    }
    await put('listings', listingId, {
      ...fields,
      listingId: S(listingId),
      title: S(title),
      type: S('buyNow'),
      price: N(price),
      status: S('sold'),
      createdAt: TS(new Date(when.getTime() - 3 * 86400000)),
    });
    await put('transactions', txnId, {
      transactionId: S(txnId),
      listingId: S(listingId),
      buyerId: S(idOf(buyer)),
      sellerId: S(uid),
      type: S('buyNow'),
      amount: N(price),
      listingTitle: S(title),
      listingImage: S(image),
      offerId: S(''),
      swapItemTitle: S(''),
      status: S('completed'),
      createdAt: TS(when),
    });
    await put('chats', txnId, {
      transactionId: S(txnId),
      buyerId: S(idOf(buyer)),
      sellerId: S(uid),
      listingId: S(listingId),
      createdAt: TS(when),
    });
    await put('ratings', ratingId, {
      ratingId: S(ratingId),
      raterId: S(idOf(buyer)),
      ratedUserId: S(uid),
      transactionId: S(txnId),
      stars: N(5),
      comment: S(COMMENTS[i % COMMENTS.length]),
      createdAt: TS(new Date(when.getTime() + 3600000)),
    });
    console.log(`deal ${n}: ${title} → ${str(buyer, 'name')} (5★)`);
  }

  // 3. Store the honest aggregates (same math as the app / function).
  const deals = [...mine.map((t) => str(t, 'status')), ...Array(need).fill('completed')];
  const done = deals.filter((s) => s === 'completed').length;
  const resolved = deals.filter((s) => ['completed', 'cancelled', 'disputed'].includes(s)).length;
  const stars = [
    ...ratings.filter((r) => str(r, 'ratedUserId') === uid)
      .map((r) => Number(r.fields.stars?.integerValue ?? r.fields.stars?.doubleValue ?? 0)),
    ...Array(need).fill(5),
  ];
  const avg = stars.length ? stars.reduce((a, b) => a + b, 0) / stars.length : 0;
  const rate = resolved ? done / resolved : 0;
  await put(
    'users',
    uid,
    {
      avgRating: N(Math.round(avg * 10) / 10),
      completedTransactions: N(done),
      completionRate: N(rate),
      trustedBadge: B(false),
      trustedBadgeEligible: B(false),
      trustedEligibilityNotified: B(false),
    },
    ['avgRating', 'completedTransactions', 'completionRate', 'trustedBadge', 'trustedBadgeEligible', 'trustedEligibilityNotified'],
  );
  console.log(
    `\n${NAME}: ${done} completed deals, ${(rate * 100).toFixed(0)}% completion, ` +
    `${avg.toFixed(2)}★ (${stars.length} ratings). Added ${need} deal(s).`,
  );
  console.log('Open the admin console: the trust check flags the seller and notifies the admin.');
}

main().catch((e) => {
  console.error('TRUST SEED FAILED:', e.message);
  process.exit(1);
});
