/// Configuration options for the PeekAPI client.
class PeekApiOptions {
  /// Your PeekAPI API key (required).
  final String apiKey;

  /// Ingest endpoint URL.
  final String endpoint;

  /// How often to flush buffered events.
  final Duration flushInterval;

  /// Max events per batch.
  final int batchSize;

  /// Max events in memory buffer.
  final int maxBufferSize;

  /// Max disk persistence size in bytes (5 MB).
  final int maxStorageBytes;

  /// Max serialized size of a single event in bytes (64 KB).
  final int maxEventBytes;

  /// Log debug info to stderr.
  final bool debug;

  /// Include query params in path (sorted alphabetically).
  final bool collectQueryString;

  /// Disk persistence file path (auto-generated if null).
  final String? storagePath;

  /// Custom consumer ID extractor. Receives request headers, returns ID.
  final String? Function(Map<String, String> headers)? identifyConsumer;

  /// Error handler callback.
  final void Function(Object error)? onError;

  const PeekApiOptions({
    required this.apiKey,
    this.endpoint = 'https://ingest.peekapi.dev/v1/events',
    this.flushInterval = const Duration(seconds: 10),
    this.batchSize = 100,
    this.maxBufferSize = 10000,
    this.maxStorageBytes = 5242880,
    this.maxEventBytes = 65536,
    this.debug = false,
    this.collectQueryString = false,
    this.storagePath,
    this.identifyConsumer,
    this.onError,
  });
}
