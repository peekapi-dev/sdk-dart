/// PeekAPI Dart SDK — zero-dependency API analytics.
///
/// Provides a buffered HTTP client for sending API request events
/// to the PeekAPI ingest endpoint, plus Shelf middleware.
library peekapi;

export 'src/client.dart' show PeekApiClient;
export 'src/event.dart' show RequestEvent;
export 'src/options.dart' show PeekApiOptions;
export 'src/middleware/shelf_middleware.dart' show peekApiMiddleware;
