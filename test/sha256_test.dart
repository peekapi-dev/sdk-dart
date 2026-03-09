import 'package:test/test.dart';
import 'package:peekapi/src/internal/sha256.dart';

void main() {
  group('Sha256', () {
    test('empty string', () {
      expect(
        Sha256.hashHex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('hello world', () {
      expect(
        Sha256.hashHex('hello world'),
        'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
      );
    });

    test('abc', () {
      expect(
        Sha256.hashHex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('deterministic — same input produces same output', () {
      final h1 = Sha256.hashHex('Bearer token123');
      final h2 = Sha256.hashHex('Bearer token123');
      expect(h1, h2);
    });

    test('different inputs produce different hashes', () {
      final h1 = Sha256.hashHex('input1');
      final h2 = Sha256.hashHex('input2');
      expect(h1, isNot(h2));
    });

    test('hash returns 32 bytes', () {
      final digest = Sha256.hash('test'.codeUnits);
      expect(digest.length, 32);
    });

    test('hashHex returns 64 hex characters', () {
      final hex = Sha256.hashHex('test');
      expect(hex.length, 64);
      expect(hex, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('long input', () {
      final input = 'a' * 1000;
      final hex = Sha256.hashHex(input);
      expect(hex.length, 64);
    });
  });
}
