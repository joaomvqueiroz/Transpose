import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transpose_mobile/media/local_media_importer.dart';

void main() {
  test('removes only old copies nothing refers to', () async {
    final Directory support = await Directory.systemTemp.createTemp('tp-');
    addTearDown(() => support.delete(recursive: true));
    final Directory media = Directory('${support.path}/transpono_media')
      ..createSync();
    Directory copy(String name) =>
        Directory('${media.path}/$name')..createSync();
    final Directory used = copy('import-used');
    final Directory unused = copy('import-unused');
    final Directory recent = copy('import-recent');
    final Directory other = copy('rhythm-preview-x');
    File('${unused.path}/media.mp3').writeAsStringSync('x');

    final importer = LocalMediaImporter(supportDirectory: () async => support);
    final int removed = await importer.removeUnused(<String>[
      'file:///data/transpono_media/import-used/media.mp3',
    ], grace: Duration.zero);
    expect(removed, 2); // unused and recent (no grace in this test)
    expect(used.existsSync(), isTrue);
    expect(unused.existsSync(), isFalse);
    expect(recent.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);

    final Directory fresh = copy('import-fresh');
    expect(await importer.removeUnused(const <String>[]), 0);
    expect(fresh.existsSync(), isTrue);
  });
}
