pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Flutter 模块的本地 Maven 仓库（由 build_flutter_aar.sh / `cd flutter_bridge && flutter build aar` 生成）
        maven { url = uri("flutter_bridge/build/host/outputs/repo") }
        // Flutter 引擎产物仓库（flutter_embedding 等）
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
    }
}

rootProject.name = "Androlua"

include(":app")
