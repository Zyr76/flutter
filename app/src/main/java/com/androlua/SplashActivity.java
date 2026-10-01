package com.androlua;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.WindowManager;

import androidx.core.splashscreen.SplashScreen;

/**
 * 极简启动页：只承载系统图标启动画面，并完成首次安装/版本更新时的资源解包，
 * 随即进入 Lua 界面（Main）。没有任何可见内容（无图片、无文字、无布局）。
 *
 * <p>放在独立 Activity 的原因：启动画面主题会由 {@link SplashScreen#installSplashScreen} 覆写为
 * postSplashScreenTheme，且该机制会干预窗口主题；而 Main 的主题由 Lua 脚本自己管理
 * （main.lua 会 setTheme 并依赖 getActionBar），两者不能同处一个 Activity。
 */
public class SplashActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 隐藏状态栏（配合主题的 windowFullscreen）。
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        SplashScreen.installSplashScreen(this);
        LuaApplication app = (LuaApplication) getApplication();
        boolean versionChanged = app.bootstrapIfNeeded();
        Intent intent = new Intent(this, Main.class);
        if (versionChanged) {
            intent.putExtra("isVersionChanged", true);
            intent.putExtra("newVersionName", app.getVersionName());
            intent.putExtra("oldVersionName", app.getOldVersionName());
        }
        startActivity(intent);
        finish();
    }
}
