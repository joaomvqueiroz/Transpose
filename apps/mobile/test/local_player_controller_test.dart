import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_core/player_core.dart';
import 'package:transpose_mobile/media/local_player_controller.dart';
import 'package:transpose_mobile/media/local_media_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source is replaced only after the durable import succeeds', () async {
    final loader = _Loader();
    final importer = _BlockingImporter();
    final player = LocalPlayerController(
      loader: loader,
      importer: importer,
      filePicker: () async => _Picked(),
    );
    await player.load(_source('current'));
    await player.playPause();
    final importing = player.pickFile();
    await Future<void>.delayed(Duration.zero);
    expect(player.busy, isTrue);
    expect(player.sourceId, 'current');
    expect(player.playing, isTrue);
    expect(loader.events, ['load:current', 'play:current']);
    importer.gate.complete(_source('durable'));
    await importing;
    expect(player.sourceId, 'durable');
    expect(player.playing, isFalse);
    expect(player.message, isNull);
    expect(loader.events, [
      'load:current',
      'play:current',
      'release:current',
      'load:durable',
    ]);
    await player.close();
    player.dispose();
  });

  test(
    'failed import leaves the previous source and playback intact',
    () async {
      final loader = _Loader();
      final player = LocalPlayerController(
        loader: loader,
        importer: _FailedImporter(),
        filePicker: () async => _Picked(),
      );
      await player.load(_source('current'));
      await player.playPause();
      await player.pickFile();
      expect(player.loaded, isTrue);
      expect(player.playing, isTrue);
      expect(player.sourceId, 'current');
      expect(player.message, isNotNull);
      expect(loader.events, ['load:current', 'play:current']);
      await player.close();
      player.dispose();
    },
  );

  test('picker cancellation never replaces the current source', () async {
    final loader = _Loader();
    final player = LocalPlayerController(
      loader: loader,
      filePicker: () async => null,
    );
    await player.load(_source('current'));
    await player.pickFile();
    expect(player.sourceId, 'current');
    expect(loader.events, ['load:current']);
    await player.close();
    player.dispose();
  });

  test(
    'replacement waits for load and releases old output before loading new',
    () async {
      final _Loader loader = _Loader()..gate = Completer<void>();
      final LocalPlayerController player = LocalPlayerController(
        loader: loader,
      );
      final Future<void> first = player.load(_source('one'));
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = player.load(_source('two'));
      expect(player.busy, isTrue);
      expect(loader.events, <String>['load:one']);

      loader.gate!.complete();
      await Future.wait(<Future<void>>[first, second]);
      expect(loader.events, <String>['load:one', 'release:one', 'load:two']);
      expect(player.loaded, isTrue);
      expect(player.sourceId, 'two');
      expect(player.title, 'two.wav');
      expect(player.busy, isFalse);
      await player.close();
      player.dispose();
    },
  );

  test('background pause queued during load stops a queued play', () async {
    final _Loader loader = _Loader()..gate = Completer<void>();
    final LocalPlayerController player = LocalPlayerController(loader: loader);
    final Future<void> loading = player.load(_source('one'));
    final Future<void> playing = player.playPause();
    final Future<void> pausing = player.pause();
    loader.gate!.complete();
    await Future.wait(<Future<void>>[loading, playing, pausing]);
    expect(player.playing, isFalse);
    expect(loader.events, <String>['load:one', 'play:one', 'pause:one']);
    await player.close();
    player.dispose();
  });

  test('close awaits release and the controller can load again', () async {
    final _Loader loader = _Loader();
    final LocalPlayerController player = LocalPlayerController(loader: loader);
    await player.load(_source('one'));
    await player.playPause();
    loader.current!.releaseGate = Completer<void>();
    final Future<void> closing = player.close();
    await Future<void>.delayed(Duration.zero);
    expect(player.busy, isTrue);
    expect(loader.current!.released, isFalse);
    loader.current!.releaseGate!.complete();
    await closing;
    expect(loader.current!.released, isTrue);
    expect(player.loaded, isFalse);
    expect(player.playing, isFalse);
    expect(player.position, Duration.zero);
    await player.load(_source('two'));
    expect(player.sourceId, 'two');
    await player.close();
    player.dispose();
  });

  test(
    'end restarts from zero; seeks are bounded to the loaded duration',
    () async {
      final _Loader loader = _Loader();
      final LocalPlayerController player = LocalPlayerController(
        loader: loader,
      );
      await player.load(_source('one'));
      await player.seek(const Duration(minutes: 10));
      expect(player.position, const Duration(seconds: 30));
      await player.seek(const Duration(seconds: -4));
      expect(player.position, Duration.zero);
      await player.playPause();
      loader.current!.end();
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, isFalse);
      await player.playPause();
      expect(player.playing, isTrue);
      expect(player.position, Duration.zero);
      await player.close();
      player.dispose();
    },
  );

  test(
    'failed load is reported and does not poison the next command',
    () async {
      final _Loader loader = _Loader()..failNext = true;
      final LocalPlayerController player = LocalPlayerController(
        loader: loader,
      );
      await player.load(_source('one'));
      expect(player.loaded, isFalse);
      expect(player.busy, isFalse);
      expect(player.message, isNotNull);
      expect(player.canPitch, isFalse);
      await player.load(_source('two'));
      expect(player.loaded, isTrue);
      expect(player.message, isNull);
      await player.close();
      player.dispose();
    },
  );

  test(
    'failed close retains ownership until release succeeds on retry',
    () async {
      final _Loader loader = _Loader();
      final LocalPlayerController player = LocalPlayerController(
        loader: loader,
      );
      await player.load(_source('one'));
      loader.current!.failRelease = true;
      await player.close();
      expect(player.hasResource, isTrue);
      expect(player.loaded, isFalse);
      expect(player.message, isNotNull);
      expect(loader.current!.released, isFalse);
      loader.current!.failRelease = false;
      await player.close();
      expect(player.hasResource, isFalse);
      expect(loader.current!.released, isTrue);
      player.dispose();
    },
  );

  test(
    'dispose during load releases resource and does not start queued play',
    () async {
      final _Loader loader = _Loader()..gate = Completer<void>();
      final LocalPlayerController player = LocalPlayerController(
        loader: loader,
      );
      final Future<void> loading = player.load(_source('one'));
      await Future<void>.delayed(Duration.zero);
      final Future<void> playing = player.playPause();
      player.dispose();
      loader.gate!.complete();
      await Future.wait(<Future<void>>[loading, playing]);
      await Future<void>.delayed(Duration.zero);
      expect(loader.events, <String>['load:one', 'release:one']);
      expect(loader.current!.released, isTrue);
    },
  );
}

class _FailedImporter extends LocalMediaImporter {
  @override
  Future<LocalFileSource> importPickedFile(PlatformFile selected) async =>
      throw const FileSystemException('No space left');
}

class _BlockingImporter extends LocalMediaImporter {
  final gate = Completer<LocalFileSource>();
  @override
  Future<LocalFileSource> importPickedFile(PlatformFile selected) =>
      gate.future;
}

final class _Picked extends PlatformFile {
  @override
  String get name => 'new.wav';
  @override
  Uri get uri => Uri.file('C:/cache/new.wav');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() async => null;
  @override
  Future<Uint8List> readAsBytes() => throw UnimplementedError();
  @override
  Stream<Uint8List> readAsByteStream() => throw UnimplementedError();
}

LocalFileSource _source(String id) => LocalFileSource.fromPath(
  id: id,
  displayName: '$id.wav',
  path: 'C:/test/$id.wav',
);

class _Loader implements MediaLoader {
  final List<String> events = <String>[];
  Completer<void>? gate;
  bool failNext = false;
  _Media? current;

  @override
  Future<LoadedMedia> load(MediaSource source) async {
    events.add('load:${source.id}');
    await gate?.future;
    if (failNext) {
      failNext = false;
      throw StateError('Decoder failed');
    }
    return current = _Media(source.id, events);
  }
}

class _Media implements LoadedMedia {
  _Media(this.id, this.events);
  final String id;
  final List<String> events;
  final StreamController<void> _ends = StreamController<void>.broadcast(
    sync: true,
  );
  Completer<void>? releaseGate;
  bool released = false;
  bool failRelease = false;

  @override
  Duration get duration => const Duration(seconds: 30);
  @override
  Duration position = Duration.zero;
  @override
  Stream<void> get endEvents => _ends.stream;
  @override
  Future<void> play() async => events.add('play:$id');
  @override
  Future<void> pause() async => events.add('pause:$id');
  @override
  Future<Duration> seek(Duration target) async => position = target;
  @override
  Future<void> release() async {
    events.add('release:$id');
    if (failRelease) throw StateError('Platform release failed');
    await releaseGate?.future;
    released = true;
    await _ends.close();
  }

  void end() {
    position = duration;
    _ends.add(null);
  }
}
