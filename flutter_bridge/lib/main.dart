import 'package:flutter/material.dart';

import 'src/bridge.dart';
import 'src/renderer.dart';

/// 嵌入式引擎入口。Android 侧用 DartEntrypoint("main") 启动这个入口。
@pragma('vm:entry-point')
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBridge.instance.start();
  runApp(const FlutterBridgeApp());
}

class FlutterBridgeApp extends StatelessWidget {
  const FlutterBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 弹窗类命令需要 Navigator：交给 FlutterBridge 持有，原生可直接调 showDialog 等。
      navigatorKey: FlutterBridge.instance.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3F51B5), useMaterial3: true),
      home: const BridgeRoot(),
    );
  }
}

/// 监听原生推来的 widget 描述，并据此重建整棵 Flutter UI。
class BridgeRoot extends StatelessWidget {
  const BridgeRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: FlutterBridge.instance.spec,
      builder: (context, spec, _) {
        if (spec == null || spec.isEmpty) {
          return const Center(
            child: Text('Flutter 引擎已就绪', style: TextStyle(color: Colors.grey)),
          );
        }
        return Renderer.build(spec);
      },
    );
  }
}
