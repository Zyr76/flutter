import 'dart:convert';

import 'package:http/http.dart' as http;

/// 位置服务：通过 IP 识别所在城市，返回「省-市-区」格式的位置文本。
class Locator {
  Locator._();

  static const _ipApi = 'https://v.api.aa1.cn/api/chinaip/';

  /// 调用 IP 定位接口，返回形如“浙江-湖州-吴兴”的地点文本；失败返回 null。
  ///
  /// 接口文档示例（小写字段）：
  /// {"status":true,"code":0,"msg":"ok","data":{"ip":"...","country":"中国",
  ///  "province":"浙江","city":"湖州","district":"吴兴","isp":"联通"}}
  /// 但线上真实返回可能是大写字段 / 不同 code，因此按下标优先解析省/市/区。
  static Future<String?> ipLocation() async {
    try {
      final resp = await http
          .get(Uri.parse(_ipApi))
          .timeout(const Duration(seconds: 8));
      // 注意：该接口即使成功也常返回 HTTP 500，但 body 是正常 JSON，因此不按
      // HTTP 状态码判断，而以 body 内的 code/status 作为成功依据。
      if (resp.bodyBytes.isEmpty) return null;
      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      // 成功判定：status 为 true，或 code ∈ {0, 200}
      final ok = body['status'] == true || [0, 200].contains(body['code']);
      if (!ok) return null;
      final data = body['data'];
      if (data is! Map<String, dynamic>) return null;

      String pick(List<String> keys) {
        for (final k in keys) {
          final raw = data[k];
          if (raw != null) {
            final v = _clean(raw);
            if (v.isNotEmpty) return v;
          }
        }
        return '';
      }

      // 兼容大写(Country/Province/City/District)与小写(country/province/city/district)
      final country = pick(const ['Country', 'country']);
      final province = pick(const ['Province', 'province']);
      var city = pick(const ['City', 'city']);
      final district = pick(const ['District', 'district']);

      // 直辖市：Province 即为城市，需去掉重复的“市”，City 等同省
      if (province.isNotEmpty &&
          (province.endsWith('市') || province.endsWith('省')) &&
          city == province) {
        city = '';
      }
      // 若只有国家没有省，则无法形成“省-市-区”，返回 null
      if (province.isEmpty && city.isEmpty) return null;

      final parts = <String>[province.isEmpty ? country : province];
      if (city.isNotEmpty && city != parts.last) parts.add(city);
      if (district.isNotEmpty && district != parts.last) parts.add(district);
      return parts.join('-');
    } catch (_) {
      return null;
    }
  }

  static String _clean(dynamic v) =>
      (v is String ? v.clean() : (v?.toString().clean() ?? ''));
}

extension on String {
  String clean() => replaceAll(RegExp(r'\s+'), '').trim();
}