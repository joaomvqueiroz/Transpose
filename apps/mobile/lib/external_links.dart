import 'package:flutter/services.dart';

const MethodChannel _external = MethodChannel('transpono/external');

/// A link the embedded pages do not show (another site, an email address, a
/// phone number) opens in the phone's own browser or app instead of doing
/// nothing.
bool opensOutside(Uri uri) =>
    const <String>{'http', 'https', 'mailto', 'tel'}.contains(uri.scheme);

/// YouTube's "leave YouTube" page (`/redirect?q=…`): the address it leads to.
Uri? youtubeRedirectTarget(Uri uri) {
  final bool youtube =
      uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com');
  if (!youtube || uri.path != '/redirect') return null;
  final Uri? target = Uri.tryParse(uri.queryParameters['q'] ?? '');
  return target != null && opensOutside(target) ? target : null;
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
