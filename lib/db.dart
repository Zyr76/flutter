import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// sqlite 数据访问层
class Db {
  Db._();
  static final Db instance = Db._();

  Database? _db;
  Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'private_space.db');
    _db = await openDatabase(
      path,
      version: 5,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  Future<void> _create(Database d, int v) async {
    await d.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        salt TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        nickname TEXT NOT NULL DEFAULT '',
        avatar_file TEXT,
        bg_file TEXT,
        gesture TEXT,
        gesture_key TEXT NOT NULL DEFAULT '',
        biometric INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE shuoshuo(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE shuo_category(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE shuo_media(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shuoshuo_id INTEGER NOT NULL,
        media_id INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE media(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumb TEXT,
        mime TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        size INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE diary(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        mood TEXT NOT NULL DEFAULT '',
        mood_value INTEGER NOT NULL DEFAULT 5,
        weather TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE capsule(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        file_path TEXT,
        media_type TEXT NOT NULL DEFAULT 'none',
        unlock_at INTEGER NOT NULL,
        open_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE album(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        cover_path TEXT,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE album_media(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        album_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        thumb TEXT,
        mime TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        size INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE folder(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        parent_id INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE space_file(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        folder_id INTEGER NOT NULL DEFAULT 0,
        file_path TEXT NOT NULL,
        name TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        mime TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
  }

  Future<void> _upgrade(Database d, int oldV, int newV) async {
    // 1 -> 2：日志新增位置字段
    if (oldV < 2) {
      await d.execute("ALTER TABLE diary ADD COLUMN location TEXT NOT NULL DEFAULT ''");
    }
    // 4 -> 5：说说新增分类 + 分类表 + 日志情绪温度计
    if (oldV < 5) {
      await d.execute("ALTER TABLE shuoshuo ADD COLUMN category TEXT NOT NULL DEFAULT ''");
      await d.execute('''
        CREATE TABLE IF NOT EXISTS shuo_category(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          name TEXT NOT NULL
        )''');
      await d.execute("ALTER TABLE diary ADD COLUMN mood_value INTEGER NOT NULL DEFAULT 5");
    }
  }

  // ---------- 用户 ----------
  Future<int> insertUser(Map<String, dynamic> m) async =>
      (await db).insert('users', m);

  Future<User?> getUserById(int id) async {
    final rows = await (await db).query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  Future<User?> getUserByName(String username) async {
    final rows = await (await db)
        .query('users', where: 'username = ?', whereArgs: [username]);
    if (rows.isEmpty) return null;
    return User.fromMap(rows.first);
  }

  /// 返回所有账号用户名（用于导入备份后提示可登录的账号）。
  Future<List<String>> userNames() async {
    final rows = await (await db).query('users',
        columns: ['username'], orderBy: 'id ASC');
    return rows.map((r) => (r['username'] ?? '') as String).toList();
  }

  /// 关闭当前数据库连接并清空缓存。
  /// 供“导入账号数据”替换数据库文件前调用，之后再次访问会重新打开新文件。
  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }

  Future<void> updateUser(int id, Map<String, dynamic> m) async =>
      (await db).update('users', m, where: 'id = ?', whereArgs: [id]);

  // ---------- 说说 ----------
  Future<int> insertShuoshuo(Map<String, dynamic> m) async =>
      (await db).insert('shuoshuo', m);

  /// [category] 为空表示不过滤分类；[monthKey] 形如 '2026-09'，为空表示不过滤月份；
  /// [dateKey] 形如 '2026-09-25'，为空表示不过滤具体日期。
  Future<List<Map>> shuoshuosByUser(int uid,
      {String? category, String? monthKey, String? dateKey}) async {
    final d = await db;
    final where = <String>['user_id = ?'];
    final args = <Object?>[uid];
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (monthKey != null && monthKey.isNotEmpty) {
      where.add("strftime('%Y-%m', created_at/1000, 'unixepoch', 'localtime') = ?");
      args.add(monthKey);
    }
    if (dateKey != null && dateKey.isNotEmpty) {
      where.add("strftime('%Y-%m-%d', created_at/1000, 'unixepoch', 'localtime') = ?");
      args.add(dateKey);
    }
    final rows = await d.query('shuoshuo',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'created_at DESC');
    final result = <Map>[];
    for (final r in rows) {
      final medRows = await d.rawQuery('''
        SELECT ms.id as link_id, m.* FROM media m
        JOIN shuo_media ms ON ms.media_id = m.id
        WHERE ms.shuoshuo_id = ? ORDER BY m.created_at ASC
      ''', [r['id']]);
      result.add({'shuoshuo': Shuoshuo.fromMap(r), 'media': medRows.map(Media.fromMap).toList()});
    }
    return result;
  }

  /// 说说所属月份（形如 ['2026-09','…']，倒序），供月份筛选使用
  Future<List<String>> shuoshuoMonths(int uid) async {
    final rows = await (await db).rawQuery('''
      SELECT DISTINCT strftime('%Y-%m', created_at/1000, 'unixepoch', 'localtime') k
      FROM shuoshuo WHERE user_id = ? ORDER BY k DESC
    ''', [uid]);
    return rows.map((r) => (r['k'] ?? '') as String).toList();
  }

  /// 说说用过的全部分类（含自定义，供筛选与选择，倒序）
  Future<List<String>> shuoshuoCategoriesInUse(int uid) async {
    final rows = await (await db).rawQuery('''
      SELECT DISTINCT category FROM shuoshuo
      WHERE user_id = ? AND category != '' ORDER BY category ASC
    ''', [uid]);
    return rows.map((r) => (r['category'] ?? '') as String).toList();
  }

  // ---------- 说说自定义分类 ----------
  Future<List<ShuoCategory>> shuoCategories(int uid) async {
    final rows = await (await db).query('shuo_category',
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'name ASC');
    return rows.map(ShuoCategory.fromMap).toList();
  }

  Future<int> insertShuoCategory(int uid, String name) async =>
      (await db).insert('shuo_category', {'user_id': uid, 'name': name});

  Future<void> deleteShuoCategory(int id) async =>
      (await db).delete('shuo_category', where: 'id = ?', whereArgs: [id]);

  Future<void> renameShuoCategory(int id, String name) async =>
      (await db).update('shuo_category', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteShuoshuoSilent(int shuoId, List<int> mediaIds) async {
    final d = await db;
    await d
        .delete('shuo_media', where: 'shuoshuo_id = ?', whereArgs: [shuoId]);
    await d.delete('shuoshuo', where: 'id = ?', whereArgs: [shuoId]);
    for (final mid in mediaIds) {
      await d.delete('media', where: 'id = ?', whereArgs: [mid]);
    }
  }

  Future<void> deleteShuoshuoMedia(int shuoId) async {
    final d = await db;
    await d
        .delete('shuo_media', where: 'shuoshuo_id = ?', whereArgs: [shuoId]);
  }

  Future<int> insertMedia(Map<String, dynamic> m) async =>
      (await db).insert('media', m);

  Future<void> linkShuoMedia(int shuoId, int mediaId) async {
    await (await db).insert('shuo_media', {
      'shuoshuo_id': shuoId,
      'media_id': mediaId,
    });
  }

  Future<int> insertShuoMedia(Map<String, dynamic> m) async =>
      (await db).insert('shuo_media', m);

  Future<void> updateShuoshuo(int id, String content, String location,
      {String category = ''}) async {
    await (await db).update('shuoshuo',
        {'content': content, 'location': location, 'category': category,
         'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 说说里用到的媒体（用于导出）
  Future<List<Media>> shuoshuoAllMedia() async {
    final rows = await (await db).query('media', orderBy: 'created_at DESC');
    return rows.map(Media.fromMap).toList();
  }

  // ---------- 日志 ----------
  Future<int> insertDiary(Map<String, dynamic> m) async =>
      (await db).insert('diary', m);

  Future<List<Diary>> diariesByUser(int uid) async {
    final rows = await (await db).query('diary',
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at ASC');
    return rows.map(Diary.fromMap).toList();
  }

  /// 日志所属的月份（形如 ['2026-09','…']，倒序），供情绪月报的分月切换
  Future<List<String>> diaryMonths(int uid) async {
    final rows = await (await db).rawQuery('''
      SELECT DISTINCT strftime('%Y-%m', created_at/1000, 'unixepoch', 'localtime') k
      FROM diary WHERE user_id = ? ORDER BY k DESC
    ''', [uid]);
    return rows.map((r) => (r['k'] ?? '') as String).toList();
  }

  /// 指定月份的日志（时间升序），供情绪月报统计
  Future<List<Diary>> diariesByMonth(int uid, String monthKey) async {
    final rows = await (await db).query('diary',
        where: "user_id = ? AND strftime('%Y-%m', created_at/1000, 'unixepoch', 'localtime') = ?",
        whereArgs: [uid, monthKey],
        orderBy: 'created_at ASC');
    return rows.map(Diary.fromMap).toList();
  }

  Future<int> updateDiary(int id, Map<String, dynamic> m) async =>
      (await db).update('diary', m, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteDiary(int id) async =>
      (await db).delete('diary', where: 'id = ?', whereArgs: [id]);

  // ---------- 时间胶囊 ----------
  Future<int> insertCapsule(Map<String, dynamic> m) async =>
      (await db).insert('capsule', m);

  Future<List<Capsule>> capsulesByUser(int uid) async {
    final rows = await (await db).query('capsule',
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at DESC');
    return rows.map(Capsule.fromMap).toList();
  }

  Future<void> deleteCapsule(int id) async =>
      (await db).delete('capsule', where: 'id = ?', whereArgs: [id]);

  // ---------- 相册 ----------
  Future<int> insertAlbum(Map<String, dynamic> m) async =>
      (await db).insert('album', m);

  Future<List<Album>> albumsByUser(int uid) async {
    final rows = await (await db).query('album',
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at DESC');
    return rows.map(Album.fromMap).toList();
  }

  Future<void> deleteAlbum(int id) async =>
      (await db).delete('album', where: 'id = ?', whereArgs: [id]);

  Future<void> updateAlbumCover(int id, String coverPath) async {
    await (await db).update('album', {'cover_path': coverPath},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertAlbumMedia(Map<String, dynamic> m) async =>
      (await db).insert('album_media', m);

  Future<List<AlbumMedia>> albumMedia(int albumId) async {
    final rows = await (await db).query('album_media',
        where: 'album_id = ?', whereArgs: [albumId], orderBy: 'created_at DESC');
    return rows.map(AlbumMedia.fromMap).toList();
  }

  Future<void> deleteAlbumMedia(int id) async =>
      (await db).delete('album_media', where: 'id = ?', whereArgs: [id]);

  /// 获取或创建“说说的照片”默认相册，用于汇总说说发布的图片/视频/实况图
  Future<Album> getOrCreateShuoAlbum(int uid) async {
    final d = await db;
    const name = '说说的照片';
    final rows = await d.query('album',
        where: 'user_id = ? AND name = ?', whereArgs: [uid, name], limit: 1);
    if (rows.isNotEmpty) return Album.fromMap(rows.first);
    final id = await d.insert('album', {
      'user_id': uid,
      'name': name,
      'cover_path': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return Album(
        id: id, userId: uid, name: name, createdAt: DateTime.now().millisecondsSinceEpoch);
  }

  /// 把说说发布的媒体同步到空间相册（图片/视频/实况图）
  Future<void> mirrorShuoMediaToAlbum(int uid, String filePath,
      {String? thumb, required String mime, required String name,
      required int size, required int createdAt}) async {
    final album = await getOrCreateShuoAlbum(uid);
    final d = await db;
    // 避免重复镜像（编辑时可能重复保存同一文件）
    final dup = await d.rawQuery(
        'SELECT id FROM album_media WHERE user_id = ? AND file_path = ? LIMIT 1',
        [uid, filePath]);
    if (dup.isNotEmpty) return;
    await d.insert('album_media', {
      'album_id': album.id,
      'user_id': uid,
      'file_path': filePath,
      'thumb': thumb,
      'mime': mime,
      'name': name,
      'size': size,
      'created_at': createdAt,
    });
    if (album.coverPath == null || album.coverPath!.isEmpty) {
      await updateAlbumCover(album.id, filePath);
    }
  }

  /// 把说说发布的文件同步到空间文件根目录
  Future<void> mirrorShuoMediaToSpaceFile(int uid, String filePath,
      {required String mime, required String name, required int size,
      required int createdAt}) async {
    final d = await db;
    final dup = await d.rawQuery(
        'SELECT id FROM space_file WHERE user_id = ? AND file_path = ? LIMIT 1',
        [uid, filePath]);
    if (dup.isNotEmpty) return;
    await d.insert('space_file', {
      'user_id': uid,
      'folder_id': 0,
      'file_path': filePath,
      'name': name,
      'size': size,
      'mime': mime,
      'created_at': createdAt,
    });
  }

  /// 判断某文件路径是否是“说说”里的媒体（用于空间删除时保护源媒体）
  Future<bool> isShuoMedia(String filePath) async {
    final rows = await (await db).query('media',
        where: 'file_path = ?', whereArgs: [filePath], limit: 1);
    return rows.isNotEmpty;
  }

  /// 查询某个媒体文件所属的所有说说（用于相册长按“定位到说说”）。
  Future<List<Map>> shuoshuosByMedia(String filePath) async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT DISTINCT s.* FROM shuoshuo s
      JOIN shuo_media sm ON sm.shuoshuo_id = s.id
      JOIN media m ON m.id = sm.media_id
      WHERE m.file_path = ?
      ORDER BY s.created_at DESC
    ''', [filePath]);
    final result = <Map>[];
    for (final r in rows) {
      final medRows = await d.rawQuery('''
        SELECT ms.id as link_id, m.* FROM media m
        JOIN shuo_media ms ON ms.media_id = m.id
        WHERE ms.shuoshuo_id = ? ORDER BY m.created_at ASC
      ''', [r['id']]);
      result.add({
        'shuoshuo': Shuoshuo.fromMap(r),
        'media': medRows.map(Media.fromMap).toList()
      });
    }
    return result;
  }

  /// 删除某文件在空间里的镜像记录（相册/空间文件），用于删除说说时清理
  Future<void> deleteSpaceMirrorsByPath(int uid, String filePath) async {
    final d = await db;
    final am = await d.rawQuery(
        'SELECT id FROM album_media WHERE user_id = ? AND file_path = ?',
        [uid, filePath]);
    for (final r in am) {
      await d.delete('album_media', where: 'id = ?', whereArgs: [r['id']]);
    }
    final sf = await d.rawQuery(
        'SELECT id FROM space_file WHERE user_id = ? AND file_path = ?',
        [uid, filePath]);
    for (final r in sf) {
      await d.delete('space_file', where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  // ---------- 空间文件 ----------
  Future<int> insertFolder(Map<String, dynamic> m) async =>
      (await db).insert('folder', m);

  Future<List<SpaceFolder>> foldersBy(int uid, int parentId) async {
    final rows = await (await db).query('folder',
        where: 'user_id = ? AND parent_id = ?', whereArgs: [uid, parentId],
        orderBy: 'created_at ASC');
    return rows.map(SpaceFolder.fromMap).toList();
  }

  Future<void> deleteFolder(int id) async {
    final d = await db;
    final sub = await d
        .query('folder', where: 'parent_id = ?', whereArgs: [id]);
    for (final s in sub) {
      await deleteFolder(s['id'] as int);
    }
    await _deleteSpaceFilesInFolder(d, id);
    await d.delete('folder', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SpaceFile>> spaceFilesBy(int uid, int folderId) async {
    final rows = await (await db).query('space_file',
        where: 'user_id = ? AND folder_id = ?', whereArgs: [uid, folderId],
        orderBy: 'created_at DESC');
    return rows.map(SpaceFile.fromMap).toList();
  }

  Future<int> insertSpaceFile(Map<String, dynamic> m) async =>
      (await db).insert('space_file', m);

  Future<List<SpaceFile>> allSpaceFiles(int uid) async {
    final rows = await (await db).query('space_file',
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at DESC');
    return rows.map(SpaceFile.fromMap).toList();
  }

  Future<void> deleteSpaceFile(int id) async =>
      (await db).delete('space_file', where: 'id = ?', whereArgs: [id]);

  /// 重命名空间文件：同时更新展示名与磁盘路径（磁盘路径仅在文件被物理改名时传入）。
  Future<void> renameSpaceFile(int id, String name, String filePath) async {
    await (await db).update('space_file',
        {'name': name, 'file_path': filePath},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _deleteSpaceFilesInFolder(Database d, int folderId) async {
    final files = await d.query('space_file',
        where: 'folder_id = ?', whereArgs: [folderId]);
    for (final f in files) {
      await d.delete('space_file', where: 'id = ?', whereArgs: [f['id']]);
    }
  }
}