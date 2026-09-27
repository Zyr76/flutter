// 数据模型

class User {
  int? id;
  final String username;
  final String salt;
  final String passwordHash;
  String nickname;
  String? avatarFile; // 相对应用目录的路径
  String? bgFile;
  String? gesture; // 手势解锁密码（组件编码，AES key 派生前）
  String gestureKey0; // 手势/生物识别解锁用的随机密钥
  int biometricEnabled; // 指纹解锁（历史兼容，仍代表指纹）
  final int createdAt;

  User({
    this.id,
    required this.username,
    required this.salt,
    required this.passwordHash,
    this.nickname = '',
    this.avatarFile,
    this.bgFile,
    this.gesture,
    this.gestureKey0 = '',
    this.biometricEnabled = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'salt': salt,
        'password_hash': passwordHash,
        'nickname': nickname,
        'avatar_file': avatarFile,
        'bg_file': bgFile,
        'gesture': gesture,
        'gesture_key': gestureKey0,
        'biometric': biometricEnabled,
        'created_at': createdAt,
      };

  factory User.fromMap(Map<String, dynamic> m) => User(
        id: m['id'] as int,
        username: m['username'] as String,
        salt: m['salt'] as String,
        passwordHash: m['password_hash'] as String,
        nickname: (m['nickname'] ?? '') as String,
        avatarFile: m['avatar_file'] as String?,
        bgFile: m['bg_file'] as String?,
        gesture: m['gesture'] as String?,
        gestureKey0: (m['gesture_key'] ?? '') as String,
        biometricEnabled: (m['biometric'] ?? 0) as int,
        createdAt: m['created_at'] as int,
      );
}

class Shuoshuo {
  int id;
  final int userId;
  final String content;
  final String location;
  String category; // 随笔分类：日常 / 生活 / 旅行 / 自定义…
  final int createdAt;
  final int updatedAt;

  Shuoshuo({
    required this.id,
    required this.userId,
    required this.content,
    this.location = '',
    this.category = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'content': content,
        'location': location,
        'category': category,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Shuoshuo.fromMap(Map<String, dynamic> m) => Shuoshuo(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        content: (m['content'] ?? '') as String,
        location: (m['location'] ?? '') as String,
        category: (m['category'] ?? '') as String,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );
}

/// 说说自定义分类（用户可自行新增）
class ShuoCategory {
  final int id;
  final int userId;
  final String name;
  ShuoCategory({required this.id, required this.userId, required this.name});
  Map<String, dynamic> toMap() => {'id': id, 'user_id': userId, 'name': name};
  factory ShuoCategory.fromMap(Map<String, dynamic> m) =>
      ShuoCategory(id: m['id'], userId: m['user_id'], name: m['name'] as String);
}

/// media 归属关联视图（说说 / 相册 / 文件）
class Media {
  int id;
  final int userId;
  final String type; // image / video / livephoto / file
  final String filePath; // 绝对路径（应用私有目录内）
  final String? thumb;
  final String mime;
  final String name;
  final int size;
  final int createdAt;

  Media({
    required this.id,
    required this.userId,
    required this.type,
    required this.filePath,
    this.thumb,
    this.mime = '',
    required this.name,
    required this.size,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'type': type,
        'file_path': filePath,
        'thumb': thumb,
        'mime': mime,
        'name': name,
        'size': size,
        'created_at': createdAt,
      };

  factory Media.fromMap(Map<String, dynamic> m) => Media(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        type: m['type'] as String,
        filePath: m['file_path'] as String,
        thumb: m['thumb'] as String?,
        mime: (m['mime'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        size: (m['size'] ?? 0) as int,
        createdAt: m['created_at'] as int,
      );
}

class ShuoMedia {
  final int id;
  final int shuoshuoId;
  final int mediaId;
  ShuoMedia({required this.id, required this.shuoshuoId, required this.mediaId});
  Map<String, dynamic> toMap() =>
      {'id': id, 'shuoshuo_id': shuoshuoId, 'media_id': mediaId};
  factory ShuoMedia.fromMap(Map<String, dynamic> m) => ShuoMedia(
      id: m['id'], shuoshuoId: m['shuoshuo_id'], mediaId: m['media_id']);
}

class Diary {
  int id;
  final int userId;
  String title;
  String content;
  String mood;
  int moodValue; // 情绪温度计取值：0(冰点) ~ 10(沸腾)
  String weather;
  String location;
  final int createdAt;
  final int updatedAt;

  Diary({
    required this.id,
    required this.userId,
    this.title = '',
    this.content = '',
    this.mood = '',
    this.moodValue = 5,
    this.weather = '',
    this.location = '',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'content': content,
        'mood': mood,
        'mood_value': moodValue,
        'weather': weather,
        'location': location,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Diary.fromMap(Map<String, dynamic> m) => Diary(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        mood: (m['mood'] ?? '') as String,
        moodValue: (m['mood_value'] ?? 5) as int,
        weather: (m['weather'] ?? '') as String,
        location: (m['location'] ?? '') as String,
        createdAt: m['created_at'] as int,
        updatedAt: m['updated_at'] as int,
      );
}

class Capsule {
  int id;
  final int userId;
  String title;
  String content;
  String? filePath;
  String mediaType; // none / image / video / file
  final int unlockAt; // 写入时间（封存）；到期=写入时间+预定时长
  final int openAt; // 期望开启的时间戳
  final int createdAt;

  Capsule({
    required this.id,
    required this.userId,
    this.title = '',
    this.content = '',
    this.filePath,
    this.mediaType = 'none',
    required this.unlockAt,
    required this.openAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'content': content,
        'file_path': filePath,
        'media_type': mediaType,
        'unlock_at': unlockAt,
        'open_at': openAt,
        'created_at': createdAt,
      };

  factory Capsule.fromMap(Map<String, dynamic> m) => Capsule(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        title: (m['title'] ?? '') as String,
        content: (m['content'] ?? '') as String,
        filePath: m['file_path'] as String?,
        mediaType: (m['media_type'] ?? 'none') as String,
        unlockAt: m['unlock_at'] as int,
        openAt: m['open_at'] as int,
        createdAt: m['created_at'] as int,
      );
}

class Album {
  int id;
  final int userId;
  String name;
  String? coverPath;
  final int createdAt;

  Album({
    required this.id,
    required this.userId,
    required this.name,
    this.coverPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'cover_path': coverPath,
        'created_at': createdAt,
      };

  factory Album.fromMap(Map<String, dynamic> m) => Album(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        name: m['name'] as String,
        coverPath: m['cover_path'] as String?,
        createdAt: m['created_at'] as int,
      );
}

class AlbumMedia {
  int id;
  final int albumId;
  final int userId;
  final String filePath;
  final String? thumb;
  final String mime;
  final String name;
  final int size;
  final int createdAt;

  AlbumMedia({
    required this.id,
    required this.albumId,
    required this.userId,
    required this.filePath,
    this.thumb,
    this.mime = '',
    required this.name,
    required this.size,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'album_id': albumId,
        'user_id': userId,
        'file_path': filePath,
        'thumb': thumb,
        'mime': mime,
        'name': name,
        'size': size,
        'created_at': createdAt,
      };

  factory AlbumMedia.fromMap(Map<String, dynamic> m) => AlbumMedia(
        id: m['id'] as int,
        albumId: m['album_id'] as int,
        userId: m['user_id'] as int,
        filePath: m['file_path'] as String,
        thumb: m['thumb'] as String?,
        mime: (m['mime'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        size: (m['size'] ?? 0) as int,
        createdAt: m['created_at'] as int,
      );
}

class SpaceFolder {
  int id;
  final int userId;
  final int parentId;
  String name;
  final int createdAt;

  SpaceFolder({
    required this.id,
    required this.userId,
    required this.parentId,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'parent_id': parentId,
        'name': name,
        'created_at': createdAt,
      };

  factory SpaceFolder.fromMap(Map<String, dynamic> m) => SpaceFolder(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        parentId: m['parent_id'] as int,
        name: m['name'] as String,
        createdAt: m['created_at'] as int,
      );
}

class SpaceFile {
  int id;
  final int userId;
  final int folderId;
  final String filePath;
  String name;
  final int size;
  final String mime;
  final int createdAt;

  SpaceFile({
    required this.id,
    required this.userId,
    required this.folderId,
    required this.filePath,
    required this.name,
    required this.size,
    this.mime = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'folder_id': folderId,
        'file_path': filePath,
        'name': name,
        'size': size,
        'mime': mime,
        'created_at': createdAt,
      };

  factory SpaceFile.fromMap(Map<String, dynamic> m) => SpaceFile(
        id: m['id'] as int,
        userId: m['user_id'] as int,
        folderId: m['folder_id'] as int,
        filePath: m['file_path'] as String,
        name: (m['name'] ?? '') as String,
        size: (m['size'] ?? 0) as int,
        mime: (m['mime'] ?? '') as String,
        createdAt: m['created_at'] as int,
      );
}