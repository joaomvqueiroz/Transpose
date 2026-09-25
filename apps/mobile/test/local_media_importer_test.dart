import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/media/local_media_importer.dart';

void main() {
  late Directory support;
  late LocalMediaImporter importer;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('transpono-import-test-');
    importer = LocalMediaImporter(supportDirectory: () async => support);
  });
  tearDown(() async => support.delete(recursive: true));

  test(
    'streamed imports publish durable files only after all chunks arrive',
    () async {
      final source = await importer.importPickedFile(
        _Picked(
          'song.wav',
          () => Stream.fromIterable([
            Uint8List.fromList([1, 2]),
            Uint8List.fromList([3, 4]),
          ]),
        ),
      );
      expect(source.displayName, 'song.wav');
      expect(source.locator.path, contains('/transpono_media/import-'));
      expect(await File.fromUri(source.locator).readAsBytes(), [1, 2, 3, 4]);
      expect(await _partials(support), isEmpty);
    },
  );

  test(
    'imports never collide and names cannot escape the private directory',
    () async {
      final first = await importer.importPickedFile(_bytes('../outside.mp3'));
      final second = await importer.importPickedFile(_bytes('../outside.mp3'));
      expect(first.locator, isNot(second.locator));
      expect(first.locator.path, endsWith('/media.mp3'));
      expect(first.locator.path, startsWith(support.uri.path));
      expect(await File.fromUri(first.locator).exists(), isTrue);
      expect(await File.fromUri(second.locator).exists(), isTrue);
    },
  );

  test('read failure leaves no published file or staging partial', () async {
    final selection = _Picked('broken.wav', () async* {
      yield Uint8List.fromList([1, 2]);
      throw const FileSystemException('Read failed');
    });
    await expectLater(
      importer.importPickedFile(selection),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await support.list(recursive: true).where((f) => f is File).toList(),
      isEmpty,
    );
  });

  test(
    'empty selections are rejected without a usable recovery locator',
    () async {
      await expectLater(
        importer.importPickedFile(
          _Picked('empty.mp3', () => const Stream.empty()),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await _partials(support), isEmpty);
    },
  );

  test('remote locators are rejected before their stream is read', () async {
    var opened = false;
    final selection = _Picked('remote.mp3', () {
      opened = true;
      return Stream.value(Uint8List.fromList([1]));
    }, uri: Uri.parse('https://example.com/media.mp3'));
    await expectLater(
      importer.importPickedFile(selection),
      throwsA(isA<FileSystemException>()),
    );
    expect(opened, isFalse);
  });

  test(
    'sample has a stable durable locator reused by future instances',
    () async {
      final data = ByteData.sublistView(Uint8List.fromList([82, 73, 70, 70]));
      final first = await importer.importSample(data);
      final reopened = LocalMediaImporter(
        supportDirectory: () async => support,
      );
      final second = await reopened.importSample(data);
      expect(first.locator, second.locator);
      expect(first.type, second.type);
      expect(
        first.locator.path,
        contains('/transpono_media/qa-tone-440-v1.wav'),
      );
      expect(await File.fromUri(second.locator).readAsBytes(), [
        82,
        73,
        70,
        70,
      ]);
      expect(await _partials(support), isEmpty);
    },
  );
}

Future<List<FileSystemEntity>> _partials(Directory support) => support
    .list(recursive: true)
    .where(
      (entity) =>
          entity.path.endsWith('.part') || entity.path.contains('writing-'),
    )
    .toList();

_Picked _bytes(String name) =>
    _Picked(name, () => Stream.value(Uint8List.fromList([1, 2, 3])));

final class _Picked extends PlatformFile {
  _Picked(this.name, this._stream, {Uri? uri})
    : uri = uri ?? Uri.file('C:/picker-cache/$name');
  final Stream<Uint8List> Function() _stream;
  @override
  final String name;
  @override
  final Uri uri;
  @override
  Never get xFile => throw UnimplementedError('Must use streaming API');
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() async => null;
  @override
  Future<Uint8List> readAsBytes() =>
      throw UnimplementedError('Must not buffer whole media');
  @override
  Stream<Uint8List> readAsByteStream() => _stream();
}
