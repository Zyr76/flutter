import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// 指纹 / 生物识别。
///
/// 采用 local_auth 推荐用法：始终使用真实生物特征（biometricOnly），配合
/// useErrorDialogs 显示系统级错误；失败原因通过 `verify` 的返回值区分，
/// 便于界面给出准确提示（未录入 / 不可用 / 被锁定 / 已取消）。
class BioAuth {
  BioAuth._();
  static final LocalAuthentication _la = LocalAuthentication();

  /// 设备是否支持生物识别
  static Future<bool> supported() async {
    try {
      return await _la.canCheckBiometrics || await _la.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// 设备是否已录入生物特征（指纹/人脸条目数 > 0）
  static Future<bool> hasEnrolled() async {
    try {
      final list = await _la.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 已录入的生物识别类型掩码：0=无 1=指纹 2=人脸 3=两者都有。
  static Future<int> availableTypes() async {
    var mask = 0;
    try {
      final list = await _la.getAvailableBiometrics();
      for (final b in list) {
        switch (b) {
          case BiometricType.fingerprint:
            mask |= 1;
          case BiometricType.face:
            mask |= 2;
          case BiometricType.iris:
            mask |= 2;
          case BiometricType.strong:
          case BiometricType.weak:
            // strong/weak 是 Android 的通用生物特征等级（可能对应人脸/指纹/虹膜）。
            // local_auth 无法细分具体类型时，同时视为“指纹+人脸”都可用，
            // 让解锁页既能刷脸也能指纹，避免只有指纹没有人脸的问题。
            mask |= 3;
        }
      }
    } catch (_) {}
    return mask;
  }

  /// 是否已录入指纹
  static Future<bool> fingerprintAvailable() async =>
      (await availableTypes() & 1) != 0;

  /// 验证生物特征。
  /// 成功返回 null；失败返回一段可直接展示给用户的提示文字。
  static Future<String?> verify(String prompt, {bool setup = false}) async {
    try {
      if (!await _la.isDeviceSupported()) return '当前设备不支持指纹 / 人脸识别';
      final enabled = (await _la.getAvailableBiometrics()).isNotEmpty;
      if (!enabled) return '您的设备尚未录入指纹或面容，请先在系统设置中添加';
      final ok = await _la.authenticate(
        localizedReason: prompt,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true, // 系统自带错误弹窗（锁定等）
        ),
      );
      if (ok) return null;
      return setup ? '验证失败或已取消，请重试' : '验证失败或已取消';
    } catch (e) {
      if (e is PlatformException) {
        switch (e.code) {
          case 'NotEnrolled':
            return '您的设备尚未录入指纹或面容，请先在系统设置中添加';
          case 'NotAvailable':
            return '生物识别当前不可用';
          case 'LockedOut':
          case 'PermanentlyLockedOut':
            return '指纹尝试次数过多已被锁定，请稍后再试或使用账号密码登录';
          default:
            return '验证失败或已取消';
        }
      }
      return '验证失败或已取消';
    }
  }
}