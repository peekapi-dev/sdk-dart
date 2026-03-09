import 'package:peekapi/peekapi.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

void main() async {
  // Create the PeekAPI client
  final client = await PeekApiClient.create(PeekApiOptions(
    apiKey: 'ak_live_your_key_here',
  ));

  // Build a Shelf pipeline with PeekAPI middleware
  final handler = const Pipeline()
      .addMiddleware(peekApiMiddleware(client))
      .addHandler(_router);

  // Start the server
  final server = await io.serve(handler, 'localhost', 8080);
  print('Server running on http://localhost:${server.port}');
}

Response _router(Request request) {
  return Response.ok('Hello, World!');
}
