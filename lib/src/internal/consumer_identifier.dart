import 'sha256.dart';

/// Identifies API consumers from HTTP request headers.
///
/// Uses x-api-key as-is, or SHA-256 hashes the Authorization header
/// to avoid storing raw credentials.
class ConsumerIdentifier {
  /// Returns the consumer ID from the given headers.
  ///
  /// Priority: x-api-key (as-is) > Authorization (SHA-256 hashed) > null.
  static String? identify(String? apiKeyHeader, String? authHeader) {
    if (apiKeyHeader != null && apiKeyHeader.isNotEmpty) {
      return apiKeyHeader;
    }
    if (authHeader != null && authHeader.isNotEmpty) {
      return hashConsumerId(authHeader);
    }
    return null;
  }

  /// SHA-256 hashes [raw] and returns `hash_` + first 12 hex chars.
  static String hashConsumerId(String raw) {
    final hex = Sha256.hashHex(raw);
    return 'hash_${hex.substring(0, 12)}';
  }
}
