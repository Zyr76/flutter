-- ============================================================
-- 性能对比：ObjectBox vs SQLite
--
-- 在 app 内直接运行本文件即可。数字只有真机才有意义。
--
-- 对比口径（尽量公平，差异都写出来）：
--   * 同一份数据：键 k，值 v 为同一段 JSON 文本，另有整数列 u
--   * 同一组操作：写入 N / 随机读取 N / 更新 N/2 / 删除 N/2 / count / 全量扫描
--   * ObjectBox：走 resources/lua/objectbox.lua 封装，每次调用一次 put/get
--   * SQLite：WAL + synchronous=NORMAL；写入/更新/删除放在单事务里批量提交
--     （SQLite 不开事务逐条提交会 fsync 每条，慢一个量级——另用 N_SMALL 单列展示）
--   * 计时用 System.nanoTime()（单调时钟，不受墙钟调整影响）
-- ============================================================
local ob = require "objectbox"
local JSON = require "yyjson"

local System = luajava.bindClass("java.lang.System")
local SQLiteDatabase = luajava.bindClass("android.database.sqlite.SQLiteDatabase")
local File = luajava.bindClass("java.io.File")

local N = 2000        -- 主样本量
local N_SMALL = 200   -- SQLite 逐条自动提交的样本量
local SPACE = "perf_ob"
local CTX = activity or this
local DB_PATH = CTX.getCacheDir().getAbsolutePath() .. "/perf_cmp.db"

local function now() return System.nanoTime() end
local function ms(t0) return tonumber(now() - t0) / 1e6 end

local results = {}
local function record(name, ops, elapsed)
  results[#results + 1] = {
    name = name, ops = ops, ms = elapsed,
    per = elapsed / ops, qps = ops / (elapsed / 1000),
  }
  print(string.format("    %-26s %6d 次  %9.3f ms  %8.4f ms/次  %10.0f 次/秒",
    name, ops, elapsed, elapsed / ops, ops / (elapsed / 1000)))
end

local function key(i) return string.format("k%06d", i) end
local function value(i)
  return JSON.encode({ 序号 = i, 标题 = "条目" .. i, 标签 = { "a", "b" }, 启用 = i % 2 == 0 })
end
local function mixed(i) return (i * 7919) % N + 1 end -- 固定伪随机，两个库取同样的序

print(string.rep("=", 68))
print("性能对比：ObjectBox vs SQLite    样本 N=" .. N)
print(string.rep("=", 68))

-- ============================================================ ObjectBox
local tAll = now()
ob.清空(SPACE)

local t = now()
for i = 1, N do ob.存(SPACE, key(i), { 序号 = i, 标题 = "条目" .. i, 标签 = { "a", "b" }, 启用 = i % 2 == 0 }) end
record("ObjectBox 写入", N, ms(t))

t = now()
local hit = 0
for i = 1, N do
  local v = ob.取(SPACE, key(mixed(i)))
  if v then hit = hit + 1 end
end
record("ObjectBox 随机读", N, ms(t))
assert(hit == N, "ObjectBox 随机读未全部命中")

t = now()
for i = 1, N / 2 do ob.存(SPACE, key(i), { 序号 = i, 标题 = "改过" .. i, 标签 = { "c" }, 启用 = false }) end
record("ObjectBox 更新", N / 2, ms(t))

t = now()
ob.数量(SPACE)
record("ObjectBox count", 1, ms(t))

t = now()
local ks = ob.键(SPACE)
for _, k in ipairs(ks) do ob.取(SPACE, k) end
record("ObjectBox 全量扫描", #ks, ms(t))

t = now()
for i = 1, N / 2 do ob.删(SPACE, key(i)) end
record("ObjectBox 删除", N / 2, ms(t))
assert(ob.数量(SPACE) == N / 2, "ObjectBox 删除后数量不对")

local obTotal = ms(tAll)
ob.清空(SPACE)
print(string.format("  ObjectBox 小计 %.1f ms", obTotal))

-- ============================================================ SQLite（WAL + 单事务）
print("\n" .. string.rep("-", 68))
print("SQLite（WAL + synchronous=NORMAL + 单事务批量）")
local okSql, err = pcall(function()
  local db = SQLiteDatabase.openOrCreateDatabase(DB_PATH, nil)
  db.enableWriteAheadLogging()
  db.execSQL("PRAGMA synchronous=NORMAL")
  db.execSQL("DROP TABLE IF EXISTS kv")
  db.execSQL("CREATE TABLE kv (k TEXT PRIMARY KEY NOT NULL, v TEXT, u INTEGER)")

  -- 写入
  local st = db.compileStatement("INSERT OR REPLACE INTO kv(k,v,u) VALUES(?,?,?)")
  local t0 = now()
  db.beginTransaction()
  for i = 1, N do
    st.bindString(1, key(i))
    st.bindString(2, value(i))
    st.bindLong(3, i)
    st.executeInsert()
  end
  db.setTransactionSuccessful()
  db.endTransaction()
  record("SQLite 写入（单事务）", N, ms(t0))
  st.close()

  -- 随机读（rawQuery + cursor，典型用法）
  t0 = now()
  local miss = 0
  for i = 1, N do
    local c = db.rawQuery("SELECT v FROM kv WHERE k=?", luajava.createArray("java.lang.String", { key(mixed(i)) }))
    if c.moveToFirst() then
      c.getString(0)
    else
      miss = miss + 1
    end
    c.close()
  end
  record("SQLite 随机读", N, ms(t0))
  assert(miss == 0, "SQLite 随机读有未命中 " .. miss)

  -- 更新（单事务）
  local su = db.compileStatement("UPDATE kv SET v=?, u=? WHERE k=?")
  t0 = now()
  db.beginTransaction()
  for i = 1, N / 2 do
    su.bindString(1, JSON.encode({ 序号 = i, 标题 = "改过" .. i, 标签 = { "c" }, 启用 = false }))
    su.bindLong(2, i)
    su.bindString(3, key(i))
    su.executeUpdateDelete()
  end
  db.setTransactionSuccessful()
  db.endTransaction()
  record("SQLite 更新（单事务）", N / 2, ms(t0))
  su.close()

  -- count
  t0 = now()
  local c = db.rawQuery("SELECT COUNT(*) FROM kv", nil)
  c.moveToFirst()
  c.getLong(0)
  c.close()
  record("SQLite count", 1, ms(t0))

  -- 全量扫描
  t0 = now()
  local n = 0
  local c2 = db.rawQuery("SELECT k,v FROM kv", nil)
  while c2.moveToNext() do
    c2.getString(0)
    c2.getString(1)
    n = n + 1
  end
  c2.close()
  record("SQLite 全量扫描", n, ms(t0))

  -- 删除（单事务）
  local sd = db.compileStatement("DELETE FROM kv WHERE k=?")
  t0 = now()
  db.beginTransaction()
  for i = 1, N / 2 do
    sd.bindString(1, key(i))
    sd.executeUpdateDelete()
  end
  db.setTransactionSuccessful()
  db.endTransaction()
  record("SQLite 删除（单事务）", N / 2, ms(t0))
  sd.close()

  db.close()
end)
if not okSql then
  print("  ! SQLite 部分失败：" .. tostring(err))
end

-- ============================================================ SQLite（默认配置，逐条提交）
print("\n" .. string.rep("-", 68))
print(string.format("SQLite（默认配置、逐条自动提交，N=%d）—— 用来看事务批量提交的差距", N_SMALL))
pcall(function()
  local p2 = DB_PATH .. ".nontx"
  local db = SQLiteDatabase.openOrCreateDatabase(p2, nil)
  db.execSQL("DROP TABLE IF EXISTS kv")
  db.execSQL("CREATE TABLE kv (k TEXT PRIMARY KEY NOT NULL, v TEXT, u INTEGER)")
  local st = db.compileStatement("INSERT OR REPLACE INTO kv(k,v,u) VALUES(?,?,?)")
  local t0 = now()
  for i = 1, N_SMALL do
    st.bindString(1, key(i))
    st.bindString(2, value(i))
    st.bindLong(3, i)
    st.executeInsert()
  end
  record("SQLite 写入（无事务）", N_SMALL, ms(t0))
  st.close()
  db.close()
  File(p2).delete()
  File(p2 .. "-wal").delete()
  File(p2 .. "-shm").delete()
end)

-- ============================================================ 对比表
print("\n" .. string.rep("=", 68))
print(string.format("%-28s %12s %14s %12s", "项目", "耗时(ms)", "ms/次", "次/秒"))
print(string.rep("-", 68))
for _, r in ipairs(results) do
  print(string.format("%-28s %12.3f %14.4f %12.0f", r.name, r.ms, r.per, r.qps))
end
print(string.rep("-", 68))

-- 成对比较（同一口径：同为事务/批量，或同为逐条）
local function find(name)
  for _, r in ipairs(results) do
    if r.name == name then return r end
  end
  return nil
end
local pairsToCompare = {
  { "写入", "ObjectBox 写入", "SQLite 写入（单事务）" },
  { "随机读", "ObjectBox 随机读", "SQLite 随机读" },
  { "更新", "ObjectBox 更新", "SQLite 更新（单事务）" },
  { "删除", "ObjectBox 删除", "SQLite 删除（单事务）" },
}
print("相对速度（>1 表示 ObjectBox 更快）：")
for _, p in ipairs(pairsToCompare) do
  local a, b = find(p[2]), find(p[3])
  if a and b then
    print(string.format("  %-8s ObjectBox %8.4f ms/次   SQLite %8.4f ms/次   倍数 %.2fx",
      p[1], a.per, b.per, b.per / a.per))
  end
end

-- 清理
pcall(function()
  File(DB_PATH).delete()
  File(DB_PATH .. "-wal").delete()
  File(DB_PATH .. "-shm").delete()
end)
ob.清空(SPACE)
print("\n完成。测试数据已清理。")
