// Demo dataset seeder — Phase 3/4 showcase data (class testing only).
//
// Usage:  node tool/seed_demo.js            (writes everything)
//         node tool/seed_demo.js --dry-run   (prints what would be written)
//
// - Talks to live Firestore via REST (works because live rules are open).
// - Every doc uses a deterministic `seed-*` id, so re-runs OVERWRITE
//   instead of duplicating. Safe to run twice.
// - Aggregates are DERIVED, not invented: completedTransactions counts real
//   completed seller txns, avgRating is the mean of real seeded ratings, and
//   trustedBadge follows the same thresholds as functions/index.js
//   (>=5 completed, >=0.9 completion rate, >=4.5 avg).
// - Timestamps spread over the past ~8 weeks so weekly charts, growth and
//   monthly bars all have real data.
// - Listing/avatar photos are real uploads into YOUR Cloudinary (unsigned
//   preset `swidshop_uploads`, folders `listings/seed-*` + `avatars/seed-*`):
//   the script downloads a deterministic placeholder and re-uploads it,
//   storing the returned `secure_url` — the exact same shape as in-app
//   uploads. Nothing is hotlinked.
//
// REST note: PATCH without an updateMask REPLACES the whole document, so
// full-doc writes pass no mask while small patches pass field masks.
//
// DELETE THIS FILE before any real release.

const API_KEY = 'AIzaSyCbR6mPi5JcuvmBr_4ZDRwyq_CyDrbo01Q';
const PROJECT = 'swidshop-d8ccf';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const DRY = process.argv.includes('--dry-run');

// --- Cloudinary unsigned upload (demo imagery into YOUR cloud) --------------
const CLOUD = 'u0sntfxy';
const PRESET = 'swidshop_uploads';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function dl(url, tries = 6) {
  for (let a = 0; a < tries; a++) {
    const r = await fetch(url, {
      headers: { 'User-Agent': 'SwidShopSeed/1.0 (class demo)' },
    });
    if (r.ok) return r;
    if ((r.status === 429 || r.status >= 500) && a < tries - 1) {
      await sleep(4000 * (a + 1));
      continue;
    }
    throw new Error(`download ${url}: ${r.status}`);
  }
  throw new Error(`download ${url}: giving up`);
}
async function uploadImage(sourceUrl, folder, publicId) {
  if (DRY) return `dry-run://${folder}/${publicId}`;
  const img = await dl(sourceUrl);
  const buf = Buffer.from(await img.arrayBuffer());
  await sleep(3000); // stay under Commons + Cloudinary rate limits
  const form = new FormData();
  form.append('file', new Blob([buf], { type: 'image/jpeg' }), `${publicId}.jpg`);
  form.append('upload_preset', PRESET);
  form.append('folder', folder);
  form.append('public_id', publicId);
  // NOTE: no `eager` param — unsigned uploads reject it; the preset's own
  // eager transformation still applies server-side.
  const res = await fetch(`https://api.cloudinary.com/v1_1/${CLOUD}/image/upload`, {
    method: 'POST',
    body: form,
  });
  if (!res.ok) throw new Error(`cloudinary ${publicId}: ${res.status} ${await res.text()}`);
  const data = await res.json();
  if (!data.secure_url) throw new Error(`cloudinary ${publicId}: no secure_url`);
  return data.secure_url;
}

// --- tiny seeded RNG (deterministic dataset) -------------------------------
let _s = 20261004;
const rnd = () => {
  _s = (_s * 1103515245 + 12345) % 2147483648;
  return _s / 2147483648;
};
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const int = (min, max) => min + Math.floor(rnd() * (max - min + 1));
const daysAgo = (min, max) =>
  new Date(Date.now() - int(min, max) * 86400000 - int(0, 86000) * 1000).toISOString();

// --- Firestore REST value helpers ------------------------------------------
const S = (v) => ({ stringValue: v });
const N = (v) => (Number.isInteger(v) ? { integerValue: `${v}` } : { doubleValue: v });
const B = (v) => ({ booleanValue: v });
const TS = (v) => ({ timestampValue: v });
const A = (items) => ({ arrayValue: { values: items } });
const M = (obj) => ({ mapValue: { fields: obj } });

async function put(collection, id, fields, mask) {
  if (DRY) {
    console.log(`  [dry] ${collection}/${id}`);
    return;
  }
  let url = `${BASE}/${collection}/${id}?key=${API_KEY}`;
  if (mask) {
    for (const f of mask) url += `&updateMask.fieldPaths=${encodeURIComponent(f)}`;
  }
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    throw new Error(`${collection}/${id}: ${res.status} ${await res.text()}`);
  }
}

async function listAll(collection) {
  const res = await fetch(`${BASE}/${collection}?key=${API_KEY}&pageSize=300`);
  if (!res.ok) throw new Error(`list ${collection}: ${res.status}`);
  const data = await res.json();
  return (data.documents || []).map((d) => ({
    id: d.name.split('/').pop(),
    fields: d.fields || {},
  }));
}

// --- vocab ------------------------------------------------------------------
const FIRST = ['Marco', 'Liza', 'Jose', 'Ana', 'Ramon', 'Irene', 'Paolo', 'Katrina', 'Miguel', 'Sofia', 'Rafael', 'Bianca', 'Enrico', 'Diana', 'Carlo', 'Nadia', 'Rhea', 'Victor', 'Lena', 'Dante', 'Mira', 'Jonas', 'Pia', 'Luz'];
const LAST = ['Santos', 'Reyes', 'Cruz', 'Bautista', 'Ocampo', 'Garcia', 'Mendoza', 'Torres', 'Tomas', 'Castillo', 'Flores', 'Villanueva', 'Ramos', 'Aquino', 'Navarro', 'Salazar'];
const CITIES = ['Quezon City', 'Manila', 'Makati', 'Cebu City', 'Davao City', 'Baguio', 'Iloilo City', 'Pasig'];
const ITEMS = [
  ['Vintage Levi\u2019s 501 Jeans', 'Bottoms', 'Like new', 'W32 L30', 'Denim', 'Levi\u2019s', 'jeans'],
  ['Oversized Graphic Tee', 'Tops', 'Gently used', 'L', 'Cotton', 'Uniqlo', 'tshirt'],
  ['Pleated Tennis Skirt', 'Bottoms', 'Brand new', 'M', 'Polyester', 'Zara', 'skirt'],
  ['Corduroy Jacket', 'Outerwear', 'Gently used', 'M', 'Corduroy', 'H&M', 'jacket'],
  ['Floral Slip Dress', 'Dresses', 'Like new', 'S', 'Satin', 'Forever 21', 'dress'],
  ['Chunky Sneakers', 'Shoes', 'Used', '9', 'Canvas', 'Converse', 'sneakers'],
  ['Leather Tote Bag', 'Bags', 'Gently used', 'OS', 'Leather', 'Charles & Keith', 'handbag'],
  ['Knit Cardigan', 'Tops', 'Like new', 'M', 'Knit', 'Mango', 'cardigan'],
  ['Denim Trucker Jacket', 'Outerwear', 'Used', 'L', 'Denim', 'Lee', 'denim-jacket'],
  ['Chelsea Boots', 'Shoes', 'Gently used', '8', 'Leather', 'Dr. Martens', 'boots'],
  ['Bucket Hat', 'Accessories', 'Brand new', 'OS', 'Cotton', 'Local brand', 'hat'],
  ['Silk Scarf', 'Accessories', 'Like new', 'OS', 'Silk', 'Local brand', 'scarf'],
];
// Keyword-matched photos via Wikimedia Commons (no key, hotlink-friendly).
// `commonsPhoto` searches once per keyword and pins one deterministic result
// per listing slot, so re-seeds stay stable.
const _commonsCache = {};
async function commonsPhoto(keyword, lock) {
  if (!_commonsCache[keyword]) {
    const q = new URLSearchParams({
      action: 'query',
      format: 'json',
      generator: 'search',
      gsrsearch: `filetype:bitmap ${keyword} clothing`,
      gsrnamespace: '6',
      gsrlimit: '20',
      prop: 'imageinfo',
      iiprop: 'url|size',
      iiurlwidth: '800',
    });
    const res = await fetch(
      `https://commons.wikimedia.org/w/api.php?${q.toString()}`,
      { headers: { 'User-Agent': 'SwidShopSeed/1.0 (class demo)' } },
    );
    if (!res.ok) throw new Error(`commons search ${keyword}: ${res.status}`);
    const data = await res.json();
    const pages = Object.values(data?.query?.pages || {});
    const urls = pages
      .map((p) => p?.imageinfo?.[0]?.thumburl || p?.imageinfo?.[0]?.url)
      .filter((u) => typeof u === 'string' && u.startsWith('http'));
    if (urls.length === 0) throw new Error(`commons: no image for ${keyword}`);
    _commonsCache[keyword] = urls;
  }
  const urls = _commonsCache[keyword];
  return urls[lock % urls.length];
}
const WANTS = ['Size M denim jacket', 'Platform boots size 8', 'Linen co-ords', 'Vintage band tee', 'Mini bag, any color', 'Pleated skirt size S'];
const REASONS = ['Counterfeit item', 'Looks like a scam listing', 'Prohibited item', 'Seller unresponsive'];
const COMMENTS = ['Smooth deal, item as described!', 'Fast handover, friendly seller.', 'Great swap, exactly what I wanted.', 'Legit seller, will buy again.', 'Okay deal, slight delay but fine.'];

// --- build -------------------------------------------------------------------
async function main() {
  console.log(DRY ? 'DRY RUN — nothing will be written.' : 'Seeding demo dataset…');

  // 0. Categories: reuse live ones, else create a default rack.
  let catNames = (await listAll('categories'))
    .map((c) => c.fields.name?.stringValue)
    .filter(Boolean);
  if (catNames.length === 0) {
    const defaults = ['Tops', 'Bottoms', 'Dresses', 'Outerwear', 'Shoes', 'Bags', 'Accessories'];
    let order = 1;
    for (const name of defaults) {
      await put('categories', `seed-cat-${order}`, {
        categoryId: S(`seed-cat-${order}`),
        name: S(name),
        iconName: S('checkroom'),
        sortOrder: N(order),
      });
      order++;
    }
    catNames = defaults;
  }
  console.log(`categories: ${catNames.length}`);

  // 1. Users (24). Aggregates filled in step 6 from real seeded data.
  const roles = [...Array(10).fill('customer'), ...Array(8).fill('seller'), ...Array(6).fill('both')];
  const users = [];
  const userDoc = (u) => ({
    uid: S(u.uid),
    name: S(u.name),
    email: S(u.email),
    firstName: S(u.name.split(' ')[0]),
    middleName: S(''),
    lastName: S(u.name.split(' ').slice(1).join(' ')),
    photoUrl: S(u.photo),
    role: S(u.role),
    address: M({ city: S(u.city), province: S('Metro Manila'), zipCode: S('1100'), country: S('Philippines') }),
    dob: TS(u.dob),
    avgRating: N(u.avg),
    completedTransactions: N(u.done),
    completionRate: N(u.rate),
    trustedBadge: B(u.trusted),
    profileComplete: B(true),
    accountStatus: S(u.status),
    favorites: A([]),
    following: A([]),
    createdAt: TS(u.created),
  });
  for (let i = 0; i < 24; i++) {
    const name = `${FIRST[i]} ${LAST[(i * 7) % LAST.length]}`;
    const uid = `seed-user-${String(i + 1).padStart(2, '0')}`;
    const photo = await uploadImage(
      `https://i.pravatar.cc/300?img=${(i % 70) + 1}`,
      `avatars/${uid}`,
      uid,
    );
    const u = {
      uid,
      name,
      email: `${name.toLowerCase().replace(/[^a-z]+/g, '.')}@example.com`,
      photo,
      role: roles[i],
      city: CITIES[i % CITIES.length],
      dob: new Date(new Date().getFullYear() - 22 - (i % 15), 5, 12).toISOString(),
      created: daysAgo(20, 150),
      avg: 0, done: 0, rate: 0, trusted: false,
      status: i === 22 ? 'suspended' : i === 23 ? 'banned' : 'active',
    };
    users.push(u);
    await put('users', u.uid, userDoc(u));
    if ((i + 1) % 6 === 0) console.log(`  avatars uploaded: ${i + 1}/24`);
  }
  console.log(`users: ${users.length} (10 customer / 8 seller / 6 both; 1 suspended, 1 banned)`);
  const sellers = users.filter((u) => u.role === 'seller' || u.role === 'both');
  const buyers = users.filter((u) => u.role === 'customer' || u.role === 'both');

  // 2. Listings (42): 18 buyNow / 12 bid / 12 swap. ~half active.
  // Photos: ONE real upload per item type (12 total), shared by listings of
  // that type — 12 downloads instead of 42, well under rate limits.
  const itemPhoto = {};
  const seenKw = [...new Set(ITEMS.map((it) => it[6]))];
  for (const kw of seenKw) {
    const url = await uploadImage(
      await commonsPhoto(kw, 0),
      'listings',
      `seed-item-${kw}`,
    );
    itemPhoto[kw] = url;
    console.log(`  item photo: ${kw}`);
    await sleep(10000);
  }
  const listings = [];
  const typePlan = [...Array(18).fill('buyNow'), ...Array(12).fill('bid'), ...Array(12).fill('swap')];
  for (let i = 0; i < 42; i++) {
    const id = `seed-listing-${String(i + 1).padStart(2, '0')}`;
    const seller = sellers[i % sellers.length];
    const item = ITEMS[i % ITEMS.length];
    const type = typePlan[i];
    const isBid = type === 'bid';
    const created = daysAgo(2, 56);
    const price = int(150, 5000);
    const startBid = int(200, 3000);
    const status = i % 7 < 3 ? 'active' : i % 7 < 6 ? 'sold' : 'expired';
    const endAt = status === 'active' && isBid
      ? new Date(Date.now() + int(1, 72) * 3600000).toISOString()
      : new Date(Date.now() - int(1, 30) * 86400000).toISOString();
    const l = { id, seller, type, status, price, startBid, item, created, topBid: 0, topBidder: '', bidCount: 0, imgs: [] };
    listings.push(l);
    l.imgs = [itemPhoto[item[6]]];
    await put('listings', id, {
      listingId: S(id),
      sellerId: S(seller.uid),
      title: S(`${item[0]} #${i + 1}`),
      description: S(`Demo listing ${i + 1}: ${item[0]} in ${item[2]} condition. Meet-ups around ${seller.city}.`),
      category: S(item[1]),
      condition: S(item[2]),
      size: S(item[3]),
      fabric: S(item[4]),
      brand: S(item[5]),
      deliveryOptions: A([S('meetup'), S('lalamove')]),
      meetupSpot: S(`SM ${seller.city}`),
      images: A(l.imgs.map((u) => S(u))),
      type: S(type),
      price: N(type === 'swap' ? 0 : price),
      startingBid: N(isBid ? startBid : 0),
      minIncrement: N(isBid ? pick([20, 50, 100]) : 0),
      auctionEndAt: TS(isBid ? endAt : created),
      swapOpen: B(type === 'swap'),
      swapWants: S(type === 'swap' ? pick(WANTS) : ''),
      swapOnly: B(type !== 'swap' ? false : i % 6 !== 0),
      status: S(status),
      createdAt: TS(created),
    });
  }
  console.log(`listings: ${listings.length} (18 buyNow / 12 bid / 12 swap)`);

  // 3. Bids on bid listings (2–8 each, rising), then stamp highest/block count.
  let bidN = 0;
  for (const l of listings.filter((x) => x.type === 'bid')) {
    const n = int(2, 8);
    let amount = l.startBid;
    for (let b = 0; b < n; b++) {
      amount += pick([20, 50, 50, 100, 200]);
      const bidder = pick(buyers.filter((x) => x.uid !== l.seller.uid));
      l.topBidder = bidder.uid;
      bidN++;
      const bidId = `seed-bid-${String(bidN).padStart(3, '0')}`;
      await put('bids', bidId, {
        bidId: S(bidId),
        listingId: S(l.id),
        bidderId: S(bidder.uid),
        amount: N(amount),
        placedAt: TS(daysAgo(0, 20)),
      });
    }
    l.topBid = amount;
    l.bidCount = n;
    await put('listings', l.id, {
      currentHighestBid: N(amount),
      highestBidderId: S(l.topBidder),
      bidCount: N(n),
    }, ['currentHighestBid', 'highestBidderId', 'bidCount']);
  }
  console.log(`bids: ${bidN}`);

  // 4. Transactions (~30, spread 8 weeks): completed buyNow + won bids +
  //    accepted swaps, plus 2 pending / 1 ongoing / 2 disputed / 1 cancelled.
  const txns = [];
  let txnN = 0;
  const addTxn = async (t) => {
    txnN++;
    const id = `seed-txn-${String(txnN).padStart(2, '0')}`;
    txns.push({ id, ...t });
    await put('transactions', id, {
      transactionId: S(id),
      listingId: S(t.listingId),
      buyerId: S(t.buyerId),
      sellerId: S(t.sellerId),
      type: S(t.type),
      amount: N(t.amount),
      listingTitle: S(t.title),
      listingImage: S(t.image),
      offerId: S(t.offerId || ''),
      swapItemTitle: S(t.swapTitle || ''),
      status: S(t.status),
      createdAt: TS(t.created),
    });
    await put('chats', id, {
      transactionId: S(id),
      buyerId: S(t.buyerId),
      sellerId: S(t.sellerId),
      listingId: S(t.listingId),
      createdAt: TS(t.created),
    });
    return id;
  };
  const img = (l) => (l.imgs && l.imgs.length > 0 ? l.imgs[0] : '');
  const titleOf = (l) => `${l.item[0]} #${listings.indexOf(l) + 1}`;
  // buyNow completed from sold buyNow listings
  for (const l of listings.filter((x) => x.type === 'buyNow' && x.status === 'sold').slice(0, 10)) {
    const buyer = pick(buyers.filter((x) => x.uid !== l.seller.uid));
    await addTxn({ listingId: l.id, buyerId: buyer.uid, sellerId: l.seller.uid, type: 'buyNow', amount: l.price, title: titleOf(l), image: img(l), status: 'completed', created: daysAgo(1, 56) });
  }
  // won bids from sold/expired bid listings with bids
  for (const l of listings.filter((x) => x.type === 'bid' && x.topBid > 0).slice(0, 7)) {
    await addTxn({ listingId: l.id, buyerId: l.topBidder, sellerId: l.seller.uid, type: 'bid', amount: l.topBid, title: titleOf(l), image: img(l), status: 'completed', created: daysAgo(1, 50) });
  }
  // open states on active listings
  const actives = listings.filter((x) => x.status === 'active');
  const openStates = ['pending', 'pending', 'ongoing', 'disputed', 'disputed', 'cancelled'];
  for (let k = 0; k < Math.min(openStates.length, actives.length); k++) {
    const l = actives[k];
    const buyer = pick(buyers.filter((x) => x.uid !== l.seller.uid));
    await addTxn({ listingId: l.id, buyerId: buyer.uid, sellerId: l.seller.uid, type: l.type === 'swap' ? 'swap' : l.type, amount: l.type === 'bid' ? (l.topBid || l.startBid) : l.price, title: titleOf(l), image: img(l), status: openStates[k], created: daysAgo(0, 10) });
  }
  console.log(`transactions: ${txns.length} (+ chat threads)`);

  // 5. Swap offers (accepted for completed swaps + pending/declined) + ratings + reports.
  let offerN = 0;
  const swapTxns = txns.filter((t) => t.type === 'swap' && t.status === 'completed');
  const swapTargets = listings.filter((x) => x.type === 'swap');
  // accepted offers backing completed swap deals
  for (const t of swapTxns.slice(0, 5)) {
    offerN++;
    const oid = `seed-offer-${String(offerN).padStart(2, '0')}`;
    const mine = listings.find((x) => x.seller.uid === t.buyerId && x.status === 'active' && x.id !== t.listingId)
      || listings.find((x) => x.status === 'active' && x.id !== t.listingId);
    await put('swapOffers', oid, {
      offerId: S(oid),
      listingId: S(t.listingId),
      offeredById: S(t.buyerId),
      offeredItemId: S(mine ? mine.id : ''),
      sellerId: S(t.sellerId),
      message: S('Demo swap — hope this works for you!'),
      status: S('accepted'),
      createdAt: TS(daysAgo(2, 40)),
    });
    t.offerId = oid;
    t.swapTitle = mine ? titleOf(mine) : '';
    await put('transactions', t.id, { offerId: S(oid), swapItemTitle: S(t.swapTitle) }, ['offerId', 'swapItemTitle']);
  }
  // pending + declined offers on active swap listings
  for (const l of swapTargets.filter((x) => x.status === 'active').slice(0, 6)) {
    offerN++;
    const oid = `seed-offer-${String(offerN).padStart(2, '0')}`;
    const from = pick(buyers.filter((x) => x.uid !== l.seller.uid));
    const mine = listings.find((x) => x.seller.uid === from.uid && x.status === 'active');
    await put('swapOffers', oid, {
      offerId: S(oid),
      listingId: S(l.id),
      offeredById: S(from.uid),
      offeredItemId: S(mine ? mine.id : ''),
      sellerId: S(l.seller.uid),
      message: S(pick(['Still available for swap?', 'Love this piece — proposing mine.', 'Meet-up in QC works for me.'])),
      status: S(offerN % 3 === 0 ? 'declined' : 'pending'),
      createdAt: TS(daysAgo(0, 12)),
    });
  }
  console.log(`swapOffers: ${offerN}`);

  // ratings: buyer rates seller on every completed deal (+ some sellers rate back)
  let rateN = 0;
  const starsByUser = {};
  for (const t of txns.filter((x) => x.status === 'completed')) {
    rateN++;
    const rid = `seed-rating-${String(rateN).padStart(2, '0')}`;
    const stars = pick([4, 4, 4, 5, 5, 5, 5, 3]);
    (starsByUser[t.sellerId] = starsByUser[t.sellerId] || []).push(stars);
    await put('ratings', rid, {
      ratingId: S(rid),
      raterId: S(t.buyerId),
      ratedUserId: S(t.sellerId),
      transactionId: S(t.id),
      stars: N(stars),
      comment: S(pick(COMMENTS)),
      createdAt: TS(daysAgo(0, 40)),
    });
  }
  console.log(`ratings: ${rateN}`);

  // reports: pending user/listing/rating + a resolved one
  const pendingTargets = [
    ['user', users[3].uid, REASONS[1]],
    ['user', users[9].uid, REASONS[3]],
    ['listing', listings[5].id, REASONS[0]],
    ['listing', listings[20].id, REASONS[2]],
    ['rating', 'seed-rating-01', 'Fake review from a friend'],
  ];
  let repN = 0;
  for (const [kind, target, reason] of pendingTargets) {
    repN++;
    const rid = `seed-report-${String(repN).padStart(2, '0')}`;
    await put('reports', rid, {
      reportId: S(rid),
      reportedBy: S(pick(buyers).uid),
      targetType: S(kind),
      targetId: S(target),
      reason: S(reason),
      status: S('pending'),
      createdAt: TS(daysAgo(0, 6)),
    });
  }
  repN++;
  await put('reports', `seed-report-${String(repN).padStart(2, '0')}`, {
    reportId: S(`seed-report-${String(repN).padStart(2, '0')}`),
    reportedBy: S(buyers[0].uid),
    targetType: S('listing'),
    targetId: S(listings[0].id),
    reason: S('Misclicked, item is fine'),
    status: S('dismissed'),
    createdAt: TS(daysAgo(10, 20)),
  });
  console.log(`reports: ${repN} (5 pending)`);

  // 5b. Concentration pass: focus sellers get 6+ completed deals each so
  // Trusted badges honestly emerge; plus 3 finished swaps. Fixed `b`
  // id-range keeps re-runs stable.
  let txnB = 0;
  let rateB = 0;
  let offerB = 0;
  const addRatingFor = async (t, stars) => {
    rateB++;
    const rid = `seed-rating-b${String(rateB).padStart(2, '0')}`;
    (starsByUser[t.sellerId] = starsByUser[t.sellerId] || []).push(stars);
    await put('ratings', rid, {
      ratingId: S(rid),
      raterId: S(t.buyerId),
      ratedUserId: S(t.sellerId),
      transactionId: S(t.id),
      stars: N(stars),
      comment: S(pick(COMMENTS)),
      createdAt: TS(daysAgo(0, 40)),
    });
  };
  const focusSellers = sellers.slice(0, 5);
  for (const s of focusSellers) {
    const have = txns.filter(
      (t) => t.sellerId === s.uid && t.status === 'completed',
    ).length;
    const mineSold = listings.filter(
      (x) => x.seller.uid === s.uid && x.status === 'sold',
    );
    const pool = mineSold.length > 0
        ? mineSold
        : listings.filter((x) => x.seller.uid === s.uid);
    for (let k = have; k < 6; k++) {
      const l = pool[k % pool.length];
      if (l.status !== 'sold') {
        l.status = 'sold';
        await put('listings', l.id, { status: S('sold') }, ['status']);
      }
      txnB++;
      const id = `seed-txn-b${String(txnB).padStart(2, '0')}`;
      const buyer = pick(buyers.filter((x) => x.uid !== s.uid));
      const t = {
        id,
        listingId: l.id,
        buyerId: buyer.uid,
        sellerId: s.uid,
        type: l.type === 'swap' ? 'swap' : l.type,
        amount: l.type === 'bid' ? (l.topBid || l.startBid) : l.price,
        title: titleOf(l),
        image: img(l),
        status: 'completed',
        created: daysAgo(3, 56),
      };
      txns.push(t);
      await put('transactions', id, {
        transactionId: S(id),
        listingId: S(l.id),
        buyerId: S(buyer.uid),
        sellerId: S(s.uid),
        type: S(t.type),
        amount: N(t.amount),
        listingTitle: S(t.title),
        listingImage: S(t.image),
        offerId: S(''),
        swapItemTitle: S(''),
        status: S('completed'),
        createdAt: TS(t.created),
      });
      await put('chats', id, {
        transactionId: S(id),
        buyerId: S(buyer.uid),
        sellerId: S(s.uid),
        listingId: S(l.id),
        createdAt: TS(t.created),
      });
      await addRatingFor(t, pick([4, 5, 5, 5, 5]));
    }
  }
  console.log(`boost txns: ${txnB} (focus sellers to 6+ completed)`);
  // finished swaps: first 3 active swap listings → sold + accepted + done
  const swapTodo = listings
    .filter((x) => x.type === 'swap' && x.status === 'active')
    .slice(0, 3);
  for (const l of swapTodo) {
    l.status = 'sold';
    await put('listings', l.id, { status: S('sold') }, ['status']);
    offerB++;
    const oid = `seed-offer-b${String(offerB).padStart(2, '0')}`;
    const buyer = pick(buyers.filter((x) => x.uid !== l.seller.uid));
    const mine = listings.find(
      (x) => x.seller.uid === buyer.uid && x.status === 'active' && x.id !== l.id,
    );
    await put('swapOffers', oid, {
      offerId: S(oid),
      listingId: S(l.id),
      offeredById: S(buyer.uid),
      offeredItemId: S(mine ? mine.id : ''),
      sellerId: S(l.seller.uid),
      message: S('Demo swap — hope this works for you!'),
      status: S('accepted'),
      createdAt: TS(daysAgo(3, 30)),
    });
    txnB++;
    const id = `seed-txn-b${String(txnB).padStart(2, '0')}`;
    const t = {
      id,
      listingId: l.id,
      buyerId: buyer.uid,
      sellerId: l.seller.uid,
      type: 'swap',
      amount: 0,
      title: titleOf(l),
      image: img(l),
      status: 'completed',
      created: daysAgo(2, 30),
      offerId: oid,
      swapTitle: mine ? titleOf(mine) : '',
    };
    txns.push(t);
    await put('transactions', id, {
      transactionId: S(id),
      listingId: S(l.id),
      buyerId: S(buyer.uid),
      sellerId: S(l.seller.uid),
      type: S('swap'),
      amount: N(0),
      listingTitle: S(t.title),
      listingImage: S(t.image),
      offerId: S(oid),
      swapItemTitle: S(t.swapTitle),
      status: S('completed'),
      createdAt: TS(t.created),
    });
    await put('chats', id, {
      transactionId: S(id),
      buyerId: S(buyer.uid),
      sellerId: S(l.seller.uid),
      listingId: S(l.id),
      createdAt: TS(t.created),
    });
    await addRatingFor(t, pick([4, 5, 5]));
  }
  console.log(`finished swaps: ${swapTodo.length}`);
  console.log(`boost ratings: ${rateB}`);

  // 6. Derive user aggregates from the real seeded docs and rewrite users.
  for (const u of users) {
    const mine = txns.filter((t) => t.sellerId === u.uid);
    const done = mine.filter((t) => t.status === 'completed').length;
    const resolved = mine.filter((t) => ['completed', 'cancelled', 'disputed'].includes(t.status)).length;
    const stars = starsByUser[u.uid] || [];
    const avg = stars.length === 0 ? 0 : Math.round((stars.reduce((a, b) => a + b, 0) / stars.length) * 10) / 10;
    const rate = resolved === 0 ? 0 : Math.round((done / resolved) * 100) / 100;
    u.avg = avg;
    u.done = done;
    u.rate = rate;
    u.trusted = done >= 5 && rate >= 0.9 && avg >= 4.5;
    await put('users', u.uid, userDoc(u));
  }
  const trusted = users.filter((u) => u.trusted).length;
  console.log(`aggregates derived — trusted sellers: ${trusted}`);

  console.log('\nDone. Counts above. Re-run any time (ids are stable).');
}

main().catch((e) => {
  console.error('SEED FAILED:', e.message);
  process.exit(1);
});
