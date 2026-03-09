import 'package:test/test.dart';
import 'package:peekapi/src/internal/consumer_identifier.dart';

void main() {
  group('ConsumerIdentifier', () {
    test('x-api-key used as-is', () {
      expect(
        ConsumerIdentifier.identify('ak_consumer_123', null),
        'ak_consumer_123',
      );
    });

    test('x-api-key takes priority over Authorization', () {
      expect(
        ConsumerIdentifier.identify('ak_consumer_123', 'Bearer secret'),
        'ak_consumer_123',
      );
    });

    test('Authorization header is SHA-256 hashed with hash_ prefix', () {
      final result = ConsumerIdentifier.identify(null, 'Bearer token123');
      expect(result, isNotNull);
      expect(result, startsWith('hash_'));
      expect(result!.length, 17); // "hash_" + 12 hex chars
    });

    test('hash format is hash_ + 12 hex characters', () {
      final result = ConsumerIdentifier.hashConsumerId('Bearer token123');
      expect(result, matches(RegExp(r'^hash_[0-9a-f]{12}$')));
    });

    test('hash is deterministic', () {
      final h1 = ConsumerIdentifier.identify(null, 'Bearer abc');
      final h2 = ConsumerIdentifier.identify(null, 'Bearer abc');
      expect(h1, h2);
    });

    test('different Authorization values produce different hashes', () {
      final h1 = ConsumerIdentifier.identify(null, 'Bearer token1');
      final h2 = ConsumerIdentifier.identify(null, 'Bearer token2');
      expect(h1, isNot(h2));
    });

    test('null headers return null', () {
      expect(ConsumerIdentifier.identify(null, null), isNull);
    });

    test('empty headers return null', () {
      expect(ConsumerIdentifier.identify('', ''), isNull);
    });

    test('empty x-api-key falls through to Authorization', () {
      final result = ConsumerIdentifier.identify('', 'Bearer token');
      expect(result, startsWith('hash_'));
    });
  });
}
