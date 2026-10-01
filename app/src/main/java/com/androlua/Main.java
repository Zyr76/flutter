package com.androlua;

import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.Settings;

import java.util.ArrayList;


public class Main extends LuaActivity
{

	@Override
	public void onCreate(Bundle savedInstanceState) {
		// 直接启动（如打开 .lua/.alp 文件）时兜底解包；正常启动时引导已由 SplashActivity 完成。
		LuaApplication app = (LuaApplication) getApplication();
		boolean bootstrappedNow = app.bootstrapIfNeeded();
		super.onCreate(savedInstanceState);
		// 权限申请直接弹在 Lua 界面上。
		requestRuntimePermissions();
		if(savedInstanceState==null && getIntent().getData()!=null)
			runFunc("onNewIntent", getIntent());
		if(savedInstanceState==null && (bootstrappedNow || getIntent().getBooleanExtra("isVersionChanged", false))){
			String newVersion = getIntent().getStringExtra("newVersionName");
			String oldVersion = getIntent().getStringExtra("oldVersionName");
			if (newVersion == null)
				newVersion = app.getVersionName();
			if (oldVersion == null)
				oldVersion = app.getOldVersionName();
			onVersionChanged(newVersion, oldVersion);
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
