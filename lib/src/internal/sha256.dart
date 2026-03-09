import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart SHA-256 implementation (FIPS 180-4).
class Sha256 {
  static const _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;
  static int _ch(int x, int y, int z) => (x & y) ^ (~x & 0xFFFFFFFF & z);
  static int _maj(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);
  static int _sigma0(int x) => _rotr(x, 2) ^ _rotr(x, 13) ^ _rotr(x, 22);
  static int _sigma1(int x) => _rotr(x, 6) ^ _rotr(x, 11) ^ _rotr(x, 25);
  static int _gamma0(int x) => _rotr(x, 7) ^ _rotr(x, 18) ^ (x >>> 3);
  static int _gamma1(int x) => _rotr(x, 17) ^ _rotr(x, 19) ^ (x >>> 10);

  /// Computes the SHA-256 hash of [message] and returns the digest bytes.
  static Uint8List hash(List<int> message) {
    final len = message.length;
    final bitLen = len * 8;

    // Pad: append 0x80, zeros, then 64-bit big-endian length
    final padded = <int>[...message, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    // Append 64-bit length (big-endian)
    for (var i = 56; i >= 0; i -= 8) {
      padded.add((bitLen >>> i) & 0xFF);
    }

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = List<int>.filled(64, 0);

    for (var offset = 0; offset < padded.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = (padded[j] << 24) |
            (padded[j + 1] << 16) |
            (padded[j + 2] << 8) |
            padded[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        w[i] = (_gamma1(w[i - 2]) + w[i - 7] + _gamma0(w[i - 15]) + w[i - 16]) &
            0xFFFFFFFF;
      }

      var a = h0, b = h1, c = h2, d = h3;
      var e = h4, f = h5, g = h6, h = h7;

      for (var i = 0; i < 64; i++) {
        final t1 = (h + _sigma1(e) + _ch(e, f, g) + _k[i] + w[i]) & 0xFFFFFFFF;
        final t2 = (_sigma0(a) + _maj(a, b, c)) & 0xFFFFFFFF;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final digest = Uint8List(32);
    void put32(int offset, int value) {
      digest[offset] = (value >>> 24) & 0xFF;
      digest[offset + 1] = (value >>> 16) & 0xFF;
      digest[offset + 2] = (value >>> 8) & 0xFF;
      digest[offset + 3] = value & 0xFF;
    }

    put32(0, h0);
    put32(4, h1);
    put32(8, h2);
    put32(12, h3);
    put32(16, h4);
    put32(20, h5);
    put32(24, h6);
    put32(28, h7);

    return digest;
  }

  /// Returns the hex-encoded SHA-256 hash of [input].
  static String hashHex(String input) {
    final digest = hash(utf8.encode(input));
    final sb = StringBuffer();
    for (final b in digest) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
