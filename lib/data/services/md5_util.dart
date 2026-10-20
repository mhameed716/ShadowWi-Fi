// تنفيذ MD5 خالص (RFC 1321) — بلا أي مكتبات خارجية.
// المدخلات تُرمَّز UTF-8 كما يفعل المتصفح في صفحات MikroTik (md5.js).
import 'dart:convert';

class Md5Util {
  const Md5Util._();

  /// بصمة MD5 سداسية عشرية صغيرة لسلسلة نصية.
  static String hash(String input) {
    final List<int> bytes = utf8.encode(input);
    final int bitLen = bytes.length * 8;
    final List<int> msg = <int>[...bytes, 0x80];
    while (msg.length % 64 != 56) {
      msg.add(0);
    }
    for (int i = 0; i < 8; i++) {
      msg.add((bitLen >> (8 * i)) & 0xFF);
    }

    int a0 = 0x67452301;
    int b0 = 0xEFCDAB89;
    int c0 = 0x98BADCFE;
    int d0 = 0x10325476;

    for (int chunk = 0; chunk < msg.length; chunk += 64) {
      final List<int> m = List<int>.filled(16, 0);
      for (int j = 0; j < 16; j++) {
        final int base = chunk + j * 4;
        m[j] = msg[base] |
            (msg[base + 1] << 8) |
            (msg[base + 2] << 16) |
            (msg[base + 3] << 24);
      }
      int a = a0;
      int b = b0;
      int c = c0;
      int d = d0;
      for (int i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ((~d) & 0xFFFFFFFF));
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + m[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl(f, _s[i])) & 0xFFFFFFFF;
      }
      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }

    final StringBuffer hex = StringBuffer();
    for (final int value in <int>[a0, b0, c0, d0]) {
      for (int i = 0; i < 4; i++) {
        hex.write(
            ((value >> (8 * i)) & 0xFF).toRadixString(16).padLeft(2, '0'));
      }
    }
    return hex.toString();
  }

  static int _rotl(int x, int c) => ((x << c) | (x >> (32 - c))) & 0xFFFFFFFF;

  static const List<int> _s = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];
}
