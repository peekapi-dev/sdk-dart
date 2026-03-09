/// Represents a single API request event captured by PeekAPI.
class RequestEvent {
  /// HTTP method (e.g. GET, POST).
  String method;

  /// Request path (e.g. /api/users).
  String path;

  /// HTTP status code (e.g. 200, 404).
  int statusCode;

  /// Response time in milliseconds.
  double responseTimeMs;

  /// Request body size in bytes.
  int requestSize;

  /// Response body size in bytes.
  int responseSize;

  /// Consumer identifier (API key, hashed auth header, or custom).
  String? consumerId;

  /// Arbitrary key-value metadata attached to the event.
  Map<String, dynamic>? metadata;

  /// ISO 8601 timestamp (auto-set if null).
  String? timestamp;

  /// Creates a new request event.
  RequestEvent({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.responseTimeMs,
    this.requestSize = 0,
    this.responseSize = 0,
    this.consumerId,
    this.metadata,
    this.timestamp,
  });

  /// Serializes this event to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'method': method,
      'path': path,
      'status_code': statusCode,
      'response_time_ms': responseTimeMs,
      'request_size': requestSize,
      'response_size': responseSize,
      'timestamp': timestamp,
    };
    if (consumerId != null) map['consumer_id'] = consumerId;
    if (metadata != null) map['metadata'] = metadata;
    return map;
  }

  /// Creates an event without metadata (for JSON size checking).
  Map<String, dynamic> toJsonWithoutMetadata() {
    final map = <String, dynamic>{
      'method': method,
      'path': path,
      'status_code': statusCode,
      'response_time_ms': responseTimeMs,
      'request_size': requestSize,
      'response_size': responseSize,
      'timestamp': timestamp,
    };
    if (consumerId != null) map['consumer_id'] = consumerId;
    return map;
  }

  /// Deserializes a request event from a JSON map.
  factory RequestEvent.fromJson(Map<String, dynamic> json) => RequestEvent(
        method: json['method'] as String? ?? '',
        path: json['path'] as String? ?? '',
        statusCode: json['status_code'] as int? ?? 0,
        responseTimeMs: (json['response_time_ms'] as num?)?.toDouble() ?? 0.0,
        requestSize: json['request_size'] as int? ?? 0,
        responseSize: json['response_size'] as int? ?? 0,
        consumerId: json['consumer_id'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        timestamp: json['timestamp'] as String?,
      );
}
