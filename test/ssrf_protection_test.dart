import 'dart:io';
import 'package:test/test.dart';
import 'package:peekapi/src/internal/ssrf_protection.dart';

void main() {
  group('SsrfProtection', () {
    group('isLocalhost', () {
      test('localhost returns true', () {
        expect(SsrfProtection.isLocalhost('localhost'), isTrue);
      });

      test('127.0.0.1 returns true', () {
        expect(SsrfProtection.isLocalhost('127.0.0.1'), isTrue);
      });

      test('::1 returns true', () {
        expect(SsrfProtection.isLocalhost('::1'), isTrue);
      });

      test('case insensitive', () {
        expect(SsrfProtection.isLocalhost('LOCALHOST'), isTrue);
      });

      test('null returns false', () {
        expect(SsrfProtection.isLocalhost(null), isFalse);
      });

      test('non-localhost returns false', () {
        expect(SsrfProtection.isLocalhost('example.com'), isFalse);
      });
    });

    group('isPrivateAddress — IPv4', () {
      test('10.0.0.0/8 is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('10.0.0.1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('10.255.255.255')),
          isTrue,
        );
      });

      test('172.16.0.0/12 is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('172.16.0.1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('172.31.255.255')),
          isTrue,
        );
      });

      test('172.32.0.0 is public', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('172.32.0.1')),
          isFalse,
        );
      });

      test('192.168.0.0/16 is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('192.168.1.1')),
          isTrue,
        );
      });

      test('127.0.0.0/8 is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('127.0.0.1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('127.255.255.255')),
          isTrue,
        );
      });

      test('169.254.0.0/16 link-local is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('169.254.1.1')),
          isTrue,
        );
      });

      test('100.64.0.0/10 CGNAT is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('100.64.0.1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('100.127.255.255')),
          isTrue,
        );
      });

      test('100.128.0.0 is public', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('100.128.0.1')),
          isFalse,
        );
      });

      test('0.0.0.0/8 current network is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('0.0.0.0')),
          isTrue,
        );
      });

      test('public IPs are allowed', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('8.8.8.8')),
          isFalse,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('1.1.1.1')),
          isFalse,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('93.184.216.34')),
          isFalse,
        );
      });
    });

    group('isPrivateAddress — IPv6', () {
      test('::1 loopback is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('::1')),
          isTrue,
        );
      });

      test('fc00::/7 ULA is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('fc00::1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('fd00::1')),
          isTrue,
        );
      });

      test('fe80::/10 link-local is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('fe80::1')),
          isTrue,
        );
      });

      test('IPv4-mapped IPv6 with private IPv4 is private', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('::ffff:10.0.0.1')),
          isTrue,
        );
        expect(
          SsrfProtection.isPrivateAddress(
              InternetAddress('::ffff:192.168.1.1')),
          isTrue,
        );
      });

      test('IPv4-mapped IPv6 with public IPv4 is allowed', () {
        expect(
          SsrfProtection.isPrivateAddress(InternetAddress('::ffff:8.8.8.8')),
          isFalse,
        );
      });
    });

    group('validateHost', () {
      test('empty host throws', () {
        expect(
          () => SsrfProtection.validateHost(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('localhost is always allowed', () async {
        await SsrfProtection.validateHost('localhost');
        // Should not throw
      });

      test('127.0.0.1 is always allowed', () async {
        await SsrfProtection.validateHost('127.0.0.1');
      });
    });
  });
}
