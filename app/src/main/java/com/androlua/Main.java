package com.androlua;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;

import androidx.core.splashscreen.SplashScreen;

import java.util.ArrayList;


public class Main extends LuaActivity
{

	@Override
	public void onCreate(Bundle savedInstanceState) {
		// 系统启动画面（App 图标）：在 setTheme / 加载 Lua 之前接管。
		SplashScreen.installSplashScreen(this);
		// 引导：首次安装或版本更新时，把 APK 内的 Lua 资源解到私有目录（main.lua 等），
		// 必须在 super.onCreate() 加载脚本之前完成。
		LuaApplication app = (LuaApplication) getApplication();
		boolean versionChanged = app.bootstrapIfNeeded();
		super.onCreate(savedInstanceState);
		// 权限申请直接弹在 Lua 界面上。
		requestRuntimePermissions();
		if(savedInstanceState==null && getIntent().getData()!=null)
			runFunc("onNewIntent", getIntent());
		if(versionChanged && (savedInstanceState==null)){
			onVersionChanged(app.getVersionName(), app.getOldVersionName());
		}
	}

	private void requestRuntimePermissions() {
		if (Build.VERSION.SDK_INT >= 23) {
			ArrayList<String> need = new ArrayList<String>();
			try {
				String[] all = getPackageManager().getPackageInfo(getPackageName(), PackageManager.GET_PERMISSIONS).requestedPermissions;
				for (String p : all) {
					if (checkCallingOrSelfPermission(p) != PackageManager.PERMISSION_GRANTED)
						need.add(p);
				}
			} catch (Exception e) {
				e.printStackTrace();
			}
			if (!need.isEmpty())
				requestPermissions(need.toArray(new String[0]), 0);
		}
		// Android 11+ 需要「所有文件访问」权限。
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
			try {
				Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
				intent.setData(Uri.parse("package:" + getPackageName()));
				startActivityForResult(intent, 1);
			} catch (Exception e) {
				try {
					startActivityForResult(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), 1);
				} catch (Exception e2) {
					e2.printStackTrace();
				}
			}
		}
	}

	@Override
	protected void onNewIntent(Intent intent)
	{
		// TODO: Implement this method
		runFunc("onNewIntent", intent);
		super.onNewIntent(intent);
	}
	
	@Override
	public String getLuaDir()
	{
		// TODO: Implement this method
		return getLocalDir();
	}

	@Override
	public String getLuaPath()
	{
		// TODO: Implement this method
		initMain();
		return getLocalDir()+"/main.lua";
	}

	private void onVersionChanged(String newVersionName, String oldVersionName) {
		// TODO: Implement this method
		runFunc("onVersionChanged", newVersionName, oldVersionName);

	}



}
