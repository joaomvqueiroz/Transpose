import 'media_capabilities.dart';

/// Stable source categories defined by the player architecture.
enum MediaSourceType {
  localFile,
  authorizedRemote,
  embeddedVideo;

  String get code => switch (this) {
        MediaSourceType.localFile => 'LOCAL_FILE',
        MediaSourceType.authorizedRemote => 'AUTHORIZED_REMOTE',
        MediaSourceType.embeddedVideo => 'EMBEDDED_VIDEO',
      };
}

/// UI- and SDK-independent description of media that can be loaded later.
///
/// Subclasses describe a source and its capabilities; opening decoders and
/// owning native resources belong to PLAYER-003 and infrastructure adapters.
abstract base class MediaSource {
  MediaSource({
    required this.id,
    required this.type,
    required this.displayName,
    required this.locator,
    required this.capabilities,
    this.durationHint,
  }) {
    _requireNonBlank(id, 'id');
    _requireNonBlank(displayName, 'displayName');
    if (locator.toString().trim().isEmpty) {
      throw ArgumentError('must not be empty', 'locator');
    }
    if (durationHint != null && durationHint!.inMicroseconds <= 0) {
      throw ArgumentError.value(
        durationHint,
        'durationHint',
        'must be greater than zero when provided',
      );
    }
  }

  final String id;
  final MediaSourceType type;
  final String displayName;

  /// Authorized locator consumed by a future platform/media adapter.
  ///
  /// Callers must not log this value; [toString] deliberately redacts it.
  final Uri locator;

  final Duration? durationHint;
  final MediaCapabilities capabilities;

  /// Persistence representation for the local session snapshot.
  String get sourceLocator => locator.toString();

  @override
  String toString() =>
      '$runtimeType(type: ${type.code}, locator: ${locator.scheme}:<redacted>, '
      'capabilities: $capabilities)';
}

/// An authorized file or document-provider item on the current device.
final class LocalFileSource extends MediaSource {
  LocalFileSource({
    required super.id,
    required super.displayName,
    required Uri locator,
    super.durationHint,
  }) : super(
          type: MediaSourceType.localFile,
          locator: _validateLocalLocator(locator),
          capabilities: MediaCapabilities.localFile,
        );

  /// Creates a local source without importing `dart:io` into the domain.
  factory LocalFileSource.fromPath({
    required String id,
    required String displayName,
    required String path,
    Duration? durationHint,
  }) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }

    final bool looksLikeWindowsDrive =
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
    final bool looksLikeWindowsShare = path.startsWith(r'\\');
    if (!path.startsWith('/') &&
        !looksLikeWindowsDrive &&
        !looksLikeWindowsShare) {
      throw ArgumentError('must be an absolute path', 'path');
    }
    final bool looksLikeWindowsPath =
        looksLikeWindowsDrive || looksLikeWindowsShare;
    return LocalFileSource(
      id: id,
      displayName: displayName,
      locator: Uri.file(path, windows: looksLikeWindowsPath),
      durationHint: durationHint,
    );
  }
}

Uri _validateLocalLocator(Uri locator) {
  final String scheme = locator.scheme.toLowerCase();
  if (scheme != 'file' && scheme != 'content') {
    throw ArgumentError(
      'LocalFileSource accepts only file:// or content:// locators',
      'locator',
    );
  }
  if (locator.path.isEmpty) {
    throw ArgumentError('must contain a path', 'locator');
  }
  if (scheme == 'file' && !locator.path.startsWith('/')) {
    throw ArgumentError('file locator must have an absolute path', 'locator');
  }
  if (scheme == 'file' && locator.host.isNotEmpty) {
    throw ArgumentError('file locator must be on this device', 'locator');
  }
  if (scheme == 'content' && !locator.hasAuthority) {
    throw ArgumentError('content locator must name a provider', 'locator');
  }
  if (locator.userInfo.isNotEmpty) {
    throw ArgumentError('must not contain user credentials', 'locator');
  }
  if (locator.hasQuery || locator.hasFragment) {
    throw ArgumentError('must not contain query or fragment', 'locator');
  }
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(Uri.decodeComponent(locator.path))) {
    throw ArgumentError('must not contain control characters', 'locator');
  }
  return locator;
}

void _requireNonBlank(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be blank');
  }
  if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
    throw ArgumentError('must not contain control characters', name);
  }
}
