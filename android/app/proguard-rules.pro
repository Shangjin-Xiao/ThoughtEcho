# Flutter混淆规则

# 不混淆Flutter引擎代码
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# 不混淆Kotlin相关代码
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# 不混淆序列化相关代码
-keepattributes *Annotation*
-keepattributes Signature
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# 保留R文件中的成员
-keepclassmembers class **.R$* {
    public static <fields>;
}

# 保留本地方法
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留枚举类
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 保留Parcelable实现类
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# 保留自定义View
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
    public void set*(...);
}

# 保留WebView相关
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String);
}

# 不混淆JavaScript接口
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# 忽略Google Play Core库相关类的缺失
-dontwarn com.google.android.play.core.**

# SQLite 数据库相关
-keep class android.database.sqlite.** { *; }
-keep class net.sqlcipher.** { *; }  # 如果使用了 SQLCipher，也需要排除
-keep class com.sqlite.** { *; } # 某些SQLite库的包名

# 32位设备兼容性规则
-keep class com.shangjin.thoughtecho.MainActivity { *; }
-keep class com.shangjin.thoughtecho.MemoryInfoPlugin { *; }
-keep class com.shangjin.thoughtecho.StreamFileSelector { *; }

# 保留JNI相关方法和类，确保32位设备上的native库正常工作
-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留Flutter平台通道相关类
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.platform.** { *; }

# MMKV库兼容性
-keep class com.tencent.mmkv.** { *; }
-dontwarn com.tencent.mmkv.**

# flutter_gemma / MediaPipe
# MediaPipe 的部分 profiling/graph 相关 API 会在字节码中引用 proto 生成类，但这些类在某些打包组合里并不会随库一起提供。
# Release 模式启用 R8 时会因此报 "Missing class ... com.google.mediapipe.proto.*" 并直接失败。
# 这些缺失类通常只影响可选的 profiler/调试路径；应用未使用时可以安全忽略。
-dontwarn com.google.mediapipe.proto.**
-dontwarn com.google.mediapipe.framework.GraphProfiler
-dontwarn com.google.mediapipe.framework.Graph

# 32位设备内存优化
-dontoptimize
-dontpreverify