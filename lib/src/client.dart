import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'event.dart';
import 'options.dart';
import 'version.dart';
import 'internal/disk_persistence.dart';
import 'internal/ssrf_protection.dart';

const _maxPathLength = 2048;
const _maxMethodLength = 16;
const _maxConsumerIdLength = 256;
const _maxConsecutiveFailures = 5;
const _baseBackoffMs = 1000;
const _sendTimeout = Duration(seconds: 10);

const _retryableStatusCodes = {429, 500, 502, 503, 504};

/// The core PeekAPI client. Buffers events in memory and flushes them
/// to the ingest endpoint in batches.
class PeekApiClient {
  final PeekApiOptions _options;
  final HttpClient _httpClient;
  final String _storagePath;
  final Uri _endpointUri;

  final List<RequestEvent> _buffer = [];
  Timer? _flushTimer;
  bool _flushInFlight = false;
  int _consecutiveFailures = 0;
  DateTime? _backoffUntil;
  bool _shutdown = false;
  StreamSubscription<ProcessSignal>? _sigtermSub;
  StreamSubscription<ProcessSignal>? _sigintSub;

  PeekApiClient._(
    this._options,
    this._httpClient,
    this._storagePath,
    this._endpointUri,
  );

  /// Creates a new PeekAPI client, validates options, and starts the
  /// background flush timer.
  ///
  /// Throws [ArgumentError] if the API key or endpoint is invalid.
  static Future<PeekApiClient> create(PeekApiOptions options) async {
    // Validate API key
    if (options.apiKey.isEmpty) {
      throw ArgumentError('apiKey must not be empty');
    }
    if (options.apiKey.contains('\r') || options.apiKey.contains('\n')) {
      throw ArgumentError('apiKey must not contain CRLF characters');
    }

    // Parse and validate endpoint
    final uri = Uri.tryParse(options.endpoint);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError('Invalid endpoint URL: ${options.endpoint}');
    }

    // Enforce HTTPS (HTTP only for localhost)
    if (uri.scheme == 'http' && !SsrfProtection.isLocalhost(uri.host)) {
      throw ArgumentError('HTTPS required for non-localhost endpoints');
    }

    // SSRF check
    await SsrfProtection.validateHost(uri.host);

    // Compute storage path
    final storagePath = options.storagePath ??
        DiskPersistence.defaultStoragePath(options.endpoint);

    // Create HTTP client
    final httpClient = HttpClient();
    httpClient.connectionTimeout = _sendTimeout;

    final client = PeekApiClient._(options, httpClient, storagePath, uri);

    // Load persisted events from disk
    client._loadFromDisk();

    // Start flush timer
    client._flushTimer = Timer.periodic(options.flushInterval, (_) {
      client._tick();
    });

    // Register shutdown hooks
    client._registerShutdownHooks();

    if (options.debug) {
      stderr.writeln(
          '[PeekAPI] Client initialized (endpoint: ${options.endpoint})');
    }

    return client;
  }

  /// Tracks a request event. Non-blocking, returns immediately.
  ///
  /// Events are buffered and flushed in batches.
  void track(RequestEvent event) {
    if (_shutdown) return;

    // Sanitize fields
    event.method = event.method.toUpperCase();
    if (event.method.length > _maxMethodLength) {
      event.method = event.method.substring(0, _maxMethodLength);
    }
    if (event.path.length > _maxPathLength) {
      event.path = event.path.substring(0, _maxPathLength);
    }
    if (event.consumerId != null &&
        event.consumerId!.length > _maxConsumerIdLength) {
      event.consumerId = event.consumerId!.substring(0, _maxConsumerIdLength);
    }

    // Auto-set timestamp
    event.timestamp ??= DateTime.now().toUtc().toIso8601String();

    // Check event size
    final jsonStr = jsonEncode(event.toJson());
    if (jsonStr.length > _options.maxEventBytes) {
      // Try without metadata
      final stripped = jsonEncode(event.toJsonWithoutMetadata());
      if (stripped.length > _options.maxEventBytes) {
        if (_options.debug) {
          stderr.writeln('[PeekAPI] Event dropped: exceeds maxEventBytes');
        }
        return;
      }
      event.metadata = null;
    }

    // Buffer management: drop oldest if full
    if (_buffer.length >= _options.maxBufferSize) {
      _buffer.removeAt(0);
      if (_options.debug) {
        stderr.writeln('[PeekAPI] Buffer full, dropped oldest event');
      }
    }

    _buffer.add(event);

    // Trigger flush if batch size reached
    if (_buffer.length >= _options.batchSize) {
      flush();
    }
  }

  /// Flushes buffered events to the ingest endpoint.
  Future<void> flush() async {
    if (_shutdown || _flushInFlight) return;
    await _doFlush();
  }

  /// Internal flush logic — can be called from shutdown (bypasses shutdown flag).
  Future<void> _doFlush() async {
    if (_buffer.isEmpty || _flushInFlight) return;

    // Backoff check
    if (_backoffUntil != null && DateTime.now().isBefore(_backoffUntil!)) {
      return;
    }

    _flushInFlight = true;

    try {
      // Extract batch
      final batchSize = _buffer.length < _options.batchSize
          ? _buffer.length
          : _options.batchSize;
      final batch = _buffer.sublist(0, batchSize);
      _buffer.removeRange(0, batchSize);

      await _send(batch);

      // Success
      _consecutiveFailures = 0;
      _backoffUntil = null;
      DiskPersistence.cleanupRecoveryFile(_storagePath);

      if (_options.debug) {
        stderr.writeln('[PeekAPI] Flushed ${batch.length} events');
      }
    } on _SendException catch (e) {
      if (e.retryable) {
        _consecutiveFailures++;
        if (_consecutiveFailures < _maxConsecutiveFailures) {
          // Re-insert batch at front
          _buffer.insertAll(0, e.events);
          // Exponential backoff
          final delayMs = _baseBackoffMs * (1 << (_consecutiveFailures - 1));
          final cappedMs = delayMs > 60000 ? 60000 : delayMs;
          _backoffUntil = DateTime.now().add(Duration(milliseconds: cappedMs));
        } else {
          // Too many failures — persist to disk
          DiskPersistence.persistToDisk(
              _storagePath, e.events, _options.maxStorageBytes);
          _consecutiveFailures = 0;
          _backoffUntil = null;
        }
      } else {
        // Non-retryable — persist to disk
        DiskPersistence.persistToDisk(
            _storagePath, e.events, _options.maxStorageBytes);
      }

      if (_options.onError != null) {
        try {
          _options.onError!(e);
        } catch (_) {
          // Ignore errors in error handler
        }
      }
    } catch (e) {
      // Unexpected error — don't lose events
      if (_options.onError != null) {
        try {
          _options.onError!(e);
        } catch (_) {
          // Ignore
        }
      }
    } finally {
      _flushInFlight = false;
    }
  }

  /// Sends a batch of events to the ingest endpoint.
  Future<void> _send(List<RequestEvent> events) async {
    final payload = jsonEncode(events.map((e) => e.toJson()).toList());

    try {
      final request =
          await _httpClient.postUrl(_endpointUri).timeout(_sendTimeout);
      request.headers.set('content-type', 'application/json');
      request.headers.set('x-api-key', _options.apiKey);
      request.headers.set('x-peekapi-sdk', sdkHeader);
      request.write(payload);

      final response = await request.close().timeout(_sendTimeout);
      await response.drain<void>();

      final status = response.statusCode;

      if (status >= 200 && status < 300) {
        return; // Success
      }

      if (_retryableStatusCodes.contains(status)) {
        throw _SendException('HTTP $status', retryable: true, events: events);
      }

      throw _SendException('HTTP $status', retryable: false, events: events);
    } on _SendException {
      rethrow;
    } on TimeoutException {
      throw _SendException('Request timeout', retryable: true, events: events);
    } on SocketException catch (e) {
      throw _SendException('Network error: ${e.message}',
          retryable: true, events: events);
    } catch (e) {
      throw _SendException('Unexpected: $e', retryable: true, events: events);
    }
  }

  /// Gracefully shuts down the client.
  ///
  /// Stops the flush timer, sends remaining events, and persists any
  /// unsent events to disk.
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;

    // Cancel timer
    _flushTimer?.cancel();
    _flushTimer = null;

    // Cancel signal subscriptions
    _sigtermSub?.cancel();
    _sigintSub?.cancel();

    // Final flush (bypass shutdown flag via _doFlush)
    _flushInFlight = false;
    await _doFlush();

    // Persist remaining buffer to disk
    if (_buffer.isNotEmpty) {
      DiskPersistence.persistToDisk(
          _storagePath, _buffer, _options.maxStorageBytes);
      _buffer.clear();
    }

    _httpClient.close();

    if (_options.debug) {
      stderr.writeln('[PeekAPI] Client shut down');
    }
  }

  void _tick() {
    if (_shutdown || _flushInFlight) return;
    _doFlush();
  }

  void _loadFromDisk() {
    final available = _options.maxBufferSize - _buffer.length;
    if (available <= 0) return;

    final events = DiskPersistence.loadFromDisk(_storagePath, available);
    if (events.isNotEmpty) {
      _buffer.addAll(events);
      if (_options.debug) {
        stderr.writeln('[PeekAPI] Recovered ${events.length} events from disk');
      }
    }
  }

  void _registerShutdownHooks() {
    try {
      _sigtermSub = ProcessSignal.sigterm.watch().listen((_) => shutdown());
    } catch (_) {
      // SIGTERM not supported on this platform (e.g., Windows)
    }
    try {
      _sigintSub = ProcessSignal.sigint.watch().listen((_) => shutdown());
    } catch (_) {
      // SIGINT not supported on this platform
    }
  }

  /// The number of buffered events (for testing).
  int get bufferLength => _buffer.length;
}

class _SendException implements Exception {
  final String message;
  final bool retryable;
  final List<RequestEvent> events;

  _SendException(this.message, {required this.retryable, required this.events});

  @override
  String toString() => 'SendException: $message (retryable: $retryable)';
}
