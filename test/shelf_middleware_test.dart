import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:peekapi/peekapi.dart';

String _tmpPath() {
  final dir = Directory.systemTemp.createTempSync('peekapi_shelf_test_');
  return '${dir.path}/peekapi-test.jsonl';
}

Future<
    ({
      HttpServer mockServer,
      String endpoint,
      List<List<Map<String, dynamic>>> batches
    })> _startMock() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final batches = <List<Map<String, dynamic>>>[];

  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    final list = (jsonDecode(body) as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    batches.add(list);
    req.response.statusCode = 200;
    await req.response.close();
  });

  return (
    mockServer: server,
    endpoint: 'http://127.0.0.1:${server.port}/v1/events',
    batches: batches,
  );
}

void main() {
  group('peekApiMiddleware', () {
    late HttpServer mockServer;
    late PeekApiClient client;
    late List<List<Map<String, dynamic>>> batches;

    setUp(() async {
      final mock = await _startMock();
      mockServer = mock.mockServer;
      batches = mock.batches;
      client = await PeekApiClient.create(PeekApiOptions(
        apiKey: 'ak_test',
        endpoint: mock.endpoint,
        batchSize: 1,
        flushInterval: Duration(hours: 1),
        storagePath: _tmpPath(),
      ));
    });

    tearDown(() async {
      await client.shutdown();
      await mockServer.close();
    });

    Future<Response> callMiddleware(
      Request request, {
      Handler? handler,
      PeekApiOptions? options,
      PeekApiClient? overrideClient,
    }) async {
      final middleware =
          peekApiMiddleware(overrideClient ?? client, options: options);
      final pipeline = middleware(handler ?? (req) => Response.ok('OK'));
      return await pipeline(request);
    }

    Request makeReq({
      String method = 'GET',
      String path = '/api/users',
      Map<String, String>? headers,
    }) {
      return Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: headers,
      );
    }

    test('tracks request with correct method', () async {
      await callMiddleware(makeReq(method: 'POST'));

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.isNotEmpty, isTrue);
      expect(batches.first.first['method'], 'POST');
    });

    test('tracks request with correct path', () async {
      await callMiddleware(makeReq(path: '/api/products'));

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['path'], '/api/products');
    });

    test('tracks response status code', () async {
      await callMiddleware(
        makeReq(),
        handler: (req) => Response(201),
      );

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['status_code'], 201);
    });

    test('response timing is captured (> 0ms)', () async {
      await callMiddleware(
        makeReq(),
        handler: (req) async {
          await Future<void>.delayed(Duration(milliseconds: 10));
          return Response.ok('OK');
        },
      );

      await Future<void>.delayed(Duration(milliseconds: 200));
      final time = batches.first.first['response_time_ms'] as num;
      expect(time, greaterThan(0));
    });

    test('consumer ID from x-api-key header', () async {
      await callMiddleware(makeReq(headers: {'x-api-key': 'ak_consumer_123'}));

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['consumer_id'], 'ak_consumer_123');
    });

    test('consumer ID from Authorization header (hashed)', () async {
      await callMiddleware(
          makeReq(headers: {'authorization': 'Bearer secret'}));

      await Future<void>.delayed(Duration(milliseconds: 200));
      final id = batches.first.first['consumer_id'] as String;
      expect(id, startsWith('hash_'));
      expect(id.length, 17);
    });

    test('custom identifyConsumer callback', () async {
      final options = PeekApiOptions(
        apiKey: 'ak_test',
        identifyConsumer: (headers) => headers['x-tenant-id'],
      );
      await callMiddleware(
        makeReq(headers: {'x-tenant-id': 'tenant_abc'}),
        options: options,
      );

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['consumer_id'], 'tenant_abc');
    });

    test('query string sorted when collectQueryString enabled', () async {
      final options = PeekApiOptions(
        apiKey: 'ak_test',
        collectQueryString: true,
      );
      await callMiddleware(
        makeReq(path: '/api/search?z=3&a=1&m=2'),
        options: options,
      );

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['path'], '/api/search?a=1&m=2&z=3');
    });

    test('query string excluded by default', () async {
      await callMiddleware(makeReq(path: '/api/search?q=test'));

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['path'], '/api/search');
    });

    test('exception in handler does not break tracking', () async {
      try {
        await callMiddleware(
          makeReq(),
          handler: (req) => throw Exception('handler error'),
        );
      } catch (_) {
        // Expected
      }

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.isNotEmpty, isTrue);
      expect(batches.first.first['status_code'], 500);
    });

    test('null client passes through without crash', () async {
      final middleware = peekApiMiddleware(null);
      final handler = middleware((req) => Response.ok('pass'));
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/test')),
      );
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, 'pass');
    });

    test('response size tracked from content-length', () async {
      await callMiddleware(
        makeReq(),
        handler: (req) => Response.ok(
          'Hello, World!',
          headers: {'content-length': '13'},
        ),
      );

      await Future<void>.delayed(Duration(milliseconds: 200));
      expect(batches.first.first['response_size'], 13);
    });
  });
}
