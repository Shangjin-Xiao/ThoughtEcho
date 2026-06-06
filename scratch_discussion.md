大家好！

随着 ThoughtEcho 的功能不断丰富，我们在各个平台（尤其是 Android 和 Windows）遇到了更多碎片化导致的疑难 Bug。

一直以来，如果大家遇到无法解决的问题，通常需要进入隐藏的“开发者模式”打开**日志中心**，然后手动导出繁杂的日志文件发送给我们。这不仅流程繁琐，而且对于瞬间的闪退（如底层引擎崩溃），本地日志中心往往来不及记录。

为了能更高效地帮大家排查和修复问题，我们决定在后续版本中引入业界标准的 **Sentry** 崩溃监控平台，作为反馈问题的辅助选项。

作为一款主打本地优先的笔记应用，我们深知大家对隐私的看重，因此在机制设计上将采取严格的标准：

**1. 绝对的默认关闭**
为了保障隐私，这个错误上报功能**默认处于完全关闭状态**。只有当您遇到了阻碍使用的 Bug，并愿意协助我们排查时，您才可以在设置中手动打开它。排查完毕后，您随时可以将其再次关闭。

**2. 专注于收集程序运行状态**
即使在开启状态下，该功能也主要用于抓取代码层面的崩溃堆栈（Stack Trace）及基础设备环境信息。我们不会主动去获取您的笔记内容或数据库，但在某些特定情况下的异常日志中，可能会附带与排查该错误直接相关的部分运行上下文数据，这些数据仅用于辅助定位问题。

**3. 隐私政策同步更新**
在该功能正式上线时，我们也会同步更新项目的《隐私政策》和《用户手册》，将具体的说明做到完全公开透明。

引入这个机制，主要是为了给愿意反馈 Bug 的朋友提供一个“一键上报”的便捷通道，替代过去手动倒腾“日志中心”的麻烦。

大家如果对这个改动有任何意见或建议，欢迎在评论区提出！👇

---

**[English Version]**

Hello everyone!

As ThoughtEcho continues to grow, we've encountered more complex, device-specific bugs across various platforms (especially Android and Windows).

Currently, when you encounter an issue, you usually have to enter the hidden "Developer Mode," open the **Log Center**, manually export the log files, and send them to us. This process is not only tedious, but the local log center often fails to capture sudden app crashes (such as underlying engine crashes).

To help us troubleshoot and fix these issues more efficiently, we have decided to introduce **Sentry**, an industry-standard crash monitoring platform, as an optional feedback tool in an upcoming release.

As a local-first note-taking app, we know how much you value privacy. Therefore, we will adopt strict standards in our implementation:

**1. Strictly Default OFF**
To protect your privacy, this error reporting feature will be **completely disabled by default**. You only need to manually enable it in the Settings if you encounter a bug and are willing to help us troubleshoot. You can turn it off anytime after the issue is resolved.

**2. Focuses on Technical Errors**
Even when enabled, this feature mainly captures code-level crash stack traces and basic device information. We do not actively access your note contents or database, though some error logs may inherently include runtime context data related to the specific crash to help us pinpoint the issue.

**3. Privacy Policy Updates**
When this feature officially launches, we will simultaneously update our *Privacy Policy* and *User Manual* to make the explanation completely transparent.

The introduction of this mechanism is primarily to provide a convenient "one-click reporting" channel for friends who are willing to report bugs, replacing the hassle of manually dealing with the local "Log Center" in the past.

If you have any feedback or suggestions regarding this change, please feel free to leave a comment below! 👇
