import Flutter
import UIKit
import workmanager_apple // iOS 上 workmanager 包名为 workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  /// Registers all pubspec-referenced Flutter plugins in the given registry.
  static func registerPlugins(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
  }
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the app's plugins in the context of a normal run
    AppDelegate.registerPlugins(with: self)
    
    // Register plugin callback for Workmanager background tasks
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      AppDelegate.registerPlugins(with: registry)
    }
    
    // 注册 WorkManager 后台任务
    // 注册一次性后台处理任务
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "com.shangjin.thoughtecho.backgroundPush")
    
    // 注册周期性任务 (每20分钟，这是最小间隔)
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.shangjin.thoughtecho.periodicCheck",
      frequency: NSNumber(value: 20 * 60)
    )
    
    // iOS 后台任务需要显式设置 minimumBackgroundFetchInterval
    // 设置为 minimum 以尽可能频繁地检查（实际由系统控制）
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
