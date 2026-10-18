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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Cookie;
import okhttp3.CookieJar;
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

        Request.Builder rb;
        try {
            rb = new Request.Builder().url(url);
        } catch (Exception e) {
            deliver(callback, null, "url 非法：" + msg(e), false);
            return null;
        }

        Object hs = opts.get("headers");
        if (hs instanceof LuaTable) {
            for (Object o : ((LuaTable<?, ?>) hs).entrySet()) {
                Map.Entry<?, ?> e = (Map.Entry<?, ?>) o;
                if (e.getKey() != null && e.getValue() != null) {
                    rb.header(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }

        // GET/HEAD 不能带 body（OkHttp 会抛），其余方法按需带
        String bodyText = str(opts, "body", "");
        RequestBody body = null;
        if (!"GET".equals(method) && !"HEAD".equals(method) && !bodyText.isEmpty()) {
            String ct = str(opts, "contentType", "text/plain; charset=utf-8");
            MediaType media = MediaType.parse(ct);
            body = RequestBody.create(media == null ? TEXT : media, bodyText);
        }
        rb.method(method, body);
        log(callback, "→ " + method + " " + url + (bodyText.isEmpty() ? "" : " body=" + bodyText));

        Object to = opts.get("timeout");
        OkHttpClient client = BASE;
        if (to instanceof Number) {
            int ms = ((Number) to).intValue();
            if (ms > 0) {
                client = BASE.newBuilder().callTimeout(ms, TimeUnit.MILLISECONDS).build();
            }
        }

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
                        text = b.string();
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

    /** 流式下载到本地文件（不整体入内存）。回调结果：{ ok, path, size, error } */
    public static Call download(final String url, final String path, final LuaObject callback) {
        if (url == null || path == null || callback == null) {
            throw new IllegalArgumentException("okhttp.download(url, path, callback)：参数必填");
        }
        final Call call;
        try {
            call = BASE.newCall(new Request.Builder().url(url).build());
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

    /** multipart 上传单个文件。回调结果同 request。 */
    public static Call upload(final String url, final String field, final String filePath, final LuaObject callback) {
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
            call = BASE.newCall(new Request.Builder().url(url).post(body).build());
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

    private static void log(LuaObject cb, String message) {
        if (DEBUG) {
            logToLua(cb, "[okhttp] " + message);
        }
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
                            if (values.size() > 1) {
                                // Lua 数组：数字键从 1 开始
                                LuaTable<Object, Object> list = new LuaTable<Object, Object>(L);
                                for (int i = 0; i < values.size(); i++) {
                                    list.put((double) (i + 1), values.get(i));
                                }
                                all.put(name, list);
                            }
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

    private static void downloadDone(final LuaObject cb, final String path, final long size) {
        deliverDownload(cb, path, size, null);
    }

    private static void reportCallbackError(LuaObject cb, Exception e) {
        e.printStackTrace();
        logToLua(cb, "[okhttp] 回调执行出错：" + msg(e));
    }
}
