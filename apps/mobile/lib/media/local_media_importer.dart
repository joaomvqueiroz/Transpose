import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:player_core/player_core.dart';

/// Keeps explicitly selected local media outside the operating system's cache.
///
/// A picker path is not a durable permission: on Android/iOS it normally points
/// at the picker's temporary copy. Stream it into app support before publishing
/// a new locator. Never move/delete the user's original and never fetch URLs.
class LocalMediaImporter {
  LocalMediaImporter({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<Directory> _mediaDirectory() async {
    final support = await _supportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}transpono_media')
        .create(recursive: true);
  }

  Future<LocalFileSource> importPickedFile(PlatformFile selected) async {
    // Current native file_picker implementations provide readable cache files.
    // Reject remote/unsupported locators instead of accidentally downloading.
    if (selected.uri.scheme != 'file' || selected.path == null) {
      throw const FileSystemException('Escolha um ficheiro local acessível.');
    }
    final extension =
        RegExp(r'\.[a-zA-Z0-9]{1,10}$')
            .firstMatch(selected.name)
            ?.group(0)
            ?.toLowerCase() ??
        '';
    final root = await _mediaDirectory();
    final directory = await root.createTemp('import-');
    final destination = File(
      '${directory.path}${Platform.pathSeparator}media$extension',
    );
    try {
      await _writeAtomically(destination, selected.readAsByteStream());
      return LocalFileSource.fromPath(
        id: 'local-${directory.uri.pathSegments.where((p) => p.isNotEmpty).last}',
        displayName: selected.name,
        path: destination.path,
      );
    } on Object {
      // This directory was minted by this call; remove only our empty directory.
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
      rethrow;
    }
  }

  Future<LocalFileSource> importSample(ByteData data) async {
    final root = await _mediaDirectory();
    final sample = File(
      '${root.path}${Platform.pathSeparator}qa-tone-440-v1.wav',
    );
    if (!await sample.exists() || await sample.length() == 0) {
      await _writeAtomically(
        sample,
        Stream.value(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    }
    return LocalFileSource.fromPath(
      id: 'qa-tone',
      displayName: 'Amostra de áudio · 440 Hz',
      path: sample.path,
    );
  }

  Future<void> _writeAtomically(
    File destination,
    Stream<List<int>> chunks,
  ) async {
    final working = await destination.parent.createTemp('writing-');
    final partial = File('${working.path}${Platform.pathSeparator}media.part');
    RandomAccessFile? output;
    try {
      output = await partial.open(mode: FileMode.writeOnly);
      var length = 0;
      await for (final chunk in chunks) {
        await output.writeFrom(chunk);
        length += chunk.length;
      }
      if (length == 0) {
        throw const FileSystemException('O ficheiro está vazio.');
      }
      await output.flush();
      await output.close();
      output = null;
      await partial.rename(destination.path);
    } finally {
      await output?.close();
      if (await partial.exists()) await partial.delete();
      // Only the unique staging directory created above is ever removed.
      if (await working.exists()) await working.delete();
    }
  }
}
