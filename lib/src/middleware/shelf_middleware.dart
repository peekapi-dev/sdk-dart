import 'package:shelf/shelf.dart';

import '../client.dart';
import '../event.dart';
import '../options.dart';
import '../internal/consumer_identifier.dart';

/// Creates a Shelf [Middleware] that tracks API requests with PeekAPI.
///
/// Usage:
/// ```dart
/// final handler = const Pipeline()
///     .addMiddleware(peekApiMiddleware(client))
///     .addHandler(router);
/// ```
Middleware peekApiMiddleware(
  PeekApiClient? client, {
  PeekApiOptions? options,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      // Null client → passthrough
      if (client == null) return innerHandler(request);

      final stopwatch = Stopwatch()..start();
      Response response;

      try {
        response = await innerHandler(request);
      } catch (e) {
        stopwatch.stop();
        // Track the error but rethrow
        try {
          _trackRequest(
            client,
            options,
            request,
            500,
            stopwatch.elapsedMicroseconds / 1000.0,
            0,
          );
        } catch (_) {
          // Never break the request
        }
        rethrow;
      }

      stopwatch.stop();

      try {
        final responseSize = response.contentLength ?? 0;
        _trackRequest(
          client,
          options,
          request,
          response.statusCode,
          stopwatch.elapsedMicroseconds / 1000.0,
          responseSize,
        );
      } catch (_) {
        // Never break the response
      }

      return response;
    };
  };
}

void _trackRequest(
  PeekApiClient client,
  PeekApiOptions? options,
  Request request,
  int statusCode,
  double responseTimeMs,
  int responseSize,
) {
  // Build path
  var path = request.requestedUri.path;
  if (options?.collectQueryString == true) {
    final query = request.requestedUri.query;
    if (query.isNotEmpty) {
      final params = query.split('&')..sort();
      path = '$path?${params.join('&')}';
    }
  }

  // Resolve consumer ID
  String? consumerId;
  if (options?.identifyConsumer != null) {
    try {
      consumerId = options!.identifyConsumer!(request.headers);
    } catch (_) {
      // Fall through to default
    }
  }
  consumerId ??= ConsumerIdentifier.identify(
    request.headers['x-api-key'],
    request.headers['authorization'],
  );

  final requestSize = request.contentLength ?? 0;

  // Round to 2 decimal places
  final roundedTime = (responseTimeMs * 100).round() / 100.0;

  client.track(RequestEvent(
    method: request.method,
    path: path,
    statusCode: statusCode,
    responseTimeMs: roundedTime,
    requestSize: requestSize,
    responseSize: responseSize,
    consumerId: consumerId,
  ));
}
