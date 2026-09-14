import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genz/services/single_connection_proxy.dart';

/// An origin that behaves like the Xtream panel this was diagnosed against:
/// one connection at a time, and a second concurrent request answered with
/// `404 Not Found` rather than a "too many connections" status.
///
/// Deliberately a raw socket server rather than an [HttpServer], because
/// connections have to be counted as they open and close on the wire.
/// Counting at the request level lags behind the socket — the count only
/// falls once a write finally fails — and so reports concurrency that has
/// already ended.
class _Panel {
  _Panel(this._server) {
    _server.listen(_handle, onError: (Object _) {});
  }

  static Future<_Panel> start() async =>
      _Panel(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;

  int _open = 0;

  /// The most connections open at once. The point of the proxy is that this
  /// never exceeds one.
  int peak = 0;

  /// How many requests were refused for exceeding the limit.
  int refused = 0;

  /// Range headers seen, in order.
  final List<String?> ranges = [];

  int get port => _server.port;

  Future<void> close() async {
    await _server.close();
  }

  void _handle(Socket socket) {
    _open++;
    if (_open > peak) peak = _open;

    final head = StringBuffer();
    var answered = false;
    var gone = false;

    socket.listen(
      (data) async {
        if (answered) return;
        head.write(String.fromCharCodes(data));
        if (!head.toString().contains('\r\n\r\n')) return;
        answered = true;
        ranges.add(_rangeIn(head.toString()));

        if (_open > 1) {
          refused++;
          socket.add(
            utf8.encode('HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n'),
          );
          await _quietly(socket.close);
          return;
        }

        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: video/mp4\r\n'
            'Accept-Ranges: bytes\r\n\r\n',
          ),
        );
        // Stream for about a second, like real playback, so the connection is
        // genuinely held while the other requests arrive — then finish, so a
        // reader draining it is never left waiting forever.
        for (var i = 0; i < 600 && !gone; i++) {
          try {
            socket.add(List<int>.filled(512, 7));
            await socket.flush();
          } catch (_) {
            return; // the proxy closed us to free the slot
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await _quietly(socket.close);
      },
      onDone: () {
        gone = true;
        _open--;
      },
      onError: (Object _) {
        gone = true;
        _open--;
      },
      cancelOnError: true,
    );
  }

  static String? _rangeIn(String head) {
    for (final line in head.split('\r\n')) {
      if (line.toLowerCase().startsWith('range:')) {
        return line.substring('range:'.length).trim();
      }
    }
    return null;
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }
}

Future<int> _get(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  try {
    await response.drain<void>().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Expected: the proxy closes a stream to serve a later request, and a
    // stream still running is not worth waiting out.
  }
  return response.statusCode;
}

void main() {
  group('SingleConnectionProxy', () {
    test('declines anything that is not an http(s) stream', () async {
      final proxy = SingleConnectionProxy();
      addTearDown(proxy.stop);

      // Downloaded files are played from disk and must never be proxied.
      expect(await proxy.serve('file:///tmp/episode.mp4', const {}), isNull);
      expect(await proxy.serve('not a url', const {}), isNull);
      expect(proxy.port, 0, reason: 'nothing should be listening');
    });

    test('keeps the original file name so demuxer hints survive', () async {
      final panel = await _Panel.start();
      addTearDown(panel.close);
      final proxy = SingleConnectionProxy();
      addTearDown(proxy.stop);

      final url = await proxy.serve(
        'http://127.0.0.1:${panel.port}/series/user/pass/432621.mp4',
        const {},
      );
      expect(url, isNotNull);
      expect(url, endsWith('/432621.mp4'));
      expect(url, startsWith('http://127.0.0.1:'));
    });

    test('rejects requests that do not carry the secret path', () async {
      final panel = await _Panel.start();
      addTearDown(panel.close);
      final proxy = SingleConnectionProxy();
      addTearDown(proxy.stop);

      await proxy.serve(
        'http://127.0.0.1:${panel.port}/series/user/pass/1.mp4',
        const {},
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      expect(
        await _get(client, 'http://127.0.0.1:${proxy.port}/guessed/1.mp4'),
        HttpStatus.forbidden,
      );
      expect(panel.peak, 0, reason: 'the panel must not have been contacted');
    });

    test(
      'never lets the panel see two connections at once',
      () async {
        final panel = await _Panel.start();
        addTearDown(panel.close);
        final proxy = SingleConnectionProxy(
          releaseDelay: const Duration(milliseconds: 50),
        );
        addTearDown(proxy.stop);

        final url = await proxy.serve(
          'http://127.0.0.1:${panel.port}/series/user/pass/432621.mp4',
          const {},
        );
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        // A stream is playing. Its body is deliberately left unread, so the
        // connection stays open exactly as it does during playback.
        final playing = await (await client.getUrl(Uri.parse(url!))).close();
        expect(playing.statusCode, HttpStatus.ok);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          panel.peak,
          1,
          reason: 'the stream should have reached the panel',
        );

        // Now a seek arrives: a second request while the first is still open,
        // which is the pattern libmpv issues and the panel answers with 404.
        // The proxy must close the first rather than let both through.
        final seek = await (await client.getUrl(Uri.parse(url))).close();
        expect(seek.statusCode, HttpStatus.ok);
        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(panel.peak, 1, reason: 'connections must be serialised');
        expect(panel.refused, 0, reason: 'nothing should hit the limit');
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('passes the Range header through to the panel', () async {
      final panel = await _Panel.start();
      addTearDown(panel.close);
      final proxy = SingleConnectionProxy(
        releaseDelay: const Duration(milliseconds: 10),
      );
      addTearDown(proxy.stop);

      final url = await proxy.serve(
        'http://127.0.0.1:${panel.port}/series/user/pass/1.mp4',
        const {},
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(Uri.parse(url!));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=381567049-');
      final response = await request.close();
      try {
        await response.drain<void>();
      } catch (_) {}

      expect(panel.ranges, contains('bytes=381567049-'));
    });
  });
}
