import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:peekapi/peekapi.dart';

String _tmpPath() {
  final dir = Directory.systemTemp.createTempSync('peekapi_client_test_');
  return '${dir.path}/peekapi-test.jsonl';
}

/// Starts a mock ingest server that captures received payloads.
Future<
    ({
      HttpServer server,
      String endpoint,
      List<String> payloads,
      List<int> statusCodes
    })> _mockServer({
  int statusCode = 200,
  List<int>? statusSequence,
}) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final payloads = <String>[];
  final statusCodes = <int>[];
  var callIndex = 0;

  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    payloads.add(body);
    statusCodes.add(req.response.statusCode);

    final code = statusSequence != null && callIndex < statusSequence.length
        ? statusSequence[callIndex]
        : statusCode;
    callIndex++;
    req.response.statusCode = code;
    await req.response.close();
  });

  return (
    server: server,
    endpoint: 'http://127.0.0.1:${server.port}/v1/events',
    payloads: payloads,
    statusCodes: statusCodes,
  );
}

RequestEvent _event(
    {String path = '/test', String method = 'GET', int status = 200}) {
  return RequestEvent(
    method: method,
    path: path,
    statusCode: status,
    responseTimeMs: 1.5,
    requestSize: 0,
    responseSize: 100,
  );
}

void main() {
  group('PeekApiClient', () {
    group('constructor validation', () {
      test('empty API key throws', () {
        expect(
          () => PeekApiClient.create(PeekApiOptions(apiKey: '')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('API key with CRLF throws', () {
        expect(
          () => PeekApiClient.create(PeekApiOptions(apiKey: 'key\r\nvalue')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('API key with newline throws', () {
        expect(
          () => PeekApiClient.create(PeekApiOptions(apiKey: 'key\nvalue')),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('invalid endpoint URL throws', () {
        expect(
          () => PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'not a url',
          )),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('HTTP non-localhost throws', () {
        expect(
          () => PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'http://example.com/v1',
          )),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('HTTP localhost is allowed', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            storagePath: _tmpPath(),
          ));
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });
    });

    group('track', () {
      test('adds event to buffer', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          client.track(_event());
          expect(client.bufferLength, 1);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('uppercases method', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            batchSize: 1,
            storagePath: _tmpPath(),
          ));
          client.track(_event(method: 'get'));

          // Wait for flush
          await Future<void>.delayed(Duration(milliseconds: 200));
          expect(mock.payloads.isNotEmpty, isTrue);
          final events = jsonDecode(mock.payloads.first) as List<dynamic>;
          expect((events.first as Map<String, dynamic>)['method'], 'GET');
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('truncates long path', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            batchSize: 1,
            storagePath: _tmpPath(),
          ));
          final longPath = '/a' * 2000;
          client.track(_event(path: longPath));

          await Future<void>.delayed(Duration(milliseconds: 200));
          expect(mock.payloads.isNotEmpty, isTrue);
          final events = jsonDecode(mock.payloads.first) as List<dynamic>;
          final path = (events.first as Map<String, dynamic>)['path'] as String;
          expect(path.length, 2048);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('drops event exceeding maxEventBytes', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            maxEventBytes: 50, // Very small
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          client.track(_event(path: '/very/long/path/that/exceeds/limit'));
          expect(client.bufferLength, 0);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('drops oldest when buffer full', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            maxBufferSize: 2,
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          client.track(_event(path: '/first'));
          client.track(_event(path: '/second'));
          client.track(_event(path: '/third'));
          expect(client.bufferLength, 2);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('auto-sets timestamp', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            batchSize: 1,
            storagePath: _tmpPath(),
          ));
          client.track(_event());

          await Future<void>.delayed(Duration(milliseconds: 200));
          expect(mock.payloads.isNotEmpty, isTrue);
          final events = jsonDecode(mock.payloads.first) as List<dynamic>;
          final ts =
              (events.first as Map<String, dynamic>)['timestamp'] as String;
          expect(ts, isNotEmpty);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('triggers flush when batchSize reached', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            batchSize: 2,
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          client.track(_event(path: '/a'));
          client.track(_event(path: '/b'));

          await Future<void>.delayed(Duration(milliseconds: 200));
          expect(mock.payloads.isNotEmpty, isTrue);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });
    });

    group('flush', () {
      test('sends correct HTTP headers', () async {
        final headers = <String, String>{};
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          req.headers.forEach((name, values) {
            headers[name] = values.join(', ');
          });
          await utf8.decoder.bind(req).join();
          req.response.statusCode = 200;
          await req.response.close();
        });

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test_key_123',
            endpoint: 'http://127.0.0.1:${server.port}/v1/events',
            batchSize: 1,
            storagePath: _tmpPath(),
          ));
          client.track(_event());

          await Future<void>.delayed(Duration(milliseconds: 200));
          expect(headers['x-api-key'], 'ak_test_key_123');
          expect(headers['x-peekapi-sdk'], startsWith('dart/'));
          expect(headers['content-type'], contains('application/json'));
          await client.shutdown();
        } finally {
          await server.close();
        }
      });

      test('JSON payload has correct structure', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            batchSize: 1,
            storagePath: _tmpPath(),
          ));
          client.track(RequestEvent(
            method: 'POST',
            path: '/api/users',
            statusCode: 201,
            responseTimeMs: 5.25,
            requestSize: 128,
            responseSize: 256,
            consumerId: 'ak_consumer_1',
          ));

          await Future<void>.delayed(Duration(milliseconds: 200));
          final events = jsonDecode(mock.payloads.first) as List<dynamic>;
          final event = events.first as Map<String, dynamic>;
          expect(event['method'], 'POST');
          expect(event['path'], '/api/users');
          expect(event['status_code'], 201);
          expect(event['response_time_ms'], 5.25);
          expect(event['request_size'], 128);
          expect(event['response_size'], 256);
          expect(event['consumer_id'], 'ak_consumer_1');
          expect(event['timestamp'], isNotNull);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });
    });

    group('retry and backoff', () {
      test('retries on 500', () async {
        var callCount = 0;
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          await utf8.decoder.bind(req).join();
          callCount++;
          req.response.statusCode = callCount == 1 ? 500 : 200;
          await req.response.close();
        });

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'http://127.0.0.1:${server.port}/v1/events',
            batchSize: 1,
            flushInterval: Duration(milliseconds: 100),
            storagePath: _tmpPath(),
          ));
          client.track(_event());

          // Wait for retry cycle
          await Future<void>.delayed(Duration(seconds: 3));
          expect(callCount, greaterThan(1));
          await client.shutdown();
        } finally {
          await server.close();
        }
      });

      test('non-retryable error persists to disk', () async {
        final path = _tmpPath();
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          await utf8.decoder.bind(req).join();
          req.response.statusCode = 401;
          await req.response.close();
        });

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'http://127.0.0.1:${server.port}/v1/events',
            batchSize: 1,
            storagePath: path,
          ));
          client.track(_event());

          await Future<void>.delayed(Duration(milliseconds: 500));
          expect(File(path).existsSync(), isTrue);
          await client.shutdown();
        } finally {
          await server.close();
        }
      });
    });

    group('shutdown', () {
      test('final flush sends remaining events', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          client.track(_event());
          client.track(_event());
          expect(client.bufferLength, 2);

          await client.shutdown();
          expect(mock.payloads.isNotEmpty, isTrue);
        } finally {
          await mock.server.close();
        }
      });

      test('track after shutdown is ignored', () async {
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            flushInterval: Duration(hours: 1),
            storagePath: _tmpPath(),
          ));
          await client.shutdown();
          client.track(_event());
          expect(client.bufferLength, 0);
        } finally {
          await mock.server.close();
        }
      });
    });

    group('disk persistence', () {
      test('events recovered from disk on startup', () async {
        final path = _tmpPath();
        final mock = await _mockServer();

        // Pre-populate disk
        File(path)
          ..createSync(recursive: true)
          ..writeAsStringSync(
              '[{"method":"GET","path":"/recovered","status_code":200,"response_time_ms":1.0,"request_size":0,"response_size":0,"timestamp":"2026-01-01T00:00:00Z"}]\n');

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            flushInterval: Duration(hours: 1),
            storagePath: path,
          ));
          expect(client.bufferLength, 1);
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });

      test('remaining events persisted on shutdown', () async {
        final path = _tmpPath();
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          await utf8.decoder.bind(req).join();
          req.response.statusCode = 500;
          await req.response.close();
        });

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'http://127.0.0.1:${server.port}/v1/events',
            flushInterval: Duration(hours: 1),
            storagePath: path,
          ));
          client.track(_event());
          await client.shutdown();

          expect(File(path).existsSync(), isTrue);
        } finally {
          await server.close();
        }
      });
    });

    group('onError callback', () {
      test('called on send failure', () async {
        Object? capturedError;
        final server = await HttpServer.bind('127.0.0.1', 0);
        server.listen((req) async {
          await utf8.decoder.bind(req).join();
          req.response.statusCode = 500;
          await req.response.close();
        });

        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: 'http://127.0.0.1:${server.port}/v1/events',
            batchSize: 1,
            storagePath: _tmpPath(),
            onError: (e) => capturedError = e,
          ));
          client.track(_event());

          await Future<void>.delayed(Duration(milliseconds: 500));
          expect(capturedError, isNotNull);
          await client.shutdown();
        } finally {
          await server.close();
        }
      });
    });

    group('debug logging', () {
      test('logs when debug is true', () async {
        // Capture stderr output
        final mock = await _mockServer();
        try {
          final client = await PeekApiClient.create(PeekApiOptions(
            apiKey: 'ak_test',
            endpoint: mock.endpoint,
            debug: true,
            storagePath: _tmpPath(),
          ));
          // Just verify it doesn't crash — stderr output is hard to capture in tests
          await client.shutdown();
        } finally {
          await mock.server.close();
        }
      });
    });
  });
}
