import 'dart:convert';
import 'dart:io';

import '../event.dart';

/// JSONL-based disk persistence for undelivered events.
///
/// File format: one JSON array per line. Each line is a batch of events.
class DiskPersistence {
  /// Computes the default storage path based on the endpoint URL.
  ///
  /// Uses first 8 hex chars of SHA-256(endpoint) as the filename hash.
  /// (Imported SHA-256 would add a circular dep, so we use hashCode as fallback.)
  static String defaultStoragePath(String endpoint) {
    // Simple hash for filename — doesn't need to be cryptographic
    final hash =
        endpoint.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    final tmpDir = Directory.systemTemp.path;
    return '$tmpDir/peekapi-events-$hash.jsonl';
  }

  /// Persists [events] to the JSONL file at [storagePath].
  ///
  /// Returns true on success, false on failure or if limits are exceeded.
  static bool persistToDisk(
    String storagePath,
    List<RequestEvent> events,
    int maxStorageBytes,
  ) {
    if (events.isEmpty) return false;

    try {
      final file = File(storagePath);

      // Check existing file size
      if (file.existsSync() && file.lengthSync() >= maxStorageBytes) {
        return false;
      }

      // Create parent directories if needed
      file.parent.createSync(recursive: true);

      // Build JSONL line: [event1, event2, ...]\n
      final jsonLine = jsonEncode(events.map((e) => e.toJson()).toList());
      file.writeAsStringSync('$jsonLine\n', mode: FileMode.append);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads persisted events from disk.
  ///
  /// Uses crash-safe recovery: renames .jsonl to .recovering before reading.
  /// Returns up to [maxEvents] events.
  static List<RequestEvent> loadFromDisk(String storagePath, int maxEvents) {
    if (maxEvents <= 0) return [];

    final events = <RequestEvent>[];
    final recoveringPath = '$storagePath.recovering';

    try {
      final recoveringFile = File(recoveringPath);
      final mainFile = File(storagePath);

      // Check for .recovering file first (previous interrupted recovery)
      File source;
      if (recoveringFile.existsSync()) {
        source = recoveringFile;
      } else if (mainFile.existsSync()) {
        // Rename to .recovering for crash safety
        mainFile.renameSync(recoveringPath);
        source = File(recoveringPath);
      } else {
        return [];
      }

      final lines = source.readAsLinesSync();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final list = jsonDecode(line) as List<dynamic>;
          for (final item in list) {
            if (events.length >= maxEvents) break;
            events.add(RequestEvent.fromJson(item as Map<String, dynamic>));
          }
        } catch (_) {
          // Skip corrupted lines
        }
        if (events.length >= maxEvents) break;
      }

      // Cleanup after successful read
      source.deleteSync();
    } catch (_) {
      // Best-effort recovery
    }

    return events;
  }

  /// Deletes the .recovering file after a successful flush.
  static void cleanupRecoveryFile(String storagePath) {
    try {
      final file = File('$storagePath.recovering');
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Ignore
    }
  }

  /// Deletes both .jsonl and .recovering files.
  static void deleteAll(String storagePath) {
    try {
      final main = File(storagePath);
      if (main.existsSync()) main.deleteSync();
    } catch (_) {
      // Ignore
    }
    try {
      final recovering = File('$storagePath.recovering');
      if (recovering.existsSync()) recovering.deleteSync();
    } catch (_) {
      // Ignore
    }
  }
}
