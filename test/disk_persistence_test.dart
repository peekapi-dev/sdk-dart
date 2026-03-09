import 'dart:io';
import 'package:test/test.dart';
import 'package:peekapi/src/event.dart';
import 'package:peekapi/src/internal/disk_persistence.dart';

String _tmpPath() {
  final dir = Directory.systemTemp.createTempSync('peekapi_test_');
  return '${dir.path}/peekapi-test.jsonl';
}

RequestEvent _event({String path = '/test', int status = 200}) {
  return RequestEvent(
    method: 'GET',
    path: path,
    statusCode: status,
    responseTimeMs: 1.5,
    requestSize: 0,
    responseSize: 100,
    timestamp: '2026-01-01T00:00:00Z',
  );
}

void main() {
  group('DiskPersistence', () {
    late String storagePath;

    setUp(() {
      storagePath = _tmpPath();
    });

    tearDown(() {
      DiskPersistence.deleteAll(storagePath);
      // Cleanup temp directory
      try {
        File(storagePath).parent.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('defaultStoragePath returns consistent path', () {
      final p1 = DiskPersistence.defaultStoragePath('https://example.com/v1');
      final p2 = DiskPersistence.defaultStoragePath('https://example.com/v1');
      expect(p1, p2);
    });

    test('defaultStoragePath differs for different endpoints', () {
      final p1 = DiskPersistence.defaultStoragePath('https://a.com/v1');
      final p2 = DiskPersistence.defaultStoragePath('https://b.com/v1');
      expect(p1, isNot(p2));
    });

    test('persist and load round-trip', () {
      final events = [_event(path: '/a'), _event(path: '/b')];
      final ok = DiskPersistence.persistToDisk(storagePath, events, 5242880);
      expect(ok, isTrue);

      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded.length, 2);
      expect(loaded[0].path, '/a');
      expect(loaded[1].path, '/b');
    });

    test('persist appends multiple batches', () {
      DiskPersistence.persistToDisk(storagePath, [_event(path: '/a')], 5242880);
      DiskPersistence.persistToDisk(storagePath, [_event(path: '/b')], 5242880);

      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded.length, 2);
      expect(loaded[0].path, '/a');
      expect(loaded[1].path, '/b');
    });

    test('load with maxEvents limit', () {
      final events = [
        _event(path: '/a'),
        _event(path: '/b'),
        _event(path: '/c')
      ];
      DiskPersistence.persistToDisk(storagePath, events, 5242880);

      final loaded = DiskPersistence.loadFromDisk(storagePath, 2);
      expect(loaded.length, 2);
    });

    test('.recovering file renamed during load', () {
      DiskPersistence.persistToDisk(storagePath, [_event()], 5242880);
      expect(File(storagePath).existsSync(), isTrue);

      // Load triggers rename to .recovering
      DiskPersistence.loadFromDisk(storagePath, 100);

      // Both should be cleaned up after successful load
      expect(File(storagePath).existsSync(), isFalse);
      expect(File('$storagePath.recovering').existsSync(), isFalse);
    });

    test('max storage bytes enforced', () {
      // Persist a large enough batch to fill storage
      final events = List.generate(100, (i) => _event(path: '/path/$i'));
      DiskPersistence.persistToDisk(storagePath, events, 100); // 100 bytes max

      // File exists but subsequent writes should fail
      final ok = DiskPersistence.persistToDisk(storagePath, [_event()], 100);
      expect(ok, isFalse);
    });

    test('empty events returns false', () {
      expect(DiskPersistence.persistToDisk(storagePath, [], 5242880), isFalse);
    });

    test('empty file returns empty list', () {
      File(storagePath)
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded, isEmpty);
    });

    test('corrupted line is skipped without crash', () {
      File(storagePath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
            'not valid json\n[{"method":"GET","path":"/ok","status_code":200,"response_time_ms":1.0,"request_size":0,"response_size":0,"timestamp":"2026-01-01T00:00:00Z"}]\n');

      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded.length, 1);
      expect(loaded[0].path, '/ok');
    });

    test('handles interrupted recovery file', () {
      // Simulate a previous crash: .recovering file exists
      File('$storagePath.recovering')
        ..createSync(recursive: true)
        ..writeAsStringSync(
            '[{"method":"GET","path":"/recovered","status_code":200,"response_time_ms":1.0,"request_size":0,"response_size":0,"timestamp":"2026-01-01T00:00:00Z"}]\n');

      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded.length, 1);
      expect(loaded[0].path, '/recovered');
    });

    test('deleteAll removes both files', () {
      DiskPersistence.persistToDisk(storagePath, [_event()], 5242880);
      File('$storagePath.recovering')
        ..createSync(recursive: true)
        ..writeAsStringSync('test\n');

      DiskPersistence.deleteAll(storagePath);
      expect(File(storagePath).existsSync(), isFalse);
      expect(File('$storagePath.recovering').existsSync(), isFalse);
    });

    test('cleanupRecoveryFile removes .recovering', () {
      File('$storagePath.recovering')
        ..createSync(recursive: true)
        ..writeAsStringSync('test\n');
      DiskPersistence.cleanupRecoveryFile(storagePath);
      expect(File('$storagePath.recovering').existsSync(), isFalse);
    });

    test('loadFromDisk with zero maxEvents returns empty', () {
      DiskPersistence.persistToDisk(storagePath, [_event()], 5242880);
      final loaded = DiskPersistence.loadFromDisk(storagePath, 0);
      expect(loaded, isEmpty);
    });

    test('event fields preserved through round-trip', () {
      final event = RequestEvent(
        method: 'POST',
        path: '/api/users',
        statusCode: 201,
        responseTimeMs: 42.5,
        requestSize: 256,
        responseSize: 512,
        consumerId: 'ak_test_123',
        timestamp: '2026-01-01T00:00:00Z',
      );
      DiskPersistence.persistToDisk(storagePath, [event], 5242880);
      final loaded = DiskPersistence.loadFromDisk(storagePath, 100);
      expect(loaded.length, 1);
      expect(loaded[0].method, 'POST');
      expect(loaded[0].path, '/api/users');
      expect(loaded[0].statusCode, 201);
      expect(loaded[0].responseTimeMs, 42.5);
      expect(loaded[0].requestSize, 256);
      expect(loaded[0].responseSize, 512);
      expect(loaded[0].consumerId, 'ak_test_123');
    });
  });
}
