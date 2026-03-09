/// PeekAPI Shelf middleware.
///
/// ```dart
/// import 'package:peekapi/shelf.dart';
///
/// final handler = const Pipeline()
///     .addMiddleware(peekApiMiddleware(client))
///     .addHandler(router);
/// ```
library peekapi.shelf;

export 'src/middleware/shelf_middleware.dart' show peekApiMiddleware;
