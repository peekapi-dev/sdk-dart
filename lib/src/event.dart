/// Represents a single API request event captured by PeekAPI.
class RequestEvent {
  String method;
  String path;
  int statusCode;
  double responseTimeMs;
  int requestSize;
  int responseSize;
  String? consumerId;
  Map<String, dynamic>? metadata;
  String? timestamp;

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
