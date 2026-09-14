/// A second address for an Xtream movie or episode whose first address would
/// not open — the same file under the `.ts` extension — or null when there is
/// no sensible alternative.
///
/// Why this exists: Xtream panels commonly sit behind Cloudflare, which caches
/// responses for file extensions it treats as static, `.mp4` among them. When
/// the panel has any brief failure answering a `.mp4` request, Cloudflare
/// stores that 404 and serves it to every request for the same address for
/// several minutes. The panel itself is fine, but the episode "fails to open"
/// until the cached error expires. Addresses ending in `.ts` are not cached
/// that way, and panels serve the same file whatever extension is asked for —
/// observed on a live panel, where `.mp4` answered with a cached 404 while
/// `.ts`, `.mkv` and `.avi` all redirected to the identical stream.
///
/// `.ts` rather than another container because it is the output format Xtream
/// accounts are near-universally allowed; the account this was diagnosed on
/// allowed only `ts` and `m3u8`.
///
/// Only a fallback, never the first choice. A panel that insists on the
/// extension from its own catalogue keeps working exactly as before, because
/// this is used only after that address has already failed.
///
/// Returns null for anything that is not an Xtream movie or series address:
/// live channels (already streamed as `.ts` or `.m3u8`), downloaded files,
/// a provider's direct-source URLs, and addresses already ending in `.ts`.
String? xtreamFallbackStreamUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }

  // Xtream VOD and series addresses end in <kind>/<user>/<pass>/<id>.<ext>.
  // Counting from the end tolerates a panel installed under a path prefix.
  final segments = uri.pathSegments;
  if (segments.length < 4) {
    return null;
  }
  final kind = segments[segments.length - 4];
  if (kind != 'movie' && kind != 'series') {
    return null;
  }

  // Edited as text rather than rebuilt through Uri, so the username and
  // password in the path keep exactly the encoding the panel accepted. Uri
  // would normalise it, and some panels reject the result.
  final cut = url.indexOf(RegExp(r'[?#]'));
  final path = cut == -1 ? url : url.substring(0, cut);
  final rest = cut == -1 ? '' : url.substring(cut);

  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash + 1) {
    return null; // The file has no extension to swap.
  }
  if (path.substring(dot + 1).toLowerCase() == _fallbackExtension) {
    return null; // Already the fallback; nothing further to try.
  }

  return '${path.substring(0, dot)}.$_fallbackExtension$rest';
}

const String _fallbackExtension = 'ts';
