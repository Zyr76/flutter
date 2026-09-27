package com.privatespace.private_space

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

// local_auth 在 Android 上要求宿主 Activity 继承 FlutterFragmentActivity，
// 否则系统生物识别弹窗（BiometricPrompt Fragment）无法挂载，
// 会导致指纹验证直接返回“验证失败或已取消”。
class MainActivity : FlutterFragmentActivity() {
  private val CHANNEL = "privatespace/apk_icon"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            // 从 APK 文件读取应用图标，写入指定输出文件；成功返回 true
            "extractIcon" -> {
              val path = call.argument<String>("path")
              val out = call.argument<String>("out")
              if (path == null || out == null) {
                result.success(false)
              } else {
                result.success(extractApkIcon(path, out))
              }
            }
            "installApk" -> {
              val path = call.argument<String>("path")
              result.success(installApk(path))
            }
            else -> result.notImplemented()
          }
        }
  }

  // 通过系统安装器安装本地 APK：返回 true 表示已成功唤起安装界面。
  // 关键：path_provider 的 getApplicationDocumentsDirectory() 返回
  // /data/data/<pkg>/app_flutter/，而 FileProvider 的 paths 配置里 <files-path>
  // 只覆盖 getFilesDir()(/data/data/<pkg>/files)，无法匹配该目录，
  // 导致 getUriForFile 抛异常、安装一直失败。这里先把 APK 复制进缓存
  // cacheDir/apk_share/（对应已声明的 <cache-path>），再用 FileProvider 分享。
  private fun installApk(apkPath: String?): Boolean {
    if (apkPath == null) return false
    val file = File(apkPath)
    if (!file.exists()) return false
    return try {
      val cacheDir = File(cacheDir, "apk_share")
      cacheDir.mkdirs()
      val tmp = File(cacheDir, "install_${System.currentTimeMillis()}.apk")
      file.copyTo(tmp, overwrite = true)
      val uri: Uri = FileProvider.getUriForFile(
          this, "$packageName.apk_provider", tmp)
      val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "application/vnd.android.package-archive")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }
      startActivity(intent)
      true
    } catch (_: Exception) {
      false
    }
  }

  // 通过 PackageManager 解析 APK 的图标。适用于任意 APK 文件路径。
  private fun extractApkIcon(apkPath: String, outPath: String): Boolean {
    return try {
      val pm = packageManager
      // 任意 APK：用 getPackageArchiveInfo 读取而不安装
      val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        pm.getPackageArchiveInfo(apkPath, PackageManager.PackageInfoFlags.of(0))
      } else {
        @Suppress("DEPRECATION")
        pm.getPackageArchiveInfo(apkPath, 0)
      }
      if (info == null) return false
      val appInfo = info.applicationInfo ?: return false
      appInfo.sourceDir = apkPath
      appInfo.publicSourceDir = apkPath
      val icon: Drawable? = try {
        pm.getApplicationIcon(appInfo)
      } catch (_: Exception) {
        // 部分机型 getApplicationIcon 校验包名，回退手动 loadIcon
        appInfo.loadIcon(pm)
      }
      val bmp = drawableToBitmap(icon) ?: return false
      val f = File(outPath)
      f.parentFile?.mkdirs()
      FileOutputStream(f).use { out ->
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
      }
      true
    } catch (_: Exception) {
      false
    }
  }

  private fun drawableToBitmap(drawable: Drawable?): Bitmap? {
    if (drawable == null) return null
    if (drawable is BitmapDrawable && drawable.bitmap != null) return drawable.bitmap
    try {
      val bmp = Bitmap.createBitmap(
          drawable.intrinsicWidth.coerceAtLeast(1),
          drawable.intrinsicHeight.coerceAtLeast(1),
          Bitmap.Config.ARGB_8888)
      val canvas = Canvas(bmp)
      drawable.setBounds(0, 0, canvas.width, canvas.height)
      drawable.draw(canvas)
      return bmp
    } catch (_: Exception) {
      return null
    }
  }
}