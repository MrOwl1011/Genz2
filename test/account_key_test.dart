import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genz/services/account_key.dart';

/// Mirrors the private _pbkdf2 in account_key.dart so the algorithm itself
/// can be checked against published vectors.
String _pbkdf2Hex(String password, String salt, int iterations, int dkLen) {
  final hmac = Hmac(sha256, utf8.encode(password));
  final saltBytes = utf8.encode(salt);
  final out = <int>[];
  for (var block = 1; out.length < dkLen; block++) {
    var u = hmac.convert(<int>[
      ...saltBytes,
      (block >> 24) & 0xFF,
      (block >> 16) & 0xFF,
      (block >> 8) & 0xFF,
      block & 0xFF,
    ]).bytes;
    final acc = List<int>.from(u);
    for (var r = 1; r < iterations; r++) {
      u = hmac.convert(u).bytes;
      for (var i = 0; i < acc.length; i++) {
        acc[i] ^= u[i];
      }
    }
    out.addAll(acc);
  }
  return out
      .sublist(0, dkLen)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

void main() {
  group('PBKDF2-HMAC-SHA256 matches published vectors', () {
    test('c=1', () {
      expect(
        _pbkdf2Hex('password', 'salt', 1, 32),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });
    test('c=2', () {
      expect(
        _pbkdf2Hex('password', 'salt', 2, 32),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });
    test('c=4096', () {
      expect(
        _pbkdf2Hex('password', 'salt', 4096, 32),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
    test('multi-block output (dkLen > 32)', () {
      expect(
        _pbkdf2Hex('passwordPASSWORDpassword',
            'saltSALTsaltSALTsaltSALTsaltSALTsalt', 4096, 40),
        '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
      );
    });
  });

  group('AccountKey.derive', () {
    test('produces 64 lowercase hex characters', () async {
      final key = await AccountKey.derive(username: 'user', password: 'pw');
      expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
    });

    test('is stable for the same credentials', () async {
      final a = await AccountKey.derive(username: 'user', password: 'pw');
      final b = await AccountKey.derive(username: 'user', password: 'pw');
      expect(a, b);
    });

    test('username is case-insensitive, password is not', () async {
      final lower = await AccountKey.derive(username: 'user', password: 'pw');
      final upperUser = await AccountKey.derive(username: 'USER', password: 'pw');
      final upperPass = await AccountKey.derive(username: 'user', password: 'PW');
      expect(upperUser, lower, reason: 'username should fold case');
      expect(upperPass, isNot(lower), reason: 'password must stay case-sensitive');
    });

    test('separator prevents concatenation collisions', () async {
      final a = await AccountKey.derive(username: 'ab', password: 'c');
      final b = await AccountKey.derive(username: 'a', password: 'bc');
      expect(a, isNot(b));
    });

    test('surrounding whitespace is ignored', () async {
      final plain = await AccountKey.derive(username: 'user', password: 'pw');
      final padded = await AccountKey.derive(username: '  user ', password: ' pw  ');
      expect(padded, plain);
    });
  });
}
