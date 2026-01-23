import Flutter
import UIKit
import workmanager // 添加导入

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // 注册 WorkManager 插件
    WorkmanagerPlugin.registerTask(withIdentifier: "com.shangjin.thoughtecho.backgroundPush")
    WorkmanagerPlugin.registerTask(withIdentifier: "com.shangjin.thoughtecho.periodicCheck")
    // iOS 后台任务需要显式设置 minimumBackgroundFetchInterval
    // 设置为 minimum 以尽可能频繁地检查（实际由系统控制）
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
