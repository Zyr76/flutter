import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../storage.dart';

class Picked {
  final String path;
  final String name;
  final int size;
  Picked({required this.path, required this.name, required this.size});
}

/// 媒体/文件选择
class Picker {
  Picker._();
  static final ImagePicker _ip = ImagePicker();

  /// 多选图片，返回绝对路径列表
  static Future<List<String>> images() async {
    final rs = await _ip.pickMultiImage(limit: 9);
    return rs.map((e) => e.path).toList();
  }

  static Future<String?> image() async {
    final r = await _ip.pickImage(source: ImageSource.gallery);
    return r?.path;
  }

  static Future<String?> cameraImage() async {
    final r = await _ip.pickImage(source: ImageSource.camera);
    return r?.path;
  }

  static Future<String?> video() async {
    final r = await _ip.pickVideo(source: ImageSource.gallery);
    return r?.path;
  }

  /// 任意格式单文件
  static Future<Picked?> file() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    return Picked(
        path: f.path ?? '', name: f.name, size: f.size ?? 0);
  }

  /// 任意格式多文件
  static Future<List<Picked>> files() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return [];
    return r.files
        .map((f) =>
            Picked(path: f.path ?? '', name: f.name, size: f.size ?? 0))
        .where((e) => e.path.isNotEmpty)
        .toList();
  }

  /// 把选择的临时文件导入到私有目录的指定子目录，返回导入后的绝对路径
  static Future<String> importTo(String src, String sub) async {
    final ext = src.split('.').lastOrNull ?? 'bin';
    final name = Storage.newName(ext.toLowerCase());
    return Storage.import(src, sub, name: name);
  }

  /// 导入并记录为媒体
  static Future<Picked> importPicked(Picked p, String type, String sub) async {
    final ext = p.path.split('.').lastOrNull ?? 'bin';
    final name = Storage.newName(ext.toLowerCase());
    final abs = await Storage.import(p.path, sub, name: name);
    return Picked(path: abs, name: p.name.isEmpty ? name : p.name, size: p.size);
  }
}