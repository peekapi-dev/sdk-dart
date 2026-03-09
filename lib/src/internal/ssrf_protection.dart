import 'dart:io';

/// Prevents Server-Side Request Forgery by blocking private IP endpoints.
class SsrfProtection {
  /// Returns true if [host] is a localhost address.
  static bool isLocalhost(String? host) {
    if (host == null) return false;
    final lower = host.toLowerCase();
    return lower == 'localhost' || lower == '127.0.0.1' || lower == '::1';
  }

  /// Validates that [host] does not resolve to a private IP.
  ///
  /// Throws [ArgumentError] if a private IP is detected.
  /// Localhost is always allowed.
  static Future<void> validateHost(String host) async {
    if (host.isEmpty) {
      throw ArgumentError('Host cannot be empty');
    }
    if (isLocalhost(host)) return;

    try {
      final addresses = await InternetAddress.lookup(host);
      for (final addr in addresses) {
        if (isPrivateAddress(addr)) {
          throw ArgumentError('Endpoint resolves to private IP: $host');
        }
      }
    } on SocketException {
      // DNS resolution failed — let the HTTP client handle it later
    }
  }

  /// Returns true if [addr] is a private/reserved IP address.
  static bool isPrivateAddress(InternetAddress addr) {
    final bytes = addr.rawAddress;
    if (bytes.length == 4) {
      return _isPrivateIPv4(bytes);
    } else if (bytes.length == 16) {
      return _isPrivateIPv6(bytes);
    }
    return false;
  }

  static bool _isPrivateIPv4(List<int> b) {
    // 0.0.0.0/8 — current network
    if (b[0] == 0) return true;
    // 10.0.0.0/8 — private (RFC 1918)
    if (b[0] == 10) return true;
    // 100.64.0.0/10 — CGNAT (RFC 6598)
    if (b[0] == 100 && (b[1] & 0xC0) == 64) return true;
    // 127.0.0.0/8 — loopback
    if (b[0] == 127) return true;
    // 169.254.0.0/16 — link-local
    if (b[0] == 169 && b[1] == 254) return true;
    // 172.16.0.0/12 — private (RFC 1918)
    if (b[0] == 172 && (b[1] & 0xF0) == 16) return true;
    // 192.168.0.0/16 — private (RFC 1918)
    if (b[0] == 192 && b[1] == 168) return true;
    return false;
  }

  static bool _isPrivateIPv6(List<int> b) {
    // ::1 — loopback
    if (_isLoopbackIPv6(b)) return true;
    // fc00::/7 — unique local address
    if ((b[0] & 0xFE) == 0xFC) return true;
    // fe80::/10 — link-local
    if (b[0] == 0xFE && (b[1] & 0xC0) == 0x80) return true;
    // ::ffff:x.x.x.x — IPv4-mapped IPv6
    if (_isIPv4MappedIPv6(b)) {
      return _isPrivateIPv4(b.sublist(12));
    }
    return false;
  }

  static bool _isLoopbackIPv6(List<int> b) {
    for (var i = 0; i < 15; i++) {
      if (b[i] != 0) return false;
    }
    return b[15] == 1;
  }

  static bool _isIPv4MappedIPv6(List<int> b) {
    for (var i = 0; i < 10; i++) {
      if (b[i] != 0) return false;
    }
    return b[10] == 0xFF && b[11] == 0xFF;
  }
}
