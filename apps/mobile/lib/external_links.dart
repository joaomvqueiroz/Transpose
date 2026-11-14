import 'package:flutter/services.dart';

const MethodChannel _external = MethodChannel('transpono/external');

/// A link the embedded pages do not show (another site, an email address, a
/// phone number) opens in the phone's own browser or app instead of doing
/// nothing.
bool opensOutside(Uri uri) {
  if (const <String>{'mailto', 'tel'}.contains(uri.scheme)) return true;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final String host = uri.host.toLowerCase();
  bool under(String domain) => host == domain || host.endsWith('.$domain');
  // "Open in the app" links (Spotify, SoundCloud, YouTube…) would start that
  // app and take the music away from Transpono.
  if (under('app.link') ||
      under('page.link') ||
      under('app.goo.gl') ||
      under('spotify.link') ||
      under('spotify.com') ||
      under('soundcloud.com') ||
      under('youtube.com') ||
      under('youtu.be')) {
    return false;
  }
  // Google's own pages (bot check, sign-in steps) and ad click-throughs are
  // not links the user chose to visit.
  if (RegExp(r'(^|\.)google\.[a-z.]+$').hasMatch(host) ||
      under('googleadservices.com') ||
      under('doubleclick.net') ||
      under('googlesyndication.com')) {
    return false;
  }
  return true;
}

/// YouTube's "leave YouTube" page (`/redirect?q=…`): the address it leads to.
Uri? youtubeRedirectTarget(Uri uri) {
  final bool youtube =
      uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com');
  if (!youtube || uri.path != '/redirect') return null;
  final Uri? target = Uri.tryParse(uri.queryParameters['q'] ?? '');
  if (target == null) return null;
  // A link to YouTube itself goes back into the app's page (see
  // [youtubeInAppTarget]); only other sites open outside.
  if (youtubeInAppTarget(target) != null) return target;
  return opensOutside(target) ? target : null;
}

/// A YouTube address to show inside the app: http is upgraded to https.
Uri? youtubeInAppTarget(Uri uri) {
  final String host = uri.host.toLowerCase();
  final bool youtube =
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtu.be';
  if (!youtube || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.scheme == 'https' ? uri : uri.replace(scheme: 'https');
}

String? _lastOpened;
DateTime _lastOpenedAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Opens [uri] outside the app. False where the platform has no handler
/// (the link then stays blocked, as before).
Future<bool> openOutside(Uri uri) async {
  if (!opensOutside(uri)) return false;
  // A page may ask for the same link several times in a row.
  final DateTime now = DateTime.now();
  if (_lastOpened == uri.toString() &&
      now.difference(_lastOpenedAt) < const Duration(seconds: 2)) {
    return true;
  }
  _lastOpened = uri.toString();
  _lastOpenedAt = now;
  try {
    return await _external.invokeMethod<bool>('open', <String, String>{
          'url': uri.toString(),
        }) ??
        false;
  } on Object {
    return false;
  }
}
