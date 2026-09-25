import 'package:player_core/player_core.dart';
import 'package:test/test.dart';

void main() {
  group('MediaCapabilities', () {
    test('derives generic audio processing from granular capabilities', () {
      final MediaCapabilities pitchOnly = MediaCapabilities(
        canPitchShift: true,
      );
      final MediaCapabilities stretchOnly = MediaCapabilities(
        canTimeStretch: true,
      );

      expect(MediaCapabilities.none.canProcessAudio, isFalse);
      expect(pitchOnly.canProcessAudio, isTrue);
      expect(stretchOnly.canProcessAudio, isTrue);
    });

    test('provides typed capability lookup and value equality', () {
      final MediaCapabilities first = MediaCapabilities(
        canSeek: true,
        canPitchShift: true,
      );
      final MediaCapabilities second = MediaCapabilities(
        canSeek: true,
        canPitchShift: true,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.supports(MediaCapability.seek), isTrue);
      expect(first.supports(MediaCapability.pitchShift), isTrue);
      expect(first.supports(MediaCapability.timeStretch), isFalse);
    });

    test('rejects precise looping without seeking', () {
      expect(
        () => MediaCapabilities(canLoopPrecisely: true),
        throwsArgumentError,
      );
    });
  });

  group('LocalFileSource', () {
    test('preserves the typed source contract', () {
      final Uri locator = Uri.file('/music/practice.wav');
      final LocalFileSource source = LocalFileSource(
        id: 'track-1',
        displayName: 'Practice take',
        locator: locator,
        durationHint: const Duration(minutes: 3),
      );

      expect(source.id, 'track-1');
      expect(source.type, MediaSourceType.localFile);
      expect(source.type.code, 'LOCAL_FILE');
      expect(source.displayName, 'Practice take');
      expect(source.locator, locator);
      expect(source.sourceLocator, locator.toString());
      expect(source.durationHint, const Duration(minutes: 3));
    });

    test('declares local pitch, time-stretch, seek, background and loop', () {
      final LocalFileSource source = LocalFileSource(
        id: 'track-1',
        displayName: 'Practice take',
        locator: Uri.file('/music/practice.wav'),
      );

      expect(source.capabilities.canSeek, isTrue);
      expect(source.capabilities.canBackgroundPlay, isTrue);
      expect(source.capabilities.canPitchShift, isTrue);
      expect(source.capabilities.canTimeStretch, isTrue);
      expect(source.capabilities.canProcessAudio, isTrue);
      expect(source.capabilities.canLoopPrecisely, isTrue);
      expect(source.capabilities.canCache, isFalse);
      expect(source.capabilities.canExport, isFalse);
    });

    test('creates a file URI from a Windows path', () {
      final LocalFileSource source = LocalFileSource.fromPath(
        id: 'track-1',
        displayName: 'Song',
        path: r'C:\Music\song.wav',
      );

      expect(source.locator.scheme, 'file');
      expect(source.locator.path, '/C:/Music/song.wav');
    });

    test('accepts an authorized Android content URI', () {
      final Uri locator = Uri.parse(
        'content://media/external/audio/media/42',
      );
      final LocalFileSource source = LocalFileSource(
        id: 'track-42',
        displayName: 'Imported song',
        locator: locator,
      );

      expect(source.locator, locator);
      expect(source.type, MediaSourceType.localFile);
    });

    test('rejects blank identifiers and display names', () {
      expect(
        () => LocalFileSource(
          id: '  ',
          displayName: 'Song',
          locator: Uri.file('/music/song.wav'),
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: '\t',
          locator: Uri.file('/music/song.wav'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects control characters in identifiers and display names', () {
      expect(
        () => LocalFileSource(
          id: 'track\u0000-id',
          displayName: 'Song',
          locator: Uri.file('/music/song.wav'),
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song\nName',
          locator: Uri.file('/music/song.wav'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects encoded control characters in a locator', () {
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song',
          locator: Uri.parse('file:///music/%00song.wav'),
        ),
        throwsArgumentError,
      );
    });

    test('rejects empty paths and non-positive duration hints', () {
      expect(
        () => LocalFileSource.fromPath(
          id: 'track-1',
          displayName: 'Song',
          path: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song',
          locator: Uri.file('/music/song.wav'),
          durationHint: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song',
          locator: Uri.file('/music/song.wav'),
          durationHint: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects remote and credential-bearing locators', () {
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Remote song',
          locator: Uri.parse('https://example.com/song.wav'),
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Unsafe song',
          locator: Uri.parse('content://user:secret@provider/document/42'),
        ),
        throwsArgumentError,
      );
    });

    test('requires an absolute file path and content provider', () {
      expect(
        () => LocalFileSource.fromPath(
          id: 'track-1',
          displayName: 'Song',
          path: 'relative/song.wav',
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song',
          locator: Uri.parse('content:/document/42'),
        ),
        throwsArgumentError,
      );
      expect(
        () => LocalFileSource(
          id: 'track-1',
          displayName: 'Song',
          locator: Uri.parse('file://remote-host/music/song.wav'),
        ),
        throwsArgumentError,
      );
    });

    test('redacts the locator and user-facing metadata from diagnostics', () {
      final LocalFileSource source = LocalFileSource(
        id: 'private-id',
        displayName: 'Private rehearsal',
        locator: Uri.parse('content://provider/private/secret-song.wav'),
      );

      final String diagnostic = source.toString();
      expect(diagnostic, contains('LOCAL_FILE'));
      expect(diagnostic, contains('content:<redacted>'));
      expect(diagnostic, isNot(contains('private-id')));
      expect(diagnostic, isNot(contains('Private rehearsal')));
      expect(diagnostic, isNot(contains('secret-song.wav')));
      expect(diagnostic, isNot(contains('token')));
      expect(diagnostic, isNot(contains('secret')));
    });

    test('rejects query and fragment without leaking their values', () {
      for (final String raw in <String>[
        'content://provider/document/42?token=private-value',
        'file:///music/song.wav#private-value',
      ]) {
        expect(
          () => LocalFileSource(
            id: 'track-1',
            displayName: 'Song',
            locator: Uri.parse(raw),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError error) => error.toString(),
              'sanitized message',
              isNot(contains('private-value')),
            ),
          ),
        );
      }
    });
  });
}
