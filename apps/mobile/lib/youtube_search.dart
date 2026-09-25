/// Opens the mobile results page inside Transpono's embedded browser.
Uri youtubeSearchUri(String query) {
  final String trimmed = query.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(
      query,
      'query',
      'A pesquisa não pode estar vazia.',
    );
  }
  return Uri.https('m.youtube.com', '/results', <String, String>{
    'search_query': trimmed,
  });
}

/// Main-frame destinations allowed in the embedded browser. Subresources are
/// loaded normally by WebView, including YouTube's media and image CDNs.
bool isYouTubeBrowserUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'youtube.com' ||
        uri.host.endsWith('.youtube.com') ||
        uri.host == 'youtu.be' ||
        uri.host == 'consent.google.com' ||
        uri.host == 'accounts.google.com');

/// Universal links must stay inside this WebView instead of starting an app.
Uri? embeddedYouTubeUri(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (isYouTubeBrowserUri(uri)) return uri;
  if (uri.scheme == 'intent') {
    final String base = value.split('#Intent;').first;
    final Uri? https = Uri.tryParse(base.replaceFirst('intent:', 'https:'));
    if (https != null && isYouTubeBrowserUri(https)) return https;
  }
  if (uri.scheme == 'vnd.youtube') {
    final String id = uri.host.isNotEmpty ? uri.host : uri.path;
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
      return Uri.https('m.youtube.com', '/watch', <String, String>{'v': id});
    }
  }
  return null;
}
