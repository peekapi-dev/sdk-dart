# PeekAPI — Dart SDK

[![pub.dev](https://img.shields.io/pub/v/peekapi)](https://pub.dev/packages/peekapi)
[![License](https://img.shields.io/github/license/peekapi-dev/sdk-dart)](LICENSE)
[![CI](https://github.com/peekapi-dev/sdk-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/peekapi-dev/sdk-dart/actions/workflows/ci.yml)

Zero-dependency Dart SDK for [PeekAPI](https://peekapi.dev) — plug-in API analytics with Shelf middleware.

## Install

```
dart pub add peekapi
```

## Quick Start

### Shelf

```dart
import 'package:peekapi/peekapi.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

void main() async {
  final client = await PeekApiClient.create(PeekApiOptions(
    apiKey: 'ak_live_...',
  ));

  final handler = const Pipeline()
      .addMiddleware(peekApiMiddleware(client))
      .addHandler(_router);

  await io.serve(handler, '0.0.0.0', 8080);
}
```

### Standalone Client

```dart
import 'package:peekapi/peekapi.dart';

void main() async {
  final client = await PeekApiClient.create(PeekApiOptions(
    apiKey: 'ak_live_...',
  ));

  client.track(RequestEvent(
    method: 'GET',
    path: '/api/users',
    statusCode: 200,
    responseTimeMs: 12.5,
  ));

  // On shutdown
  await client.shutdown();
}
```

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| apiKey | `String` | — | Your PeekAPI API key (required) |
| endpoint | `String` | `https://ingest.peekapi.dev/v1/events` | Ingest endpoint URL |
| flushInterval | `Duration` | 10s | How often to flush buffered events |
| batchSize | `int` | 100 | Max events per batch |
| maxBufferSize | `int` | 10000 | Max events in memory buffer |
| debug | `bool` | false | Log debug info to stderr |
| identifyConsumer | `Function?` | null | Custom consumer ID extractor |
| collectQueryString | `bool` | false | Include query params in path |
| storagePath | `String?` | auto | Disk persistence file path |
| maxStorageBytes | `int` | 5242880 | Max disk persistence size (5 MB) |
| onError | `Function?` | null | Error handler callback |

## How It Works

1. Middleware captures request metadata (method, path, status, timing, size)
2. Consumer ID extracted from `x-api-key` or `Authorization` header (SHA-256 hashed)
3. Event added to an in-memory buffer (microseconds, non-blocking)
4. Background timer flushes the buffer every 10s via HTTPS POST
5. On failure: exponential backoff, up to 5 retries, then persists to disk
6. On shutdown: remaining events flushed and persisted to disk
7. On next startup: persisted events recovered and retried

## Consumer Identification

```dart
final client = await PeekApiClient.create(PeekApiOptions(
  apiKey: 'ak_live_...',
  identifyConsumer: (headers) => headers['x-tenant-id'],
));
```

## Features

- Zero runtime dependencies (standard library only + shelf for middleware)
- Async non-blocking — your API latency is unaffected
- Automatic retry with exponential backoff
- Disk persistence for offline resilience
- SSRF protection (private IPs blocked, HTTPS enforced)
- Graceful shutdown handlers (SIGTERM/SIGINT)
- Input sanitization (path: 2048, method: 16, consumer_id: 256 chars)

## Requirements

- Dart >= 3.0

## Contributing

All issues and feature requests are tracked in the [community repo](https://github.com/peekapi-dev/community).

1. Fork this repository
2. Install dependencies: `dart pub get`
3. Run tests: `dart test`
4. Check lint/format: `dart analyze && dart format --set-exit-if-changed .`
5. Open a pull request

## Support

If you find PeekAPI useful, give this repo a star — it helps others discover the project.

### Badge

Show that your API is monitored by PeekAPI:

```markdown
[![Monitored by PeekAPI](https://img.shields.io/badge/monitored%20by-PeekAPI-06b6d4)](https://peekapi.dev)
```

## License

MIT
