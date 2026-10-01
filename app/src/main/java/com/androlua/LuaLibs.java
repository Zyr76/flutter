package com.androlua;

import android.content.Context;
import android.graphics.drawable.Drawable;
import android.widget.ImageView;

import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestBuilder;
import com.bumptech.glide.load.resource.bitmap.CenterCrop;
import com.bumptech.glide.load.resource.bitmap.CircleCrop;
import com.bumptech.glide.load.resource.bitmap.RoundedCorners;
import com.luajava.JavaFunction;
import com.luajava.LuaException;
import com.luajava.LuaObject;
import com.luajava.LuaState;

import java.io.File;

/**
 * 一组便捷全局函数，把常用第三方库/控件封装成 Lua 一行可用的入口。
 *
 * <ul>
 *   <li>{@code 加载图片(url或路径, ImageView [, {placeholder,error,circle/圆形,centerCrop,radius}])}
 *       —— 用 Glide 异步加载（网络/本地文件都支持，自动缓存）。</li>
 *   <li>{@code 代码编辑器()} —— 返回一个内置的 {@link LuaEditor}（等宽字体、语法高亮、行号）。</li>
 *   <li>{@code 网页视图()} —— 返回一个 {@link LuaWebView}（需在 Activity 中使用）。</li>
 * </ul>
 *
 * <p>此外，第三方库的类也可在脚本里直接 {@code import} 使用：
 * Glide（{@code com.bumptech.glide.*}）、OkHttp（{@code okhttp3.*}）、
 * FlexboxLayout（{@code com.google.android.flexbox.*}）、Lottie（{@code com.airbnb.lottie.*}）。
 */
public final class LuaLibs {

    private LuaLibs() {
    }

    public static void register(final LuaState L, final LuaContext context) throws LuaException {
        final Context ctx = context.getContext();

        // ---- 加载图片(url/path, imageView [, opts]) —— Glide ----
        JavaFunction loadImage = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                if (L.getTop() < 3 || L.isNoneOrNil(2) || L.isNoneOrNil(3)) {
                    warn(L, "用法: 加载图片(url或路径, ImageView [, {placeholder,error,circle,centerCrop,radius}])");
                    return 0;
                }
                String url = L.toString(2);
                Object v = L.toJavaObject(3);
                if (!(v instanceof ImageView)) {
                    warn(L, "加载图片: 第二个参数需要是 ImageView");
                    return 0;
                }
                ImageView iv = (ImageView) v;
                Object model = (url.startsWith("http://") || url.startsWith("https://"))
                        ? url : new File(url);

                RequestBuilder<Drawable> rb = Glide.with(iv).load(model);

                int ph = 0, err = 0, radius = 0;
                boolean circle = false, centerCrop = false;
                if (L.isTable(4)) {
                    LuaObject o = L.getLuaObject(4);
                    ph = intField(o, "placeholder", 0);
                    err = intField(o, "error", 0);
                    radius = intField(o, "radius", 0);
                    circle = boolField(o, "circle", false) || boolField(o, "圆形", false);
                    centerCrop = boolField(o, "centerCrop", false);
                }
                if (ph != 0)
                    rb = rb.placeholder(ph);
                if (err != 0)
                    rb = rb.error(err);
                if (circle)
                    rb = rb.transform(new CircleCrop());
                else if (radius > 0)
                    rb = rb.transform(new CenterCrop(), new RoundedCorners(radius));
                else if (centerCrop)
                    rb = rb.centerCrop();
                rb.into(iv);
                return 0;
            }
        };
        loadImage.register("加载图片");
        loadImage.register("glide图片");

        // ---- 代码编辑器() —— 内置 LuaEditor ----
        JavaFunction editor = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                L.pushJavaObject(new LuaEditor(ctx));
                return 1;
            }
        };
        editor.register("代码编辑器");
        editor.register("CodeEditor");

        // ---- 网页视图() —— LuaWebView（需要 Activity 上下文）----
        JavaFunction webview = new JavaFunction(L) {
            @Override
            public int execute() throws LuaException {
                if (context instanceof LuaActivity) {
                    L.pushJavaObject(new LuaWebView((LuaActivity) context));
                } else {
                    warn(L, "网页视图() 只能在 Activity 中使用");
                    L.pushNil();
                }
                return 1;
            }
        };
        webview.register("网页视图");
        webview.register("WebView视图");
    }

    private static int intField(LuaObject o, String name, int def) {
        try {
            LuaObject f = o.getField(name);
            return (f != null && !f.isNil()) ? (int) f.getInteger() : def;
        } catch (Exception e) {
            return def;
        }
    }

    private static boolean boolField(LuaObject o, String name, boolean def) {
        try {
            LuaObject f = o.getField(name);
            return (f != null && !f.isNil()) ? f.getBoolean() : def;
        } catch (Exception e) {
            return def;
        }
    }

    private static void warn(LuaState L, String msg) {
        try {
            LuaObject print = L.getLuaObject("print");
            if (print.isFunction()) {
                print.push();
                L.pushString("[LuaLibs] " + msg);
                L.pcall(1, 0, 0);
            }
        } catch (Throwable ignored) {
        }
    }
}
