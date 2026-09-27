import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 密码学与解锁工具
class Security {
  Security._();

  static final Random _rng = Random.secure();

  /// 生成随机盐（hex）
  static String genSalt() {
    final bytes = Uint8List.fromList(
        List.generate(16, (_) => _rng.nextInt(256)));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 口令 == sha256(salt + '::' + username + '::' + password)
  static String hashPassword(String salt, String username, String password) {
    return sha256.convert(utf8.encode('$salt::$username::$password')).toString();
  }

  /// 随机 32 字节密钥字符串（用于手势/生物解锁二次校验）
  static String genKey() {
    final bytes = Uint8List.fromList(
        List.generate(32, (_) => _rng.nextInt(256)));
    return base64Url.encode(bytes);
  }

  /// 简单混淆：异或，用于把解锁密钥存储（非强加密，仅供本地防护）
  static String obfuscate(String key, String pass) {
    final a = utf8.encode(key);
    final b = utf8.encode(pass);
    final out = List<int>.generate(a.length, (i) => a[i] ^ b[i % b.length]);
    return base64Url.encode(out);
  }

  static String deobfuscate(String encoded, String pass) {
    final a = base64Url.decode(encoded);
    final b = utf8.encode(pass);
    final out = List<int>.generate(a.length, (i) => a[i] ^ b[i % b.length]);
    return utf8.decode(out);
  }
}

/// 手势矩阵编码：9 个点 -> 0..8，路径转成字符串（用于展示/校验）
class GestureCode {
  GestureCode._();

  static const int n = 3;

  static String encode(List<int> seq) => seq.map((e) => e.toString()).join();

  static List<int> decode(String code) =>
      code.split('').map(int.parse).toList();

  /// 校验手势是否合法：相邻点之间若有未经过的三点共线点需自动经过
  static bool isValid(List<int> seq) {
    if (seq.isEmpty || seq.length < 4) return false;
    final seen = <int>{};
    for (var i = 0; i < seq.length; i++) {
      final p = seq[i];
      if (p < 0 || p > 8 || seen.contains(p)) return false;
      seen.add(p);
      if (i > 0) {
        final mid = between(seq[i - 1], p);
        if (mid != null && !seen.contains(mid)) {
          return false; // 忽略中间点的覆盖处理，由 UI 层自动补点
        }
      }
    }
    return true;
  }

  /// 若 a-b 之间隔着一点，则返回该中间点编号，否则 null
  static int? between(int a, int b) {
    final ar = a ~/ n, ac = a % n;
    final br = b ~/ n, bc = b % n;
    // 同行/列/对角线
    final mr = (ar + br) ~/ 2, mc = (ac + bc) ~/ 2;
    if ((ar + br).isEven && (ac + bc).isEven && ar != br && ac != bc) {
      // 对角线中点有效（1,1)
      if (mr * n + mc == 4) return 4;
    }
    if (ar == br && (ac + bc).isEven && (ac - bc).abs() == 2) {
      final ri = mr * n + (ac + bc) ~/ 2;
      if (ri != a && ri != b) return ri;
    }
    if (ac == bc && (ar + br).isEven && (ar - br).abs() == 2) {
      final ri = ((ar + br) ~/ 2) * n + ac;
      if (ri != a && ri != b) return ri;
    }
    return null;
  }
}