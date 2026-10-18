package com.androlua.net;

import android.os.Build;
import android.os.Handler;
import android.util.Log;
import android.os.Looper;

import com.luajava.LuaObject;
import com.luajava.LuaState;
import com.luajava.LuaTable;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.nio.charset.Charset;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

import okhttp3.Cache;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Cookie;
import okhttp3.CookieJar;
import okhttp3.Dispatcher;
import okhttp3.FormBody;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

/**
 * OkHttp 的 Lua 门面（Lua 侧见 resources/lua/okhttp.lua）。
 *
 * <p>线程模型：请求在 OkHttp 线程池执行，**所有 Lua 回调统一 post 回主线程**——
 * Lua 状态只在主线程使用，从 worker 线程直接调用会破坏 Lua 栈。
 *
 * <p>已支持：query / form / json / responseType / charset / timeout / 取消 /
 * 断点续传下载 / 进度回调 / 单文件与多文件上传 / 批量并发 / Cookie（内存 + 落盘）/
 * 重试 / 缓存 / 代理 / 忽略证书 / 请求 id / 自定义日志。
 */
public final class LuaOkHttp {

    private static final MediaType TEXT = MediaType.parse("text/plain; charset=utf-8");
    private static final MediaType OCTET = MediaType.parse("application/octet-stream");
    /** P3-10：Lua 字节串与 Java 字符串之间的一一映射编码。 */
    private static final Charset ISO_8859_1 = Charset.forName("ISO-8859-1");
    private static final long MAX_IN_MEMORY = 8L * 1024 * 1024;

    private static volatile boolean DEBUG = false;
    private static volatile LuaObject LOGGER = null;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** P1-2：进度节流门闩改为「每个下载一份」，避免多任务互相阻塞。 */
    private static final class ProgressGate {
        final AtomicBoolean pending = new AtomicBoolean(false);
    }

    // ---------- 可重建的客户端组件（cache / proxy / ssl）----------
    private static File cacheDir = null;
    private static long cacheSize = 0;
    private static Proxy proxy = null;
    private static boolean trustAll = false;
    private static final Map<String, List<Cookie>> COOKIE_STORE = new ConcurrentHashMap<String, List<Cookie>>();
    private static volatile File cookieFile = null;

    private static final CookieJar JAR = new CookieJar() {
        @Override
        public void saveFromResponse(HttpUrl url, List<Cookie> cookies) {
            if (cookies == null || cookies.isEmpty()) {
                return;
            }
            synchronized (COOKIE_STORE) {
                List<Cookie> old = COOKIE_STORE.get(url.host());
                List<Cookie> merged = old == null ? new ArrayList<Cookie>() : new ArrayList<Cookie>(old);
                merged.addAll(cookies);
                COOKIE_STORE.put(url.host(), merged);
            }
            saveCookies();
        }

        @Override
        public List<Cookie> loadForRequest(HttpUrl url) {
            List<Cookie> out = new ArrayList<Cookie>();
            synchronized (COOKIE_STORE) {
                List<Cookie> all = COOKIE_STORE.get(url.host());
                if (all != null) {
                    for (Cookie c : all) {
                        if (c.matches(url)) {
                            out.add(c);
                        }
                    }
                }
            }
            return out;
        }
    };

    private static final Map<String, OkHttpClient> CLIENT_CACHE = new ConcurrentHashMap<String, OkHttpClient>();

    private static volatile OkHttpClient CLIENT = buildClient();

    private static OkHttpClient buildClient() {
        OkHttpClient.Builder b = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(20, TimeUnit.SECONDS)
                .writeTimeout(20, TimeUnit.SECONDS)
                .followRedirects(true)
                .cookieJar(JAR);
        if (cacheDir != null && cacheSize > 0) {
            b.cache(new Cache(cacheDir, cacheSize));
        }
        if (proxy != null) {
            b.proxy(proxy);
        }
        if (trustAll) {
            try {
                final TrustManager[] tm = new TrustManager[]{new X509TrustManager() {
                    @Override
                    public void checkClientTrusted(X509Certificate[] chain, String authType) {
                    }

                    @Override
                    public void checkServerTrusted(X509Certificate[] chain, String authType) {
                    }

                    @Override
                    public X509Certificate[] getAcceptedIssuers() {
                        return new X509Certificate[0];
                    }
                }};
                SSLContext sc = SSLContext.getInstance("TLS");
                sc.init(null, tm, new SecureRandom());
                SSLSocketFactory f = sc.getSocketFactory();
                b.sslSocketFactory(f, (X509TrustManager) tm[0]);
                b.hostnameVerifier(new HostnameVerifier() {
                    @Override
                    public boolean verify(String hostname, SSLSession session) {
                        return true;
                    }
                });
            } catch (Exception ignored) {
            }
        }
        OkHttpClient c = b.build();
        Dispatcher d = c.dispatcher();
        d.setMaxRequests(64);
        d.setMaxRequestsPerHost(8);
        return c;
    }

    private static synchronized void rebuild() {
        CLIENT = buildClient();
        CLIENT_CACHE.clear();
    }

    // ---------- Cookie：内存 + 可选落盘 ----------

    /** 设置 Cookie 落盘文件；传 null 取消。文件已存在时会自动加载。 */
    public static void setCookieFile(String path) {
        if (path == null || path.trim().isEmpty()) {
            cookieFile = null;
            return;
        }
        File f = new File(path);
        cookieFile = f;
        loadCookies(f);
    }

    public static void clearCookies() {
        synchronized (COOKIE_STORE) {
            COOKIE_STORE.clear();
        }
        saveCookies();
    }

    private static void loadCookies(File f) {
        if (f == null || !f.isFile()) {
            return;
        }
        synchronized (COOKIE_STORE) {
            COOKIE_STORE.clear();
            BufferedReader r = null;
            try {
                r = new BufferedReader(new FileReader(f));
                String line;
                while ((line = r.readLine()) != null) {
                    int tab = line.indexOf('\t');
                    if (tab <= 0 || tab + 1 >= line.length()) {
                        continue;
                    }
                    String host = line.substring(0, tab);
                    // [1] 防御：某些来源会写出前导点（.example.com），HttpUrl 不接受；
                    // 去掉后再用 cookie 自身的 Domain 属性还原作用域
                    if (host.startsWith(".")) {
                        host = host.substring(1);
                    }
                    HttpUrl u = HttpUrl.parse("https://" + host + "/");
                    if (u == null) {
                        continue;
                    }
                    Cookie c = Cookie.parse(u, line.substring(tab + 1));
                    if (c == null) {
                        continue;
                    }
                    List<Cookie> list = COOKIE_STORE.get(host);
                    if (list == null) {
                        list = new ArrayList<Cookie>();
                        COOKIE_STORE.put(host, list);
                    }
                    list.add(c);
                }
            } catch (Exception ignored) {
            } finally {
                if (r != null) {
                    try {
                        r.close();
                    } catch (IOException ignored) {
                    }
                }
            }
        }
    }

    /** 原子写：临时文件 + rename，避免写一半掉电留下坏文件。 */
    private static synchronized void saveCookies() {
        File f = cookieFile;
        if (f == null) {
            return;
        }
        File tmp = new File(f.getAbsolutePath() + ".tmp");
        FileWriter w = null;
        try {
            File parent = f.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            w = new FileWriter(tmp);
            synchronized (COOKIE_STORE) {
                for (Map.Entry<String, List<Cookie>> e : COOKIE_STORE.entrySet()) {
                    for (Cookie c : e.getValue()) {
                        w.write(e.getKey());
                        w.write('\t');
                        w.write(c.toString());
                        w.write('\n');
                    }
                }
            }
            w.flush();
            w.close();      // #7：置 null 放到 finally，close 抛异常时也不会重复 close
            if (Build.VERSION.SDK_INT >= 26) {
                try {
                    java.nio.file.Files.move(tmp.toPath(), f.toPath(),
                            java.nio.file.StandardCopyOption.ATOMIC_MOVE,
                            java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    return;
                } catch (Exception ignored) {
                }
            }
            if (f.exists() && !f.delete()) {
                tmp.delete();
                return;
            }
            if (!tmp.renameTo(f)) {
                tmp.delete();
            }
        } catch (Exception ignored) {
        } finally {
            if (w != null) {
                try {
                    w.close();
                } catch (IOException ignored) {
                }
                w = null;
            }
        }
    }

    // ---------- 客户端配置 ----------
    public static void setDebug(boolean on) {
        DEBUG = on;
    }

    public static void setLogger(LuaObject logger) {
        LOGGER = logger;
    }

    /** [16] 磁盘缓存。sizeBytes > 0 才生效；dir 传 null 关闭。 */
    public static void setCache(String dir, double sizeBytes) {
        cacheDir = (dir == null || dir.isEmpty()) ? null : new File(dir);
        cacheSize = (long) sizeBytes;
        rebuild();
    }

    /** [17] HTTP 代理。传空 host 等于清除。 */
    public static void setProxy(String host, double port) {
        if (host == null || host.isEmpty()) {
            proxy = null;
        } else {
            proxy = new Proxy(Proxy.Type.HTTP, new InetSocketAddress(host, (int) port));
        }
        rebuild();
    }

    /** [18] 是否校验证书。verify=false 表示信任所有证书（仅调试用）。 */
    public static void setSslVerify(boolean verify) {
        trustAll = !verify;
        rebuild();
    }

    // ---------- 核心：统一的执行与结果投递 ----------
    /** #1：响应快照——Response 在工作线程读完就关，不再跨线程传递。 */
    private static final class Snapshot {
        final int code;
        final okhttp3.Headers headers;

        Snapshot(int code, okhttp3.Headers headers) {
            this.code = code;
            this.headers = headers;
        }
    }

    private interface Sink {
        void done(Snapshot snapshot, String body, String error, boolean canceled);
    }

    /**
     * 可取消句柄：重试会换新的 Call，取消必须转发到"当前那一个"，
     * 否则用户取消的是已经失败掉的旧 Call，重试仍在跑。
     */
    /** all() 里各请求的结果（替代原来的 Object[] 打包）。 */
    private static final class Result {
        boolean ok;
        int code;
        String body;
        String error;
        boolean canceled;
    }

    public static class Handle {
        private volatile Call current;

        void set(Call c) {
            current = c;
        }

        public void cancel() {
            Call c = current;
            if (c != null) {
                c.cancel();
            }
        }
    }


    private static OkHttpClient clientFor(int timeoutMs, boolean forDownload) {
        if (timeoutMs <= 0) {
            return CLIENT;
        }
        String cacheKey = timeoutMs + (forDownload ? ":download" : ":request");   // #5：语义自明
        OkHttpClient cached = CLIENT_CACHE.get(cacheKey);
        if (cached != null) {
            return cached;
        }
        OkHttpClient.Builder b = CLIENT.newBuilder();
        if (forDownload) {
            // 下载看的是"单次读多个字节"的间隔，不是总时长，所以给 readTimeout
            b.readTimeout(timeoutMs, TimeUnit.MILLISECONDS);
        } else {
            b.callTimeout(timeoutMs, TimeUnit.MILLISECONDS);
        }
        OkHttpClient made = b.build();
        CLIENT_CACHE.put(cacheKey, made);
        return made;
    }

    /** 构造请求（query / headers / form / body / json 由 Lua 侧编码成 body）。 */
    private static Request buildRequest(LuaTable opts, String method, String url, String tag) throws IOException {
        HttpUrl parsed = HttpUrl.parse(url);
        if (parsed == null) {
            throw new IOException("url 非法：" + url);
        }
        HttpUrl.Builder ub = parsed.newBuilder();
        Object q = opts.get("query");
        if (q instanceof LuaTable) {
            for (Object o : ((LuaTable<?, ?>) q).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                String k = String.valueOf(e.getKey());
                Object v = e.getValue();
                if (v instanceof LuaTable) {
                    LuaTable<?, ?> arr = (LuaTable<?, ?>) v;
                    for (int i = 1; i <= arr.length(); i++) {
                        ub.addQueryParameter(k, String.valueOf(arr.get((double) i)));
                    }
                } else if (v != null) {
                    ub.addQueryParameter(k, String.valueOf(v));
                }
            }
        }

        Request.Builder rb = new Request.Builder().url(ub.build()).tag(tag);

        Object hs = opts.get("headers");
        if (hs instanceof LuaTable) {
            for (Object o : ((LuaTable<?, ?>) hs).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    rb.header(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }

        String realMethod = method;
        String bodyText = str(opts, "body", "");
        RequestBody body = null;
        Object form = opts.get("form");
        if (form instanceof LuaTable) {
            StringBuilder formLog = DEBUG ? new StringBuilder() : null;
            FormBody.Builder fb = new FormBody.Builder();
            for (Object o : ((LuaTable<?, ?>) form).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() == null || e.getValue() == null) {
                    continue;
                }
                String k = String.valueOf(e.getKey());
                Object v = e.getValue();
                if (v instanceof LuaTable) {
                    // 与 query 对齐：数组值 → 同名参数多次
                    LuaTable<?, ?> arr = (LuaTable<?, ?>) v;
                    for (int i = 1; i <= arr.length(); i++) {
                        String one = String.valueOf(arr.get((double) i));
                        fb.add(k, one);
                        if (formLog != null) formLog.append(k).append('=').append(one).append('&');
                    }
                } else {
                    fb.add(k, String.valueOf(v));
                    if (formLog != null) formLog.append(k).append('=').append(v).append('&');
                }
            }
            body = fb.build();
            if (opts.get("method") == null) {
                realMethod = "POST";
            }
            if (!bodyText.isEmpty()) {
                // #4：两者同时给属于调用方误用，直接报错而不是静默丢弃 body
                throw new IOException("form 与 body 不能同时使用，请只用其中一个");
            }
            String kv = (formLog == null || formLog.length() == 0)
                    ? ""
                    : formLog.substring(0, formLog.length() - 1);
            if (DEBUG) {
                log(null, "info", tag + " form: " + kv);
            }
            bodyText = "";
        } else if (!"GET".equals(method) && !"HEAD".equals(method) && !bodyText.isEmpty()) {
            String ct = str(opts, "contentType", "text/plain; charset=utf-8");
            MediaType media = MediaType.parse(ct);
            body = RequestBody.create(media == null ? TEXT : media, bodyText);
        }
        rb.method(realMethod, body);
        return rb.build();
    }

    private static String readBody(Response response, LuaTable<?, ?> opts) throws IOException {
        ResponseBody b = response.body();
        if (b == null) {
            return "";
        }
        long len = b.contentLength();
        String rt = str(opts, "responseType", "text").toLowerCase();
        // P3-8：bytes 模式常用于把图片/二进制读进内存，上限放宽到 32MB；
        // 也可用 opts.maxBytes 自定（字节）
        long limit = "bytes".equals(rt) ? 32L * 1024 * 1024 : MAX_IN_MEMORY;
        Object mb = opts == null ? null : opts.get("maxBytes");
        if (mb instanceof Number) {
            long v = ((Number) mb).longValue();      // P2-4：用 long，避免 int 截断
            if (v > 0) {
                limit = Math.min(v, 64L * 1024 * 1024);   // 硬上限 64MB，防 OOM
            }
        }
        if (len > limit) {
            throw new IOException("响应体过大（" + len + " 字节，上限 " + limit + "），可用 opts.maxBytes 调整或改用 ok.download");
        }
        Object cs = opts == null ? null : opts.get("charset");
        Charset charset;
        if ("bytes".equals(rt)) {
            // P1-3：返回的 String 是"字节按 ISO-8859-1 一一映射"的结果。
            // Lua 侧必须用 string.byte / string.char 逐字节还原，不能当 UTF-8 文本处理。
            charset = ISO_8859_1;
        } else if (cs != null) {
            charset = Charset.forName(String.valueOf(cs));
        } else {
            // 跟随响应头里的 charset；没有就 UTF-8（原 b.string() 的行为）
            MediaType mt = b.contentType();
            Charset declared = mt == null ? null : mt.charset();
            charset = declared == null ? Charset.forName("UTF-8") : declared;
        }
        // 边读边计数：chunked（contentLength = -1）时也能拦住超限，避免整体 OOM
        // P3-8：len <= limit <= 64MB，这里强转 int 安全；chunked（-1）时用默认容量
        java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream(
                len > 0 ? (int) len : 8192);
        InputStream in = b.byteStream();
        byte[] buf = new byte[8192];
        long total = 0;
        int n;
        while ((n = in.read(buf)) != -1) {
            total += n;
            if (total > limit) {
                throw new IOException("响应体过大（已读 " + total + " 字节，上限 " + limit + "），可用 opts.maxBytes 调整或改用 ok.download");
            }
            bos.write(buf, 0, n);
        }
        return new String(bos.toByteArray(), charset);
    }

    /**
     * 执行一次请求（含重试），结果交给 sink。返回可取消句柄。
     *
     * <p>契约：同步失败（url 为空、构造失败）返回 null，**但会同步调用一次 sink** 告知错误；
     * all() 依赖这一点（先填 slots 再 left--），勿改成静默失败不调 sink。
     */
    private static Handle exec(final LuaTable opts, final Sink sink) {
        final String tag = UUID.randomUUID().toString().substring(0, 8);
        String method = str(opts, "method", "GET").toUpperCase();
        final String url = str(opts, "url", "").trim();
        if (url.isEmpty()) {
            sink.done(null, null, "url 不能为空", false);
            return null;
        }
        Object rv = opts.get("retries");
        final int retries = rv instanceof Number ? Math.max(0, ((Number) rv).intValue()) : 0;
        final boolean idempotent = "GET".equals(method) || "HEAD".equals(method);

        Call call;
        try {
            final Request req = buildRequest(opts, method, url, tag);
            Object to = opts.get("timeout");
            call = clientFor(to instanceof Number ? ((Number) to).intValue() : 0, false).newCall(req);
            if (DEBUG) {
                log(null, "info", tag + " → " + req.method() + " " + req.url());
            }
        } catch (Exception e) {
            sink.done(null, null, "请求构造失败：" + msg(e), false);
            return null;
        }

        final Handle handle = new Handle();
        handle.set(call);                       // [3] 必须在 enqueue 之前，否则同步回调时 cancel 扑空
        if (!idempotent && retries > 0) {
            emitLog(null, "error", tag + " " + method + " 非幂等，retries 被忽略");  // [4]
        }
        final int[] left = {idempotent ? retries : 0};
        enqueue(call, opts, tag, sink, left, handle);
        return handle;
    }

    private static void enqueue(final Call call, final LuaTable opts, final String tag,
                                final Sink sink, final int[] left, final Handle handle) {
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                if (c.isCanceled()) {
                    sink.done(null, null, "已取消", true);
                    return;
                }
                if (left[0] > 0) {
                    left[0]--;
                    log(null, "info", tag + " 重试中（剩 " + left[0] + " 次）：" + msg(e));
                    try {
                        Object to = opts.get("timeout");
                        // P3-8：重试复用原 Request，仅适用于可重放 body（FormBody / 字符串）。
                        // 若将来支持一次性流式 body，必须在此重建 request 或禁止重试。
                        Call again = clientFor(to instanceof Number ? ((Number) to).intValue() : 0, false)
                                .newCall(c.request());
                        handle.set(again);          // 取消转发到重试后的 Call
                        enqueue(again, opts, tag, sink, left, handle);
                        return;
                    } catch (Exception ignored) {
                    }
                }
                sink.done(null, null, "网络错误：" + msg(e), false);
            }

            @Override
            public void onResponse(Call c, Response response) {
                String text;
                try {
                    text = readBody(response, opts);
                } catch (IOException e) {
                    response.close();
                    sink.done(null, null, "读取响应失败：" + msg(e), false);
                    return;
                }
                if (DEBUG) {
                    log(null, "info", tag + " ← " + response.code() + " " + response.request().url());
                }
                // #1：快照后立即关闭，连接不等 Lua 回调
                Snapshot snap = new Snapshot(response.code(), response.headers());
                response.close();
                sink.done(snap, text, null, false);
            }
        });
    }

    /**
     * 发起一次异步请求，返回可取消的 Call。
     * opts：method / url / query / headers / form / body / contentType / json / timeout /
     *       retries / responseType / charset
     */
    public static Handle request(LuaTable opts, final LuaObject callback) {
        if (opts == null || callback == null) {
            throw new IllegalArgumentException("okhttp.request(opts, callback)：两个参数都必填");
        }
        return exec(opts, new Sink() {
            @Override
            public void done(Snapshot snapshot, String body, String error, boolean canceled) {
                deliver(callback, snapshot, body, error, canceled);
            }
        });
    }

    /** [12] 并发执行多个请求，全部结束后按序回调：cb({ {ok,...}, {ok,...} })。 */
    public static Handle all(LuaTable reqs, final LuaObject callback) {
        if (reqs == null || callback == null) {
            throw new IllegalArgumentException("okhttp.all(reqs, callback)：两个参数都必填");
        }
        // [6] 返回聚合句柄：ok.cancel(group) 可一次性取消所有子请求
        final List<Handle> children = new ArrayList<Handle>();
        final Handle group = new Handle() {
            @Override
            public void cancel() {
                synchronized (children) {
                    for (Handle h : children) {
                        h.cancel();
                    }
                }
            }
        };
        final int n = reqs.length();
        final Result[] slots = new Result[n + 1];
        final AtomicInteger left = new AtomicInteger(n);
        if (n == 0) {
            deliverAll(callback, slots, 0);
            return group;
        }
        for (int i = 1; i <= n; i++) {
            final Object item = reqs.get((double) i);
            if (!(item instanceof LuaTable)) {
                Result bad = new Result();
                bad.error = "参数不是表";
                slots[i] = bad;
                if (left.decrementAndGet() == 0) {
                    deliverAll(callback, slots, n);
                }
                continue;
            }
            final int idx = i;
            Handle child = exec((LuaTable) item, new Sink() {
                @Override
                public void done(Snapshot snapshot, String body, String error, boolean canceled) {
                    Result r = new Result();
                    if (snapshot == null) {
                        r.error = error;
                        r.canceled = canceled;
                    } else {
                        r.ok = true;
                        r.code = snapshot.code;
                        r.body = body;
                    }
                    slots[idx] = r;
                    if (left.decrementAndGet() == 0) {
                        deliverAll(callback, slots, n);
                        // [3] 全部结束后释放子句柄（之后 group.cancel 变成 no-op），避免长期持有 Call
                        synchronized (children) {
                            children.clear();
                        }
                    }
                }
            });
            // P2-6：child == null 是正常路径——exec 同步失败时会**同步调用过 sink**
            // （slots[idx] 已填、left 已减），这里不加入 children 是正确的
            if (child != null) {
                synchronized (children) {
                    children.add(child);
                }
            }
        }
        return group;
    }

    private static void deliverAll(final LuaObject callback, final Result[] slots, final int n) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    final LuaState L = callback.getLuaState();
                    LuaTable<Object, Object> out = new LuaTable<Object, Object>(L);
                    for (int i = 1; i <= n; i++) {
                        LuaTable<Object, Object> one = new LuaTable<Object, Object>(L);
                        Result r = slots[i];
                        if (r == null) {
                            one.put("ok", Boolean.FALSE);
                            one.put("error", "无结果");
                        } else if (r.ok) {
                            one.put("ok", Boolean.TRUE);
                            one.put("code", (double) r.code);
                            one.put("body", r.body == null ? "" : r.body);
                        } else {
                            one.put("ok", Boolean.FALSE);
                            one.put("error", r.error);
                            if (r.canceled) {
                                one.put("canceled", Boolean.TRUE);
                            }
                        }
                        out.put((double) i, one);
                    }
                    callback.call(out);
                } catch (Exception e) {
                    reportCallbackError(callback, e);
                }
            }
        });
    }

    /** [09] 断点续传下载：[04] 用 readTimeout 作为"多久没收到数据"的上限。 */
    public static Handle download(String url, String path, LuaObject callback) {
        return download(url, path, callback, 0, null, false);
    }

    public static Handle download(String url, String path, LuaObject callback, int timeoutMs, LuaObject onProgress) {
        return download(url, path, callback, timeoutMs, onProgress, false);
    }

    public static Handle download(final String url, final String path, final LuaObject callback,
                                  int timeoutMs, final LuaObject onProgress, boolean resume) {
        if (url == null || path == null || callback == null) {
            throw new IllegalArgumentException("okhttp.download(url, path, callback)：参数必填");
        }
        final File target = new File(path);
        // [2] 不论是否续传都写 .part，成功才改名：避免中途失败把已有的完整文件截断损坏
        final File out = new File(path + ".part");
        final long offset = (resume && out.isFile()) ? out.length() : 0;
        Request.Builder rb;
        try {
            HttpUrl u = HttpUrl.parse(url);     // P2-4：只解析一次
            if (u == null) {
                deliver(callback, null, null, "url 非法：" + url, false);
                return null;
            }
            rb = new Request.Builder().url(u);
        } catch (Exception e) {
            deliver(callback, null, null, "url 非法：" + msg(e), false);
            return null;
        }
        if (offset > 0) {
            rb.header("Range", "bytes=" + offset + "-");
        }
        final Call call;
        try {
            call = clientFor(timeoutMs, true).newCall(rb.build());
        } catch (Exception e) {
            deliver(callback, null, null, "请求构造失败：" + msg(e), false);
            return null;
        }
        Handle handle = new Handle();
        handle.set(call);                       // [3] 先于 enqueue
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                deliver(callback, null, null, c.isCanceled() ? "已取消" : "网络错误：" + msg(e), c.isCanceled());
            }

            @Override
            public void onResponse(Call c, Response response) {
                boolean appending = offset > 0 && response.code() == 206;
                if (appending) {
                    String cr = response.header("Content-Range");
                    if (cr == null || !cr.startsWith("bytes " + offset + "-")) {
                        log(null, "info", "Content-Range 与本地 offset 不符（" + cr + "），改为重新下载");
                        appending = false;
                    }
                }
                if (offset > 0 && response.code() != 206) {
                    log(null, "info", "服务端不支持 Range（返回 " + response.code() + "），改为重新下载");  // [5]
                }
                if (!response.isSuccessful() && response.code() != 206) {
                    int code = response.code();
                    response.close();               // P0-1：不关会泄漏连接
                    deliver(callback, null, null, "HTTP " + code, false);
                    return;
                }
                File parent = out.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    deliver(callback, null, null, "无法创建目录：" + parent, false);
                    return;
                }
                final long base = appending ? offset : 0;   // P2-9
                // P2-5：gate 与本次 onResponse 生命周期绑定（download 目前无重试，
                // 若将来给 download 加重试，需把 gate 提到方法外层复用）
                final ProgressGate gate = new ProgressGate();
                long total = base;
                long lastPost = 0;
                final ResponseBody rb0 = response.body();       // #6：只取一次
                long expected = rb0 == null ? -1 : rb0.contentLength();
                if (expected > 0) {
                    expected += base;
                }
                try (ResponseBody b = rb0;
                     InputStream in = b == null ? null : b.byteStream();
                     OutputStream os = new FileOutputStream(out, appending)) {
                    if (in == null) {
                        out.delete();       // P2-13
                        deliver(callback, null, null, "响应体为空", false);
                        return;
                    }
                    byte[] buf = new byte[16 * 1024];
                    int n;
                    while ((n = in.read(buf)) != -1) {
                        if (c.isCanceled()) {
                            // P1-1：非续传时删掉半截文件；续传保留 .part 供下次接着下
                            if (!appending) {     // P2-8：重新下载时保留 .part 是脏数据
                                out.delete();
                            }
                            deliver(callback, null, null, "已取消", true);
                            return;
                        }
                        os.write(buf, 0, n);
                        total += n;
                        long now = System.currentTimeMillis();
                        if (onProgress != null && now - lastPost >= 250
                                && gate.pending.compareAndSet(false, true)) {
                            lastPost = now;
                            reportProgress(onProgress, total, expected, gate);
                        }
                    }
                    // P1-1：收尾进度走与主循环相同的串行通道——CAS 到就投递，没 CAS 到
                    // 说明上一帧回调还在主线程排队，不再补发（避免两帧乱序）。
                    if (onProgress != null && gate.pending.compareAndSet(false, true)) {
                        reportProgress(onProgress, total, expected, gate);
                    }
                } catch (IOException e) {
                    deliver(callback, null, null, "写入失败：" + msg(e), false);
                    return;
                }
                if (target.exists() && !target.delete()) {
                    deliver(callback, null, null, "覆盖目标文件失败：" + target, false);
                    return;
                }
                if (!out.renameTo(target)) {
                    deliver(callback, null, null, "改名失败：" + out + " → " + target, false);
                    return;
                }
                deliverDownload(callback, target.getAbsolutePath(), total, null);
            }
        });
        return handle;
    }

    /** WebSocket 句柄：send / sendBinary / close / cancel / readyState。 */
    public static final class WsHandle {
        private volatile WebSocket ws;
        private volatile String state = "connecting";

        private volatile String url;
        private volatile LuaTable<?, ?> handlers;
        private volatile boolean reconnect;
        private volatile int reconnectDelay = 2000;
        private volatile int maxReconnectDelay = 30000;
        private volatile int maxReconnectAttempts = 10;  // [4] 0 = 不限，默认 10 次
        private volatile int pingIntervalSec;
        private volatile int connectTimeoutSec;
        private volatile int attempt;
        volatile boolean manualClose;

        /** 文本帧。P3-11：返回 false 只代表"未连接或队列拒收"，用 readyState() 区分原因。 */
        public boolean send(String text) {
            WebSocket w = ws;
            return w != null && w.send(text == null ? "" : text);
        }

        /**
         * [M1] 发送二进制帧。
         *
         * <p>data 必须是**原始字节串**（Lua 侧用 string.char 构造）；含 >0xFF 的文本
         * （如中文）经 ISO-8859-1 会变成 '?' 且静默损坏——文本请用 {@link #send(String)}。
         *
         * <p>返回 false 只代表未连接或队列拒收，用 {@link #readyState()} 区分原因。
         */
        public boolean sendBinary(String data) {
            WebSocket w = ws;
            if (w == null) {
                return false;
            }
            byte[] bytes = (data == null ? "" : data).getBytes(ISO_8859_1);
            return w.send(okio.ByteString.of(bytes));
        }

        public void close() {
            close(1000.0, "");
        }

        /** [M5] 自定义关闭码（Lua 传的是 double）。 */
        public void close(double code, String reason) {
            manualClose = true;                     // 主动关闭不触发重连
            state = "closing";
            int c = (int) code;
            if (c < 1000 || c > 4999) {
                c = 1000;                           // P1-6：非法关闭码归一
            }
            WebSocket w = ws;
            if (w == null) {
                state = "closed";       // #3：连接还没建立，不会有 onClosed，别让 readyState 卡在 closing
                return;
            }
            try {
                w.close(c, reason == null ? "" : reason);
            } catch (Exception e) {
                wsEmit(handlers, "onFailure", "close 失败：" + msg(e), -1.0);
            }
        }

        public void cancel() {
            manualClose = true;
            WebSocket w = ws;
            if (w != null) {
                w.cancel();
            }
        }

        /** [M3] 连接状态：connecting / open / closing / closed。 */
        public String readyState() {
            return state;
        }

        void set(WebSocket w) {
            ws = w;
        }
    }

    /**
     * 建立 WebSocket 连接（ws / wss）。
     *
     * <p>handlers：headers / onOpen / onMessage / onClose / onFailure /
     * reconnect / reconnectDelay / maxReconnectDelay / pingInterval / connectTimeout
     */
    public static WsHandle ws(String url, LuaTable handlers) {
        if (url == null || url.trim().isEmpty()) {
            throw new IllegalArgumentException("okhttp.ws(url, handlers)：url 必填");
        }
        HttpUrl u = HttpUrl.parse(url.trim());
        if (u == null) {
            throw new IllegalArgumentException("okhttp.ws: url 非法：" + url);
        }
        WsHandle handle = new WsHandle();
        handle.url = u.toString();
        handle.handlers = handlers;
        if (handlers != null) {
            handle.reconnect = bool(handlers, "reconnect", false);
            Object d = handlers.get("reconnectDelay");
            if (d instanceof Number) {
                handle.reconnectDelay = Math.max(200, ((Number) d).intValue());
            }
            Object md = handlers.get("maxReconnectDelay");
            if (md instanceof Number) {
                handle.maxReconnectDelay = Math.max(handle.reconnectDelay, ((Number) md).intValue());
            }
            Object ma = handlers.get("maxReconnectAttempts");
            if (ma instanceof Number) {
                handle.maxReconnectAttempts = Math.max(0, ((Number) ma).intValue());
            }
            Object ping = handlers.get("pingInterval");
            if (ping instanceof Number) {
                handle.pingIntervalSec = ((Number) ping).intValue();
            }
            Object ct = handlers.get("connectTimeout");
            if (ct instanceof Number) {
                handle.connectTimeoutSec = ((Number) ct).intValue();
            }
        }
        dial(handle);
        return handle;
    }

    private static boolean bool(LuaTable<?, ?> t, String key, boolean def) {
        Object v = t == null ? null : t.get(key);
        if (v == null) {
            return def;
        }
        if (v instanceof Boolean) {
            return (Boolean) v;
        }
        return Boolean.parseBoolean(String.valueOf(v));
    }

    private static void dial(final WsHandle handle) {
        Request.Builder rb;
        try {
            rb = new Request.Builder().url(HttpUrl.parse(handle.url));
        } catch (Exception e) {
            wsEmit(handle.handlers, "onFailure", "url 非法：" + msg(e), -1.0);
            return;
        }
        Object hs = handle.handlers == null ? null : handle.handlers.get("headers");
        if (hs instanceof LuaTable) {
            for (Object o : ((LuaTable<?, ?>) hs).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    rb.header(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }
        OkHttpClient client = CLIENT;
        if (handle.pingIntervalSec > 0 || handle.connectTimeoutSec > 0) {
            OkHttpClient.Builder cb = CLIENT.newBuilder();
            if (handle.pingIntervalSec > 0) {
                cb.pingInterval(handle.pingIntervalSec, TimeUnit.SECONDS);   // [M4]
            }
            if (handle.connectTimeoutSec > 0) {
                cb.connectTimeout(handle.connectTimeoutSec, TimeUnit.SECONDS);  // [M6]
            }
            client = cb.build();
        }
        handle.state = "connecting";
        final LuaTable<?, ?> h = handle.handlers;
        WebSocket ws;
        try {
            ws = client.newWebSocket(rb.build(), new WebSocketListener() {
            @Override
            public void onOpen(WebSocket webSocket, Response response) {
                handle.attempt = 0;
                handle.state = "open";
                // P0-2：wsEmit 异步投递，裸 Response 到回调执行时可能已失效，只传快照
                LuaTable<Object, Object> info = null;
                try {
                    // P1-3：优先从 onOpen 这个 Lua 函数本身取状态，比从表上取更可靠
                    Object fn0 = h == null ? null : h.get("onOpen");
                    LuaState L0 = fn0 instanceof LuaObject
                            ? ((LuaObject) fn0).getLuaState()
                            : (h == null ? null : h.getLuaState());
                    if (L0 != null) {
                        info = new LuaTable<Object, Object>(L0);
                        info.put("code", (double) response.code());
                        LuaTable<String, Object> h1 = new LuaTable<String, Object>(L0);
                        LuaTable<Object, Object> h2 = new LuaTable<Object, Object>(L0);
                        for (String name : response.headers().names()) {
                            List<String> vs = response.headers(name);
                            String v0 = vs.isEmpty() ? "" : vs.get(0);
                            h1.put(name, v0);
                            h1.put(name.toLowerCase(), v0);      // P3-7：与 deliver 一致
                            LuaTable<Object, Object> list = new LuaTable<Object, Object>(L0);
                            for (int i = 0; i < vs.size(); i++) {
                                list.put((double) (i + 1), vs.get(i));
                            }
                            h2.put(name, list);
                            h2.put(name.toLowerCase(), list);
                        }
                        info.put("headers", h1);
                        info.put("headersAll", h2);
                    }
                } catch (Exception ignored) {
                }
                wsEmit(h, "onOpen", info);
            }

            @Override
            public void onMessage(WebSocket webSocket, String text) {
                wsEmit(h, "onMessage", text, Boolean.FALSE);      // [B2] 文本
            }

            @Override
            public void onMessage(WebSocket webSocket, okio.ByteString bytes) {
                // [B2] 二进制：ISO-8859-1 无损转成 Lua 字节串，第二个参数为 true
                byte[] raw = bytes == null ? new byte[0] : bytes.toByteArray();
                wsEmit(h, "onMessage", new String(raw, ISO_8859_1), Boolean.TRUE);
            }

            @Override
            public void onClosing(WebSocket webSocket, int code, String reason) {
                // [B1] 对端要关：回 close frame，真正回调在 onClosed
                handle.state = "closing";
                webSocket.close(code, reason == null ? "" : reason);
            }

            @Override
            public void onClosed(WebSocket webSocket, int code, String reason) {
                // [B1] 握手完成才通知 Lua（本端主动 close 也走这里）
                handle.state = "closed";
                wsEmit(h, "onClose", (double) code, reason == null ? "" : reason);
                maybeReconnect(handle);
            }

            @Override
            public void onFailure(WebSocket webSocket, Throwable t, Response response) {
                handle.state = "closed";
                int code = -1;
                if (response != null) {
                    code = response.code();
                    response.close();                            // [R2] 握手失败也不泄漏连接
                }
                wsEmit(h, "onFailure", msg(t), (double) code);   // [R1] 带上 HTTP 状态码
                maybeReconnect(handle);
            }
            });
        } catch (Exception e) {
            // [1] client 已关闭 / 内部异常：不能让异常冒到 Lua 调用方或主线程 Runnable
            handle.state = "closed";
            wsEmit(handle.handlers, "onFailure", "建立连接失败：" + msg(e), -1.0);
            maybeReconnect(handle);
            return;
        }
        handle.set(ws);
    }

    /** 把 WebSocket 事件投递到主线程再调 Lua（args 可为 null 占位，Lua 侧收到 nil）。 */
    private static void wsEmit(final LuaTable<?, ?> handlers, final String name, final Object... args) {
        if (handlers == null) {
            // [2] 没给 handlers 时也不静默：至少让失败在控制台可见
            if ("onFailure".equals(name) && args.length > 0) {
                Log.e("okhttp", "WebSocket 失败（未提供 handlers）：" + args[0]);
            }
            return;
        }
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    Object fn = handlers.get(name);
                    if (fn instanceof LuaObject) {
                        ((LuaObject) fn).call(args);
                    }
                } catch (Exception e) {
                    emitLog(null, "error", "WebSocket 回调 " + name + " 出错：" + msg(e));
                }
            }
        });
    }

    /** [M2] 非主动关闭时按指数退避重连。 */
    private static void maybeReconnect(final WsHandle handle) {
        if (!handle.reconnect || handle.manualClose) {
            return;
        }
        // [4] 次数上限：到了就停并通知 onGiveUp
        if (handle.maxReconnectAttempts > 0 && handle.attempt >= handle.maxReconnectAttempts) {
            wsEmit(handle.handlers, "onGiveUp", (double) handle.attempt);
            return;
        }
        final int delay = Math.min(handle.maxReconnectDelay,
                handle.reconnectDelay * (1 << Math.min(handle.attempt, 6)));
        handle.attempt++;
        wsEmit(handle.handlers, "onReconnect", (double) delay);
        MAIN.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!handle.manualClose) {
                    dial(handle);
                }
            }
        }, delay);
    }

    /** 单文件上传（multipart）。 */
    public static Handle upload(String url, String field, String filePath, LuaObject callback) {
        return upload(url, field, filePath, callback, 0);
    }

    public static Handle upload(final String url, final String field, final String filePath,
                                final LuaObject callback, final int timeoutMs) {
        if (url == null || filePath == null || callback == null) {
            throw new IllegalArgumentException("okhttp.upload(url, field, filePath, callback)：参数必填");
        }
        File f = new File(filePath);
        if (!f.isFile()) {
            deliver(callback, null, null, "文件不存在：" + filePath, false);
            return null;
        }
        MultipartBody body = new MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(field == null || field.isEmpty() ? "file" : field, f.getName(),
                        RequestBody.create(mimeOf(f.getPath()), f))
                .build();
        return postMultipart(url, body, timeoutMs, callback);
    }

    /** [10] 多文件 + 普通字段上传：files = { {field=,path=}, ... }，fields = { k=v }。 */
    public static Handle uploadMany(String url, LuaTable files, LuaTable fields, LuaObject callback) {
        if (url == null || callback == null) {
            throw new IllegalArgumentException("okhttp.uploadMany(url, files, fields, callback)：参数必填");
        }
        MultipartBody.Builder mb = new MultipartBody.Builder().setType(MultipartBody.FORM);
        if (files != null) {
            int n = files.length();
            for (int i = 1; i <= n; i++) {
                Object item = files.get((double) i);
                if (!(item instanceof LuaTable)) {
                    continue;
                }
                LuaTable<?, ?> f = (LuaTable<?, ?>) item;
                String p = str(f, "path", "");
                File file = new File(p);
                if (!file.isFile()) {
                    deliver(callback, null, null, "文件不存在：" + p, false);
                    return null;
                }
                String name = str(f, "field", "file");
                mb.addFormDataPart(name, file.getName(), RequestBody.create(mimeOf(file.getPath()), file));
            }
        }
        if (fields != null) {
            for (Object o : fields.entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    mb.addFormDataPart(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }
        return postMultipart(url, mb.build(), 0, callback);
    }

    private static Handle postMultipart(String url, RequestBody body, final int timeoutMs, final LuaObject callback) {
        final Call call;
        try {
            call = clientFor(timeoutMs, false).newCall(new Request.Builder().url(url).post(body).build());
        } catch (Exception e) {
            deliver(callback, null, null, "请求构造失败：" + msg(e), false);
            return null;
        }
        Handle handle = new Handle();
        handle.set(call);                       // [3] 先于 enqueue
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                deliver(callback, null, null, c.isCanceled() ? "已取消" : "网络错误：" + msg(e), c.isCanceled());
            }

            @Override
            public void onResponse(Call c, Response response) {
                String text;
                try {
                    text = readBody(response, null);
                } catch (IOException e) {
                    response.close();
                    deliver(callback, null, null, "读取响应失败：" + msg(e), false);
                    return;
                }
                // #1：先快照再关闭，Lua 回调里不再持有 Response
                Snapshot snap = new Snapshot(response.code(), response.headers());
                response.close();
                deliver(callback, snap, text, null, false);
            }
        });
        return handle;
    }

    // ---------- 工具 ----------
    /** P2-1：按扩展名推断上传用的 MediaType。 */
    private static MediaType mimeOf(String path) {
        String p = path == null ? "" : path.toLowerCase();
        int dot = p.lastIndexOf('.');
        String ext = dot < 0 ? "" : p.substring(dot + 1);
        switch (ext) {
            case "jpg":
            case "jpeg":
                return MediaType.parse("image/jpeg");
            case "png":
                return MediaType.parse("image/png");
            case "gif":
                return MediaType.parse("image/gif");
            case "webp":
                return MediaType.parse("image/webp");
            case "txt":
                return MediaType.parse("text/plain; charset=utf-8");
            case "json":
                return MediaType.parse("application/json; charset=utf-8");
            case "html":
            case "htm":
                return MediaType.parse("text/html; charset=utf-8");
            case "mp4":
                return MediaType.parse("video/mp4");
            case "mp3":
                return MediaType.parse("audio/mpeg");
            default:
                return OCTET;
        }
    }

    private static String str(LuaTable<?, ?> t, String key, String def) {
        if (t == null) {
            return def;
        }
        Object v = t.get(key);
        return v == null ? def : String.valueOf(v);
    }

    private static String msg(Throwable e) {
        if (e == null) {
            return "未知错误";
        }
        String m = e.getMessage();
        return m == null || m.isEmpty() ? e.getClass().getSimpleName() : m;
    }

    private static void log(LuaObject cb, String level, String message) {
        emitLog(cb, level, message);
    }

    /** error 级始终输出；info 级受 DEBUG 控制。logger 抛异常直接吞掉（避免 log 里再 log）。 */
    private static void emitLog(final LuaObject cb, final String level, final String message) {
        if (!DEBUG && !"error".equals(level)) {
            return;
        }
        final LuaObject logger = LOGGER;
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    if (logger != null && logger.isFunction()) {
                        logger.call(level, message);
                        return;
                    }
                    LuaState L = cb == null ? null : cb.getLuaState();
                    if (L != null) {
                        LuaObject print = L.getLuaObject("print");
                        if (print != null && print.isFunction()) {
                            print.call("[okhttp] " + message);
                            return;
                        }
                    }
                    // P3-1：既没有 logger 也拿不到 Lua 状态时，退回控制台
                    Log.e("okhttp", message);
                } catch (Exception ignored) {
                }
            }
        });
    }

    private static void reportProgress(final LuaObject onProgress, final long received, final long total,
                                       final ProgressGate gate) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    onProgress.call((double) received, (double) total);
                } catch (Exception e) {
                    emitLog(null, "error", "进度回调出错：" + msg(e));   // P3-3
                } finally {
                    // P3-11：gate 可为 null（表示"不做节流"的调用方），当前唯一调用方都传非 null
                    if (gate != null) {
                        gate.pending.set(false);                        // 放行本下载的下一次
                    }
                }
            }
        });
    }

    /** 回到主线程调用 Lua；response 为 null 表示失败。 */
    private static void deliver(final LuaObject callback, final Snapshot snapshot,
                                final String body, final String error, final boolean canceled) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    final LuaState L = callback.getLuaState();
                    LuaTable<String, Object> t = new LuaTable<String, Object>(L);
                    if (snapshot == null) {
                        t.put("ok", Boolean.FALSE);
                        t.put("error", error);
                        if (canceled) {
                            t.put("canceled", Boolean.TRUE);
                        }
                    } else {
                        t.put("ok", Boolean.TRUE);
                        t.put("code", (double) snapshot.code);
                        t.put("body", body == null ? "" : body);
                        LuaTable<String, Object> h = new LuaTable<String, Object>(L);
                        LuaTable<Object, Object> all = new LuaTable<Object, Object>(L);
                        for (String name : snapshot.headers.names()) {
                            List<String> values = snapshot.headers.values(name);
                            String v0 = values.isEmpty() ? "" : values.get(0);
                            h.put(name, v0);
                            h.put(name.toLowerCase(), v0);
                            LuaTable<Object, Object> list = new LuaTable<Object, Object>(L);
                            for (int i = 0; i < values.size(); i++) {
                                list.put((double) (i + 1), values.get(i));
                            }
                            all.put(name, list);
                            all.put(name.toLowerCase(), list);
                        }
                        t.put("headers", h);
                        t.put("headersAll", all);
                    }
                    callback.call(t);
                } catch (Exception e) {
                    reportCallbackError(callback, e);
                }
            }
        });
    }

    private static void deliverDownload(final LuaObject callback, final String path,
                                        final long size, final String error) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    LuaTable<String, Object> t = new LuaTable<String, Object>(callback.getLuaState());
                    t.put("ok", error == null ? Boolean.TRUE : Boolean.FALSE);
                    if (error == null) {
                        t.put("path", path);
                        t.put("size", (double) size);
                    } else {
                        t.put("error", error);
                    }
                    callback.call(t);
                } catch (Exception e) {
                    reportCallbackError(callback, e);
                }
            }
        });
    }

    private static void reportCallbackError(LuaObject cb, Exception e) {
        Log.e("okhttp", "回调执行出错", e);
        emitLog(cb, "error", "回调执行出错：" + msg(e));
    }
}
