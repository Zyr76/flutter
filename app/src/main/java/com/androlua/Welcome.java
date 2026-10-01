package com.androlua;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Dialog;
import android.app.ProgressDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.AsyncTask;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.provider.Settings;
import android.net.Uri;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.splashscreen.SplashScreen;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.view.Gravity;

import com.luajava.LuaFunction;
import com.luajava.LuaState;
import com.luajava.LuaStateFactory;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;


public class Welcome extends Activity {

    private boolean isUpdata;

    private LuaApplication app;

    private String luaMdDir;

    private String localDir;

    private long mLastTime;

    private long mOldLastTime;

    private ProgressDialog pd;

    private boolean isVersionChanged;

    private String mVersionName;

    private String mOldVersionName;

    private ArrayList<String> permissions;

    /** 启动图资源路径（放在 assets 里）。 */
    private static final String SPLASH_ASSET = "res/splash_screen.png";

    @Override
    public void onCreate(Bundle savedInstanceState) {

        super.onCreate(savedInstanceState);
        // 接管系统 splash（Android 12+ 强制的那层）：SplashTheme 已把它设成「同色底 + 透明图标」。
        SplashScreen.installSplashScreen(this);
        // 启动页：一张全屏图片、无任何文字，图片取自 assets/res/splash_screen.png，按 centerCrop 铺满。
        // 若 Lua 目录下存在 setup.png，则用它覆盖（老机制保留）。
        app = (LuaApplication) getApplication();
        luaMdDir = app.luaMdDir;
        localDir = app.localDir;
        try {
            File setup = new File(app.getLuaPath("setup.png"));
            Drawable splash = setup.exists()
                    ? new LuaBitmapDrawable(app, setup.getAbsolutePath(), null)
                    : loadAssetSplash();
            if (splash != null) {
                getWindow().setBackgroundDrawable(splash);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        if (checkInfo()) {
            if (Build.VERSION.SDK_INT >= 23) {
                try {
                    permissions = new ArrayList<String>();
                    String[] ps2 = getPackageManager().getPackageInfo(getPackageName(), PackageManager.GET_PERMISSIONS).requestedPermissions;
                    for (String p : ps2) {
                        try {
                            checkPermission(p);
                        } catch (Exception e) {
                            e.printStackTrace();
                        }
                    }
                    if (!permissions.isEmpty()) {
                        String[] ps = new String[permissions.size()];
                        permissions.toArray(ps);
                        requestPermissions(ps,
                                0);
                        return;
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
            // Android 11+ 需要请求 MANAGE_EXTERNAL_STORAGE 权限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (!Environment.isExternalStorageManager()) {
                    try {
                        Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                        intent.setData(Uri.parse("package:" + getPackageName()));
                        startActivityForResult(intent, 1);
                        return;
                    } catch (Exception e) {
                        Intent intent = new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
                        startActivityForResult(intent, 1);
                        return;
                    }
                }
            }
            new UpdateTask().execute();
        } else {
            startActivity();
        }
    }

    /**
     * 从 assets 读启动图（{@link #SPLASH_ASSET}），降采样后按 <b>centerCrop</b> 铺满全屏
     * （等比放大到填满、再居中裁剪，不会拉伸变形）。读不到时返回 null，不改窗口背景。
     */
    private Drawable loadAssetSplash() {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        InputStream probe = null;
        try {
            probe = getAssets().open(SPLASH_ASSET);
            BitmapFactory.decodeStream(probe, null, bounds);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        } finally {
            closeQuietly(probe);
        }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null;
        }

        int screenW = getResources().getDisplayMetrics().widthPixels;
        int screenH = getResources().getDisplayMetrics().heightPixels;

        // 降采样到「大约屏幕大小」：允许降到屏幕长边的一半，避免 3000x4000 的原图直接吃几十 MB 内存。
        int longSide = Math.max(bounds.outWidth, bounds.outHeight);
        int screenLong = Math.max(screenW, screenH);
        int sample = 1;
        while (longSide / (sample * 2) >= screenLong / 2) {
            sample *= 2;
        }

        Bitmap src;
        InputStream in = null;
        try {
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = sample;
            opts.inPreferredConfig = Bitmap.Config.RGB_565; // 启动图不需要 alpha，省一半内存
            in = getAssets().open(SPLASH_ASSET);
            src = BitmapFactory.decodeStream(in, null, opts);
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        } finally {
            closeQuietly(in);
        }
        if (src == null) {
            return null;
        }

        BitmapDrawable drawable = new BitmapDrawable(getResources(), centerCrop(src, screenW, screenH));
        drawable.setGravity(Gravity.FILL);
        return drawable;
    }

    /** 等比放大到能铺满 targetW x targetH，再居中裁剪到该尺寸。 */
    private static Bitmap centerCrop(Bitmap src, int targetW, int targetH) {
        int w = src.getWidth();
        int h = src.getHeight();
        float scale = Math.max((float) targetW / w, (float) targetH / h);
        int scaledW = Math.max(targetW, Math.round(w * scale));
        int scaledH = Math.max(targetH, Math.round(h * scale));
        Bitmap scaled = Bitmap.createScaledBitmap(src, scaledW, scaledH, true);
        return Bitmap.createBitmap(scaled, (scaledW - targetW) / 2, (scaledH - targetH) / 2,
                targetW, targetH);
    }

    private static void closeQuietly(InputStream in) {
        if (in != null) {
            try {
                in.close();
            } catch (IOException ignored) {
            }
        }
    }

    private void checkPermission(String permission) {
        if (checkCallingOrSelfPermission(permission)
                != PackageManager.PERMISSION_GRANTED) {
            permissions.add(permission);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        // Android 11+ 检查 MANAGE_EXTERNAL_STORAGE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!Environment.isExternalStorageManager()) {
                try {
                    Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                    intent.setData(Uri.parse("package:" + getPackageName()));
                    startActivityForResult(intent, 1);
                    return;
                } catch (Exception e) {
                    Intent intent = new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
                    startActivityForResult(intent, 1);
                    return;
                }
            }
        }
        new UpdateTask().execute();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 1) {
            // 从 MANAGE_EXTERNAL_STORAGE 权限设置返回
            new UpdateTask().execute();
        }
    }

    public void startActivity() {
        Intent intent = new Intent(Welcome.this, Main.class);
        if (isVersionChanged) {
            intent.putExtra("isVersionChanged", isVersionChanged);
            intent.putExtra("newVersionName", mVersionName);
            intent.putExtra("oldVersionName", mOldVersionName);
        }
        startActivity(intent);
        //overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out                                                                                                                 );
        finish();

    }

    public boolean checkInfo() {
        try {
            PackageInfo packageInfo = getPackageManager().getPackageInfo(this.getPackageName(), 0);
            long lastTime = packageInfo.lastUpdateTime;
            String versionName = packageInfo.versionName;
            SharedPreferences info = getSharedPreferences("appInfo", 0);
            String oldVersionName = info.getString("versionName", "");
            if (!versionName.equals(oldVersionName)) {
                SharedPreferences.Editor edit = info.edit();
                edit.putString("versionName", versionName);
                edit.apply();
                isVersionChanged = true;
                mVersionName = versionName;
                mOldVersionName = oldVersionName;
            }
            long oldLastTime = info.getLong("lastUpdateTime", 0);
            if (oldLastTime != lastTime) {
                SharedPreferences.Editor edit = info.edit();
                edit.putLong("lastUpdateTime", lastTime);
                edit.apply();
                isUpdata = true;
                mLastTime = lastTime;
                mOldLastTime = oldLastTime;
                return true;
            }
        } catch (PackageManager.NameNotFoundException e) {
            e.printStackTrace();
        }
        return false;
    }


    @SuppressLint("StaticFieldLeak")
    private class UpdateTask extends AsyncTask<String, String, String> {
        @Override
        protected String doInBackground(String[] p1) {
            // TODO: Implement this method
            onUpdate(mLastTime, mOldLastTime);
            return null;
        }

        @Override
        protected void onPostExecute(String result) {
            startActivity();
        }

        private void onUpdate(long lastTime, long oldLastTime) {

            LuaState L = LuaStateFactory.newLuaState();
            L.openLibs();
            try {
                if (L.LloadBuffer(LuaUtil.readAsset(Welcome.this, "update.lua"), "update") == 0) {
                    if (L.pcall(0, 0, 0) == 0) {
                        LuaFunction func = L.getFunction("onUpdate");
                        if (func != null)
                            func.call(mVersionName, mOldVersionName);
                    }
                    ;
                }

            } catch (Exception e) {
                e.printStackTrace();
            }

            try {
                //LuaUtil.rmDir(new File(localDir),".lua");
                //LuaUtil.rmDir(new File(luaMdDir),".lua");


                unApk("assets", localDir);
                unApk("lua", luaMdDir);
                //unZipAssets("main.alp", extDir);
            } catch (IOException e) {
                sendMsg(e.getMessage());
            }
        }

        private void sendMsg(String message) {
            // TODO: Implement this method

        }

        private void unApk(String dir, String extDir) throws IOException {
            int i = dir.length() + 1;
            ZipFile zip = new ZipFile(getApplicationInfo().publicSourceDir);
            Enumeration<? extends ZipEntry> entries = zip.entries();
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                String name = entry.getName();
                if (name.indexOf(dir) != 0)
                    continue;
                String path = name.substring(i);
                if (entry.isDirectory()) {
                    File f = new File(extDir + File.separator + path);
                    if (!f.exists()) {
                        //noinspection ResultOfMethodCallIgnored
                        f.mkdirs();
                    }
                } else {
                    String fname = extDir + File.separator + path;
                    File ff = new File(fname);
                    File temp = new File(fname).getParentFile();
                    if (!temp.exists()) {
                        if (!temp.mkdirs()) {
                            throw new RuntimeException("create file " + temp.getName() + " fail");
                        }
                    }
                    try {
                        if (ff.exists() && entry.getSize() == ff.length() && LuaUtil.getFileMD5(zip.getInputStream(entry)).equals(LuaUtil.getFileMD5(ff)))
                            continue;
                    } catch (NullPointerException ignored) {
                    }
                    FileOutputStream out = new FileOutputStream(extDir + File.separator + path);
                    InputStream in = zip.getInputStream(entry);
                    byte[] buf = new byte[4096];
                    int count = 0;
                    while ((count = in.read(buf)) != -1) {
                        out.write(buf, 0, count);
                    }
                    out.close();
                    in.close();
                }
            }
            zip.close();
        }

    }
}
