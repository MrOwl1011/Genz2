import 'package:flutter_test/flutter_test.dart';
import 'package:genz/services/stream_url_fallback.dart';

void main() {
  group('xtreamFallbackStreamUrl', () {
    test('the address that failed in the field gets a .ts alternative', () {
      expect(
        xtreamFallbackStreamUrl(
          'http://panel.example/series/123456789012/987654321098/432621.mp4',
        ),
        'http://panel.example/series/123456789012/987654321098/432621.ts',
      );
    });

    test('movies are covered as well as series', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/movie/u/p/839112.mkv'),
        'http://panel.example/movie/u/p/839112.ts',
      );
    });

    test('https and a port are preserved', () {
      expect(
        xtreamFallbackStreamUrl('https://panel.example:8443/series/u/p/1.mp4'),
        'https://panel.example:8443/series/u/p/1.ts',
      );
    });

    test('a panel installed under a path prefix still matches', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/iptv/series/u/p/1.mp4'),
        'http://panel.example/iptv/series/u/p/1.ts',
      );
    });

    test('encoded credentials keep their exact encoding', () {
      expect(
        xtreamFallbackStreamUrl(
          'http://panel.example/series/us%40er/p%26ss%2Fword/1.mp4',
        ),
        'http://panel.example/series/us%40er/p%26ss%2Fword/1.ts',
      );
    });

    test('a query string stays after the new extension', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/movie/u/p/1.mp4?t=1'),
        'http://panel.example/movie/u/p/1.ts?t=1',
      );
    });

    test('an address already ending in .ts has nothing further to try', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/series/u/p/1.ts'),
        isNull,
      );
      expect(
        xtreamFallbackStreamUrl('http://panel.example/series/u/p/1.TS'),
        isNull,
      );
    });

    test('live channels are left alone', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/live/u/p/123.m3u8'),
        isNull,
      );
      expect(xtreamFallbackStreamUrl('http://panel.example/u/p/123'), isNull);
    });

    test('downloaded files are left alone', () {
      expect(
        xtreamFallbackStreamUrl('file:///var/mobile/Downloads/432621.mp4'),
        isNull,
      );
    });

    test('a direct-source address from a CDN is left alone', () {
      expect(
        xtreamFallbackStreamUrl('https://cdn.example.com/video.mp4'),
        isNull,
      );
      expect(
        xtreamFallbackStreamUrl('https://cdn.example.com/a/b/c/video.mp4'),
        isNull,
      );
    });

    test('a file with no extension is left alone', () {
      expect(
        xtreamFallbackStreamUrl('http://panel.example/series/u/p/432621'),
        isNull,
      );
    });

    test('something that is not a URL is left alone', () {
      expect(xtreamFallbackStreamUrl('not a url'), isNull);
      expect(xtreamFallbackStreamUrl(''), isNull);
    });
  });
}
