package com.androlua.net;

import android.os.Handler;
import android.os.Looper;

import com.luajava.LuaObject;
import com.luajava.LuaState;
import com.luajava.LuaTable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Cookie;
import okhttp3.CookieJar;
import okhttp3.FormBody;
import okhttp3.Dispatcher;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.MultipartBody;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * OkHttp 的 Lua 门面，Lua 侧见 resources/lua/okhttp.lua。
 *
 * <p>设计要点：
 * <ul>
 *   <li>请求在 OkHttp 线程池执行，**回调统一 post 回主线程**再调 Lua——Lua 状态只在主线程用。</li>
 *   <li>{@link #request} 返回 {@link Call}，Lua 侧可调 {@code ok.cancel(call)} 中止在途请求；
 *       被取消的请求回调会带 {@code canceled=true}，不再误打失效页面。</li>
 *   <li>自带内存 CookieJar（按 host 累积），同一进程内跨请求保持登录态。</li>
 *   <li>附带 {@link #download} 流式下载（不把响应体整体读进内存）与 {@link #upload} 分片上传。</li>
 * </ul>
 *
 * <p>结果表：{ ok, code, body, headers, headersAll, canceled, error }
 */
public final class LuaOkHttp {

    private static final MediaType TEXT = MediaType.parse("text/plain; charset=utf-8");
    private static final MediaType OCTET = MediaType.parse("application/octet-stream");

    /** 响应体超过这个大小就不再整体入内存（走 download 或自行分片）。 */
    private static final long MAX_IN_MEMORY = 8L * 1024 * 1024;

    private static volatile boolean DEBUG = false;

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    /** 内存 CookieJar：按 host 累积，满足登录态类接口的基本需求。 */
    private static final Map<String, List<Cookie>> COOKIE_STORE = new ConcurrentHashMap<String, List<Cookie>>();
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

    private static final OkHttpClient BASE = new OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .followRedirects(true)
            .cookieJar(JAR)
            .build();

    static {
        Dispatcher d = BASE.dispatcher();
        d.setMaxRequests(64);
        d.setMaxRequestsPerHost(8);
    }

    private LuaOkHttp() {
    }

    /** 打开/关闭请求日志（打到 Lua 控制台）。 */
    public static void setDebug(boolean on) {
        DEBUG = on;
    }

    /** 清空内存 Cookie。 */
    public static void clearCookies() {
        COOKIE_STORE.clear();
    }

    /**
     * 发起一次异步请求，返回可取消的 Call。
     *
     * @param opts     Lua 表：method / url / headers / body / contentType / timeout(毫秒)
     * @param callback Lua 函数，参数是结果表
     */
    public static Call request(LuaTable opts, final LuaObject callback) {
        if (opts == null || callback == null) {
            throw new IllegalArgumentException("okhttp.request(opts, callback)：两个参数都必填");
        }
        final String method = str(opts, "method", "GET").toUpperCase();
        final String url = str(opts, "url", "").trim();
        if (url.isEmpty()) {
            deliver(callback, null, "url 不能为空", false);
            return null;
        }

        // [01] query：opts.query = { a = "1", b = { "x", "y" } } → 自动 URL 编码；
        //      值是数组时同名参数重复添加
        String finalUrl;
        try {
            HttpUrl parsed = HttpUrl.parse(url);
            if (parsed == null) {
                deliver(callback, null, "url 非法：" + url, false);
                return null;
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
            finalUrl = ub.build().toString();
        } catch (Exception e) {
            deliver(callback, null, "url 非法：" + msg(e), false);
            return null;
        }
        Request.Builder rb = new Request.Builder().url(finalUrl);

        Object hs = opts.get("headers");
        if (hs instanceof LuaTable) {
            for (Object o : ((LuaTable<?, ?>) hs).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    rb.header(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }

        // [02] form：x-www-form-urlencoded；给了 form 且没显式写 method 时默认 POST
        String realMethod = method;
        String bodyText = str(opts, "body", "");
        RequestBody body = null;
        Object form = opts.get("form");
        if (form instanceof LuaTable) {
            FormBody.Builder fb = new FormBody.Builder();
            for (Object o : ((LuaTable<?, ?>) form).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    fb.add(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
            body = fb.build();
            if (opts.get("method") == null) {
                realMethod = "POST";
            }
            bodyText = "";
        } else if (!"GET".equals(method) && !"HEAD".equals(method) && !bodyText.isEmpty()) {
            // GET/HEAD 不能带 body（OkHttp 会抛），其余方法按需带
            String ct = str(opts, "contentType", "text/plain; charset=utf-8");
            MediaType media = MediaType.parse(ct);
            body = RequestBody.create(media == null ? TEXT : media, bodyText);
        }
        rb.method(realMethod, body);
        log(callback, "→ " + realMethod + " " + finalUrl + (bodyText.isEmpty() ? "" : " body=" + bodyText));

        Object to = opts.get("timeout");
        OkHttpClient client = clientFor(to instanceof Number ? ((Number) to).intValue() : 0);

        final Call call;
        try {
            call = client.newCall(rb.build());
        } catch (Exception e) {
            // 非法 method 等：统一走结果表，不把异常抛给 Lua 调用方
            deliver(callback, null, "请求构造失败：" + msg(e), false);
            return null;
        }
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                boolean canceled = c.isCanceled();
                deliver(callback, null, canceled ? "已取消" : "网络错误：" + msg(e), canceled);
            }

            @Override
            public void onResponse(Call c, Response response) {
                String text = "";
                try (ResponseBody b = response.body()) {
                    if (b != null) {
                        long len = b.contentLength();
                        if (len > MAX_IN_MEMORY) {
                            deliver(callback, null,
                                    "响应体过大（" + len + " 字节，上限 " + MAX_IN_MEMORY + "），请用 ok.download 或分片接口",
                                    false);
                            return;
                        }
                        // [11] responseType：text(默认) / bytes / json；也可用 charset 覆盖解码
                        String rt = str(opts, "responseType", "text").toLowerCase();
                        Object cs = opts.get("charset");
                        if ("bytes".equals(rt)) {
                            // Lua 字符串是字节串，用 ISO-8859-1 无损搬运
                            text = new String(b.bytes(), Charset.forName("ISO-8859-1"));
                        } else if (cs != null) {
                            text = new String(b.bytes(), Charset.forName(String.valueOf(cs)));
                        } else {
                            text = b.string();
                        }
                    }
                } catch (IOException e) {
                    deliver(callback, null, "读取响应失败：" + msg(e), false);
                    return;
                }
                log(callback, "← " + response.code() + " " + response.request().url());
                deliver(callback, response, text, false);
            }
        });
        return call;
    }

    /** 流式下载（默认超时、无进度回调）。 */
    public static Call download(String url, String path, LuaObject callback) {
        return download(url, path, callback, 0, null);
    }

    /**
     * 流式下载到本地文件（不整体入内存）。回调结果：{ ok, path, size, error }
     *
     * @param timeoutMs  可选总超时（毫秒）；大文件建议用 readTimeout 语义，这里用 callTimeout，
     *                   传 0 表示用默认（10s 连接 / 20s 读）
     * @param onProgress 可选的进度回调，收到 (已收字节, 总字节)；总字节未知时为 -1，约 250ms 一次
     */
    public static Call download(final String url, final String path, final LuaObject callback,
                                int timeoutMs, final LuaObject onProgress) {
        if (url == null || path == null || callback == null) {
            throw new IllegalArgumentException("okhttp.download(url, path, callback)：参数必填");
        }
        final Call call;
        try {
            call = clientFor(timeoutMs).newCall(new Request.Builder().url(url).build());
        } catch (Exception e) {
            deliver(callback, null, "url 非法：" + msg(e), false);
            return null;
        }
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                deliver(callback, null, c.isCanceled() ? "已取消" : "网络错误：" + msg(e), c.isCanceled());
            }

            @Override
            public void onResponse(Call c, Response response) {
                if (!response.isSuccessful()) {
                    deliver(callback, null, "HTTP " + response.code(), false);
                    return;
                }
                File out = new File(path);
                File parent = out.getParentFile();
                if (parent != null && !parent.exists() && !parent.mkdirs()) {
                    deliver(callback, null, "无法创建目录：" + parent, false);
                    return;
                }
                long total = 0;
                long lastPost = 0;
                final long expected = response.body() == null ? -1 : response.body().contentLength();
                try (ResponseBody b = response.body();
                     InputStream in = b == null ? null : b.byteStream();
                     OutputStream os = new FileOutputStream(out)) {
                    if (in == null) {
                        deliver(callback, null, "响应体为空", false);
                        return;
                    }
                    byte[] buf = new byte[16 * 1024];
                    int n;
                    while ((n = in.read(buf)) != -1) {
                        if (c.isCanceled()) {
                            deliver(callback, null, "已取消", true);
                            return;
                        }
                        os.write(buf, 0, n);
                        total += n;
                        // 进度节流：约 250ms 一次，避免主线程被刷爆
                        long now = System.currentTimeMillis();
                        if (onProgress != null && now - lastPost >= 250) {
                            lastPost = now;
                            reportProgress(onProgress, total, expected);
                        }
                    }
                    if (onProgress != null) {
                        reportProgress(onProgress, total, expected);
                    }
                } catch (IOException e) {
                    deliver(callback, null, "写入失败：" + msg(e), false);
                    return;
                }
                downloadDone(callback, out.getAbsolutePath(), total);
            }
        });
        return call;
    }

    /** multipart 上传单个文件（默认超时）。回调结果同 request。 */
    public static Call upload(String url, String field, String filePath, LuaObject callback) {
        return upload(url, field, filePath, callback, 0);
    }

    /** multipart 上传单个文件。回调结果同 request。 */
    public static Call upload(final String url, final String field, final String filePath,
                              final LuaObject callback, int timeoutMs) {
        if (url == null || filePath == null || callback == null) {
            throw new IllegalArgumentException("okhttp.upload(url, field, filePath, callback)：参数必填");
        }
        File f = new File(filePath);
        if (!f.isFile()) {
            deliver(callback, null, "文件不存在：" + filePath, false);
            return null;
        }
        MultipartBody body = new MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(field == null || field.isEmpty() ? "file" : field, f.getName(),
                        RequestBody.create(OCTET, f))
                .build();
        final Call call;
        try {
            call = clientFor(timeoutMs).newCall(new Request.Builder().url(url).post(body).build());
        } catch (Exception e) {
            deliver(callback, null, "请求构造失败：" + msg(e), false);
            return null;
        }
        call.enqueue(new Callback() {
            @Override
            public void onFailure(Call c, IOException e) {
                deliver(callback, null, c.isCanceled() ? "已取消" : "网络错误：" + msg(e), c.isCanceled());
            }

            @Override
            public void onResponse(Call c, Response response) {
                String text = "";
                try (ResponseBody b = response.body()) {
                    if (b != null) {
                        text = b.string();
                    }
                } catch (IOException e) {
                    deliver(callback, null, "读取响应失败：" + msg(e), false);
                    return;
                }
                deliver(callback, response, text, false);
            }
        });
        return call;
    }

    /** 按超时构造客户端（<=0 用默认）；连接池由 BASE.newBuilder 共享。 */
    private static OkHttpClient clientFor(int timeoutMs) {
        if (timeoutMs <= 0) {
            return BASE;
        }
        return BASE.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build();
    }

    private static String str(LuaTable<?, ?> t, String key, String def) {
        Object v = t.get(key);
        return v == null ? def : String.valueOf(v);
    }

    /** 错误信息兜底：message 可能为 null。 */
    private static String msg(Throwable e) {
        if (e == null) {
            return "未知错误";
        }
        String m = e.getMessage();
        return m == null || m.isEmpty() ? e.getClass().getSimpleName() : m;
    }

    /** 自定义日志回调（Lua 函数，收到 (level, msg)）。 */
    private static volatile LuaObject LOGGER;

    public static void setLogger(LuaObject logger) {
        LOGGER = logger;
    }

    private static void log(LuaObject cb, String message) {
        if (DEBUG) {
            emitLog(cb, "info", message);
        }
    }

    /** error 级始终输出；info 级受 DEBUG 控制。logger 抛异常直接吞掉，避免递归。 */
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
                        }
                    }
                } catch (Exception ignored) {
                }
            }
        });
    }

    private static void logToLua(final LuaObject cb, final String message) {
        if (cb == null) {
            return;
        }
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                LuaState L = cb.getLuaState();
                try {
                    LuaObject print = L.getLuaObject("print");
                    if (print != null && print.isFunction()) {
                        print.call(message);
                    }
                } catch (Exception ignored) {
                }
            }
        });
    }

    /** 回到主线程再调用 Lua；response 为 null 表示失败。 */
    private static void deliver(final LuaObject callback, final Response response,
                                final String bodyOrError, final boolean canceled) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    final LuaState L = callback.getLuaState();
                    LuaTable<String, Object> t = new LuaTable<String, Object>(L);
                    if (response == null) {
                        t.put("ok", Boolean.FALSE);
                        t.put("error", bodyOrError);
                        if (canceled) {
                            t.put("canceled", Boolean.TRUE);
                        }
                    } else {
                        t.put("ok", Boolean.TRUE);
                        t.put("code", (double) response.code());
                        t.put("body", bodyOrError);
                        // 单值：第一个；多值：headersAll[name] = { v1, v2, ... }
                        LuaTable<String, Object> h = new LuaTable<String, Object>(L);
                        LuaTable<String, Object> all = new LuaTable<String, Object>(L);
                        for (String name : response.headers().names()) {
                            List<String> values = response.headers(name);
                            h.put(name, values.isEmpty() ? "" : values.get(0));
                            // [07] 单值也放进数组，Lua 侧统一用 headersAll 遍历
                            LuaTable<Object, Object> list = new LuaTable<Object, Object>(L);
                            for (int i = 0; i < values.size(); i++) {
                                list.put((double) (i + 1), values.get(i));
                            }
                            all.put(name, list);
                        }
                        t.put("headers", h);
                        t.put("headersAll", all);
                        response.close();
                    }
                    callback.call(t);
                } catch (Exception e) {
                    // 回调用户代码出错：打到 Lua 控制台，而不是只留堆栈
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

    private static void reportProgress(final LuaObject onProgress, final long received, final long total) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    onProgress.call((double) received, (double) total);
                } catch (Exception ignored) {
                }
            }
        });
    }

    private static void downloadDone(final LuaObject cb, final String path, final long size) {
        deliverDownload(cb, path, size, null);
    }

    private static void reportCallbackError(LuaObject cb, Exception e) {
        e.printStackTrace();
        logToLua(cb, "[okhttp] 回调执行出错：" + msg(e));
    }
}
