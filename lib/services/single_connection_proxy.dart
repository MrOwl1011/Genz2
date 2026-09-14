import 'dart:async';
import 'dart:io';
import 'dart:math';

/// A loopback HTTP proxy that holds at most one upstream connection at a time.
///
/// Xtream accounts are commonly capped at a single concurrent connection
/// (`max_connections: 1`). libmpv does not respect that: to seek, it opens a
/// second connection at the new byte offset — and another to read the MP4
/// index — while its main streaming connection is still open. The panel
/// refuses the extra connection and, as observed on a live panel, answers it
/// with `404 Not Found` rather than a "too many connections" status. libmpv
/// retries about ten times, gives up ("treating it as fatal error") and parks
/// at end-of-file, so dragging the seek bar from 30:00 to 31:00 drops the
/// viewer at the end of the episode instead.
///
/// Measured against that panel, every 404 arrived while a second request was
/// in flight and every request made alone succeeded. No libmpv option avoids
/// the second connection: `cache=no`, HTTP keep-alive (`multiple_requests=1`),
/// a 300-second readahead buffer and reopening the file at the seek target
/// were each tried and behaved identically, because the behaviour lives in
/// ffmpeg's seek path rather than in mpv's cache. Nor is it a seekability
/// problem — mpv reports `seekable=1`, and the server serves byte ranges
/// correctly when asked one at a time.
///
/// So the connections are serialised here instead. mpv is pointed at this
/// proxy on 127.0.0.1, and before opening a new upstream connection the proxy
/// closes the one it already holds, so the panel never sees two at once. With
/// this in place the same seek lands correctly and playback continues, with no
/// 404s at all.
///
/// Desktop only: used by `MediaKitBackend`, which is constructed solely for
/// Windows, macOS and Linux. The phone's VLCKit and ExoPlayer backends open
/// one connection at a time already and are untouched.
///
/// Note for macOS: binding a local listener requires the
/// `com.apple.security.network.server` entitlement under the App Sandbox.
class SingleConnectionProxy {
  SingleConnectionProxy({
    this.releaseDelay = const Duration(milliseconds: 300),
  });

  /// How long to wait after closing the previous upstream connection before
  /// opening the next. A panel frees the slot a moment after the socket
  /// closes, and reconnecting instantly can still be counted as a second
  /// connection.
  final Duration releaseDelay;

  HttpServer? _server;
  HttpClient? _client;

  /// Random path prefix every request must carry. The listener is bound to
  /// loopback, but the upstream URL embeds the account's credentials, so this
  /// stops another local process from using it as an open proxy by guessing
  /// the port.
  String? _secret;

  Uri? _target;
  Map<String, String> _headers = const {};

  _Upstream? _active;

  /// Serialises the abort-then-open step. Streaming happens outside it, so a
  /// long-lived stream never blocks the next request from taking over.
  Future<void> _gate = Future<void>.value();

  /// The port being listened on, or 0 when not running.
  int get port => _server?.port ?? 0;

  /// Starts proxying [target] and returns the loopback URL to hand to the
  /// player engine.
  ///
  /// Returns null when proxying does not apply or is unavailable — a local
  /// file, an unparseable URL, or a listener that could not be bound (a
  /// sandbox without the server entitlement, for instance). The caller should
  /// then use the original URL and accept the old behaviour rather than fail
  /// to play at all.
  Future<String?> serve(String target, Map<String, String> headers) async {
    final uri = Uri.tryParse(target);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    _target = uri;
    _headers = Map<String, String>.unmodifiable(headers);

    if (_server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      } catch (_) {
        _server = null;
        return null;
      }
      _secret = _newToken();
      _client = HttpClient();
      _server!.listen(_handle, onError: (Object _) {});
    }

    // Keep the original file name on the end: engines take demuxer hints from
    // the extension, so the proxied URL should look like the real one.
    final name = uri.pathSegments.isEmpty ? 'stream' : uri.pathSegments.last;
    return 'http://${InternetAddress.loopbackIPv4.address}:${_server!.port}'
        '/$_secret/$name';
  }

  /// Closes the upstream connection and stops listening.
  Future<void> stop() async {
    await _abort();
    _target = null;
    _secret = null;
    final client = _client;
    _client = null;
    try {
      client?.close(force: true);
    } catch (_) {}
    final server = _server;
    _server = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final secret = _secret;
    if (secret == null || !request.uri.path.startsWith('/$secret/')) {
      response.statusCode = HttpStatus.forbidden;
      await _close(response);
      return;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    _Upstream? active;
    try {
      active = await _exclusively(() => _acquire(range, request, response));
    } catch (_) {
      active = null;
    }
    if (active == null) {
      response.statusCode = HttpStatus.badGateway;
      await _close(response);
      return;
    }

    response.statusCode = active.response.statusCode;
    for (final header in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      'content-range',
      'accept-ranges',
    ]) {
      final value = active.response.headers.value(header);
      if (value != null) {
        response.headers.set(header, value);
      }
    }

    // Status line and headers are out; let the body flow.
    active.subscription.resume();
    await active.done.future;
    if (identical(_active, active)) {
      _active = null;
    }
    await _close(response);
  }

  /// Closes the connection currently held, waits for the panel to free the
  /// slot, then opens the new one.
  ///
  /// Runs entirely inside [_exclusively] and registers the new connection in
  /// [_active] *before* the gate is released. Registering it after the gate
  /// releases leaves a window where the next request runs [_abort] while this
  /// one is not yet recorded: nothing is closed, and two connections reach the
  /// panel. Real playback rarely hits that window, because a seek arrives
  /// seconds after the stream starts — overlapping requests hit it reliably.
  Future<_Upstream?> _acquire(
    String? range,
    HttpRequest incoming,
    HttpResponse out,
  ) async {
    await _abort();
    if (releaseDelay > Duration.zero) {
      await Future<void>.delayed(releaseDelay);
    }
    final client = _client;
    final target = _target;
    if (client == null || target == null) {
      return null;
    }
    final request = await client.getUrl(target);
    // Redirects are followed per request, so a panel that hands out a session
    // token in the redirect issues a fresh one each time.
    request.followRedirects = true;
    request.maxRedirects = 5;
    _headers.forEach(request.headers.set);
    final userAgent = incoming.headers.value(HttpHeaders.userAgentHeader);
    if (userAgent != null) {
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    if (range != null) {
      request.headers.set(HttpHeaders.rangeHeader, range);
    }
    final upstream = await request.close();

    final done = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    subscription = upstream.listen(
      (chunk) {
        try {
          out.add(chunk);
          // Pause until the chunk has actually gone out, so a fast upstream
          // cannot be buffered into memory faster than the engine reads it.
          subscription.pause(out.flush().catchError((Object _) {}));
        } catch (_) {
          // The engine hung up (it does this routinely — after a seek it
          // abandons the old stream); stop pulling from upstream.
          subscription.cancel();
          if (!done.isCompleted) done.complete();
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    // Held until the caller has written the status line and headers.
    subscription.pause();

    final active = _Upstream(subscription, done, upstream);
    _active = active;
    return active;
  }

  Future<void> _abort() async {
    final active = _active;
    _active = null;
    if (active == null) return;
    try {
      await active.subscription.cancel();
    } catch (_) {}
    if (!active.done.isCompleted) {
      active.done.complete();
    }
  }

  Future<T> _exclusively<T>(Future<T> Function() body) {
    final previous = _gate;
    final release = Completer<void>();
    _gate = release.future;
    return previous.then((_) async {
      try {
        return await body();
      } finally {
        release.complete();
      }
    });
  }

  static Future<void> _close(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {}
  }

  static String _newToken() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

class _Upstream {
  _Upstream(this.subscription, this.done, this.response);

  final StreamSubscription<List<int>> subscription;
  final Completer<void> done;
  final HttpClientResponse response;
}
