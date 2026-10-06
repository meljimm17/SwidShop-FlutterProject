// Guards against drift between AppConstants and the monetization numbers
// duplicated in firestore.rules (rules cannot import Dart). Pure file read —
// no Firebase.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:swidshop/core/constants.dart';

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  /// Body of `function name(...) { ... }` in the rules file.
  String fn(String name) {
    final start = rules.indexOf('function $name(');
    expect(start, isNot(-1), reason: 'rules function $name missing');
    final end = rules.indexOf('\n    }', start);
    return rules.substring(start, end);
  }

  String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  test('plan prices and length', () {
    final body = fn('planPrice');
    expect(body, contains("'plus' ? ${n(AppConstants.planPrices['plus']!)}"));
    expect(body, contains("'pro' ? ${n(AppConstants.planPrices['pro']!)}"));
    expect(fn('planDays'), contains('return ${AppConstants.planDays};'));
  });

  test('boost prices', () {
    final body = fn('boostPrice');
    AppConstants.boostPrices.forEach((days, price) {
      expect(body, contains('days == $days ? ${n(price)}'));
    });
    expect(rules, contains("in [${AppConstants.boostDurations.join(', ')}]"));
  });

  test('featured, photo pack, highlight, fee due', () {
    expect(
      fn('featuredPrice'),
      contains('return ${n(AppConstants.featuredPrice)};'),
    );
    expect(
      fn('featuredDays'),
      contains('return ${AppConstants.featuredDays};'),
    );
    expect(
      fn('photoPackPrice'),
      contains('return ${n(AppConstants.photoPackPrice)};'),
    );
    expect(
      fn('photoPackLimit'),
      contains('return ${AppConstants.photoLimits['pack']};'),
    );
    expect(
      fn('highlightDays'),
      contains('return ${AppConstants.highlightDays};'),
    );
    expect(fn('feeDueDays'), contains('return ${AppConstants.feeDueDays};'));
  });

  test('commission rates', () {
    final body = fn('rateFor');
    expect(body, contains("'pro' ? ${AppConstants.feeRates['pro']}"));
    expect(body, contains("'plus' ? ${AppConstants.feeRates['plus']}"));
    expect(body, contains(': ${AppConstants.feeRates['free']})'));
  });

  test('photo limits and auction lengths', () {
    final photos = fn('photoLimitFor');
    expect(photos, contains("'pro' ? ${AppConstants.photoLimits['pro']}"));
    expect(photos, contains("'plus' ? ${AppConstants.photoLimits['plus']}"));
    expect(photos, contains(': ${AppConstants.photoLimits['free']})'));
    final auction = fn('maxAuctionDays');
    expect(auction, contains("'pro' ? ${AppConstants.maxProAuctionDays}"));
    expect(auction, contains(': ${AppConstants.maxAuctionDays};'));
  });

  test('bump cooldown', () {
    expect(
      rules,
      contains(
        "o.bumpedAt + duration.value(${AppConstants.bumpCooldown.inHours}, 'h')",
      ),
    );
  });

  test('swap photo offer limit', () {
    expect(
      rules,
      contains(
        "get('offeredImages', []).size() <= ${AppConstants.maxSwapOfferPhotos}",
      ),
    );
  });

  test('payments collection name', () {
    expect(rules, contains('match /${AppConstants.paymentsCollection}/{'));
  });

  test('Cloud Functions mirror the same fee numbers', () {
    final js = File('functions/index.js').readAsStringSync();
    expect(
      js,
      contains(
        'const FEE_RATES = { free: ${AppConstants.feeRates['free']}, '
        'plus: ${AppConstants.feeRates['plus']}, '
        'pro: ${AppConstants.feeRates['pro']} };',
      ),
    );
    expect(js, contains('const FEE_DUE_DAYS = ${AppConstants.feeDueDays};'));
    expect(
      js,
      contains(
        'const FEE_REMINDER_DAYS = [${AppConstants.feeReminderDays.join(', ')}];',
      ),
    );
  });
}
