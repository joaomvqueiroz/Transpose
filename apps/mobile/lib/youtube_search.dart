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

/// Google sign-in pages. Signing in to YouTube / YouTube Music hops between
/// accounts.google.com and country sites such as www.google.pt
/// (/accounts/SetSID) to set the session; blocking those hops is what made
/// sign-in fail inside Transpono.
bool isGoogleSignInUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  final String host = uri.host;
  final bool google = RegExp(
    r'^(?:[a-z0-9-]+\.)?google\.(?:com|[a-z]{2}|com?\.[a-z]{2})$',
  ).hasMatch(host);
  if (!google) return false;
  return host.startsWith('accounts.') ||
      host.startsWith('myaccount.') ||
      uri.path.startsWith('/accounts') ||
      uri.path.startsWith('/signin');
}

/// SoundCloud pages, opened by the SoundCloud choice in the same studio. Its
/// covers and user uploads stream without DRM, so the page bridge applies;
/// official label tracks are DRM-protected and cannot be processed.
bool isSoundCloudBrowserUri(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'soundcloud.com' || uri.host.endsWith('.soundcloud.com'));

/// SoundCloud's mobile search results for [query].
Uri soundCloudSearchUri(String query) => Uri.https(
  'm.soundcloud.com',
  '/search',
  <String, String>{'q': query.trim()},
);

/// Universal links must stay inside this WebView instead of starting an app.
Uri? embeddedYouTubeUri(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (isYouTubeBrowserUri(uri) ||
      isSoundCloudBrowserUri(uri) ||
      isGoogleSignInUri(uri)) {
    return uri;
  }
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
