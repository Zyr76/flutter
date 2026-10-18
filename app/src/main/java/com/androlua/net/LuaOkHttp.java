package com.androlua.net;

import android.os.Handler;
import android.os.Looper;

import com.luajava.LuaObject;
import com.luajava.LuaTable;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * OkHttp 的 Lua 门面，Lua 侧见 resources/lua/okhttp.lua。
 *
 * <p>请求在 OkHttp 自己的线程池执行，回调**统一 post 回主线程**再调 Lua：
 * Lua 状态只在主线程使用，从 worker 线程直接调用会破坏 Lua 栈。
 *
 * <p>opts 键：method / url / headers(表) / body(字符串) / contentType / timeout(毫秒)
 * <p>结果表：{ ok, code, body, headers, error }
 */
public final class LuaOkHttp {

    private static final MediaType TEXT = MediaType.parse("text/plain; charset=utf-8");

    private static final OkHttpClient BASE = new OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .followRedirects(true)
            .build();

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private LuaOkHttp() {
    }

    /**
     * 发起一次异步请求。
     *
     * @param opts     Lua 表，至少要有 url
     * @param callback Lua 函数，参数是结果表
     */
    public static void request(LuaTable opts, final LuaObject callback) {
        if (opts == null || callback == null) {
            throw new IllegalArgumentException("okhttp.request(opts, callback)：两个参数都必填");
        }
        final String method = str(opts, "method", "GET").toUpperCase();
        final String url = str(opts, "url", "").trim();
        if (url.isEmpty()) {
            deliver(callback, null, "url 不能为空");
            return;
        }

        Request.Builder rb;
        try {
            rb = new Request.Builder().url(url);
        } catch (Exception e) {
            deliver(callback, null, "url 非法：" + e.getMessage());
            return;
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

        // GET/HEAD 不能带 body（OkHttp 会直接抛异常），其余方法按需带
        String bodyText = str(opts, "body", "");
        RequestBody body = null;
        if (!"GET".equals(method) && !"HEAD".equals(method) && !bodyText.isEmpty()) {
            String ct = str(opts, "contentType", "text/plain; charset=utf-8");
            MediaType media = MediaType.parse(ct);
            body = RequestBody.create(media == null ? TEXT : media, bodyText);
        }
        rb.method(method, body);

        Object to = opts.get("timeout");
        OkHttpClient client = BASE;
        if (to instanceof Number) {
            int ms = ((Number) to).intValue();
            if (ms > 0) {
                client = BASE.newBuilder().callTimeout(ms, TimeUnit.MILLISECONDS).build();
            }
        }

        client.newCall(rb.build()).enqueue(new Callback() {
            @Override
            public void onFailure(Call call, IOException e) {
                deliver(callback, null, "网络错误：" + e.getMessage());
            }

            @Override
            public void onResponse(Call call, Response response) {
                String text = "";
                try (ResponseBody b = response.body()) {
                    if (b != null) {
                        text = b.string();
                    }
                } catch (IOException e) {
                    deliver(callback, null, "读取响应失败：" + e.getMessage());
                    return;
                }
                deliver(callback, response, text);
            }
        });
    }

    private static String str(LuaTable<?, ?> t, String key, String def) {
        Object v = t.get(key);
        return v == null ? def : String.valueOf(v);
    }

    /** 回到主线程再调用 Lua；response 为 null 表示失败。 */
    private static void deliver(final LuaObject callback, final Response response, final String bodyOrError) {
        MAIN.post(new Runnable() {
            @Override
            public void run() {
                try {
                    LuaTable<String, Object> t = new LuaTable<>(callback.getLuaState());
                    if (response == null) {
                        t.put("ok", Boolean.FALSE);
                        t.put("error", bodyOrError);
                    } else {
                        t.put("ok", Boolean.TRUE);
                        t.put("code", (double) response.code());
                        t.put("body", bodyOrError);
                        LuaTable<String, Object> h = new LuaTable<>(callback.getLuaState());
                        for (String name : response.headers().names()) {
                            h.put(name, response.header(name, ""));
                        }
                        t.put("headers", h);
                        response.close();
                    }
                    callback.call(t);
                } catch (Exception e) {
                    // 回调本身出错时不影响后续请求
                    e.printStackTrace();
                }
            }
        });
    }
}
