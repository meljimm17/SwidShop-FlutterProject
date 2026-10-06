/// SwidShop Terms & Conditions shown in the last registration step.
///
/// Keep this aligned with how the app actually works (listing types,
/// auction closing, trust badge thresholds in `functions/index.js`, report
/// outcomes). Bump [AppConstants.termsVersion] on material changes.
library;

class TermsSection {
  const TermsSection(this.title, this.points);

  final String title;
  final List<String> points;
}

const String termsIntro =
    'These terms cover how you use SwidShop to buy, bid on, and swap '
    'pre-loved items with other members. By creating an account you agree '
    'to them. Please read them before continuing.';

const List<TermsSection> termsSections = [
  TermsSection('1. Your account', [
    'You must be at least 18 years old and a resident of the Philippines.',
    'One person, one account. Use your real name and keep your details '
        'accurate and up to date.',
    'You are responsible for everything done through your account. Keep '
        'your password private and tell us if you think it was compromised.',
  ]),
  TermsSection('2. Identity verification', [
    'We ask for a valid government ID to reduce fraud. It is reviewed only '
        'by SwidShop admins and is never shown on your profile, listings, or '
        'chats.',
    'We may limit selling, bidding, or swapping until your ID is reviewed, '
        'and may reject IDs that are unclear, expired, or not yours.',
  ]),
  TermsSection('3. Listings', [
    'Every listing is one of three types: Buy Now (fixed price), Bid '
        '(auction), or Swap (trade for another item).',
    'Only list items you own and can hand over. Photos and descriptions '
        'must show the actual item, including flaws, stains, repairs, and '
        'true size.',
    'Do not list counterfeit or replica items, stolen goods, weapons, '
        'drugs, adult content, live animals, recalled products, or anything '
        'illegal to sell in the Philippines.',
    'SwidShop may remove listings that break these rules without notice.',
  ]),
  TermsSection('4. Bidding', [
    'A bid is a commitment to buy at that price if you win. Each bid must '
        'be higher than the current highest bid (or the starting bid).',
    'Bids cannot be withdrawn once placed.',
    'Auctions close automatically at the end time shown. The highest '
        'bidder at closing wins, and a transaction is opened between the '
        'winner and the seller.',
  ]),
  TermsSection('5. Swaps', [
    'A swap offer proposes one of your items in exchange for a listed item. '
        'Nothing is final until the other member accepts.',
    'Describe the item you are offering honestly. Both sides are '
        'responsible for handing over their item as agreed.',
  ]),
  TermsSection('6. Payment, meet-ups and delivery', [
    'SwidShop connects buyers, sellers, and swappers. We do not process, '
        'hold, or refund payments, and we are not a party to your deal.',
    'Agree on payment (for example GCash, bank transfer, or cash) and on '
        'meet-up or courier details in the transaction chat, and keep those '
        'agreements there for reference.',
    'Meet in safe, public places. Never send money or items outside an '
        'agreed transaction, and never share your passwords or one-time codes.',
  ]),
  TermsSection('7. Ratings and the Trusted badge', [
    'After a transaction, both members can leave a rating. Ratings must be '
        'honest and about that transaction only.',
    'Trusted Seller eligibility requires at least 10 completed seller '
        'transactions, a completion rate of 90% or higher, an average rating '
        'of 4.5 or higher, and no unresolved reports against the account, its '
        'listings, or its ratings.',
    'Eligibility is checked automatically. An admin reviews the seller’s '
        'account details before awarding the badge. The badge is removed if '
        'the seller no longer meets the requirements.',
  ]),
  TermsSection('8. Conduct, reports and enforcement', [
    'Be respectful. No harassment, hate speech, spam, scams, or attempts to '
        'move deals off SwidShop to avoid these terms.',
    'You can report a member or listing. Admins review every report and may '
        'dismiss it, warn the member, remove the listing, or suspend the '
        'account.',
    'Disputed transactions are reviewed using the transaction chat and any '
        'evidence both sides provide.',
  ]),
  TermsSection('9. Your data', [
    'We collect what you give us at sign-up (name, email, birth date, phone, '
        'address, profile photo, and ID images) plus your listings, bids, '
        'offers, chats, and ratings.',
    'We use it to run your account, verify identity, prevent fraud, show '
        'your public profile (name, photo, city, ratings), and send '
        'notifications about your activity.',
    'Your phone number, street address, and ID are visible only to you and '
        'SwidShop admins. We process personal data in line with the Data '
        'Privacy Act of 2012 (RA 10173). You can ask to access, correct, or '
        'delete your data.',
  ]),
  TermsSection('10. Liability', [
    'Items are sold or swapped as described by the members, not by '
        'SwidShop. We do not guarantee the quality, safety, or authenticity '
        'of items.',
    'To the extent allowed by law, SwidShop is not liable for losses from '
        'deals between members.',
  ]),
  TermsSection('11. Changes and closing your account', [
    'We may update these terms. If the changes are significant, we will ask '
        'you to accept them again in the app.',
    'You can stop using SwidShop and ask us to close your account at any '
        'time. We may suspend or close accounts that break these terms.',
  ]),
];
