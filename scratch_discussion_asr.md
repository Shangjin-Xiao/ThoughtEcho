大家好！

我们正在为 ThoughtEcho 准备本地离线语音识别（ASR）功能，相关的代码（基于 `sherpa-onnx`）目前已在 Pull Request 中进行测试。

该功能允许您直接在 App 内进行语音输入，所有的语音实时转写均在设备本地完成，数据绝不上传云端，以完全保障您的隐私安全。

关于该功能的实现细节与体积说明如下：

1. **基础包体积增加**：为了支持本地识别，应用需要引入 `sherpa-onnx` 推理引擎。这将导致 App 的基础安装包体积固定增加几十 MB。
2. **模型按需下载**：由于高精度的语音模型体积较大（通常在几十 MB 到几百 MB 不等），我们**不会**将其内置在安装包中。功能上线后，您可以在需要时自行在应用内下载对应的离线模型。

大家对于这个即将上线的新功能有什么期待或疑问，欢迎在评论区留言！👇

---

**[English Version]**

Hello everyone!

We are preparing to introduce a Local Offline Speech Recognition (ASR) feature to ThoughtEcho. The related code (based on `sherpa-onnx`) is currently being tested in a Pull Request.

This feature allows you to use voice dictation directly within the app. All real-time speech-to-text processing is done entirely locally on your device. No audio is ever uploaded to the cloud, fully ensuring your privacy and security.

Regarding the implementation details and app size of this feature:

1. **Base App Size Increase**: To support local recognition, the app needs to include the `sherpa-onnx` inference engine. This will result in a fixed increase of several dozens of megabytes in the app's base installation package.
2. **On-Demand Model Download**: Because high-accuracy voice models are quite large (typically ranging from dozens to hundreds of megabytes), we will **not** bundle them in the installation package. Once the feature is released, you can manually download the necessary offline models within the app when needed.

If you have any expectations or questions about this upcoming feature, please feel free to leave a comment below! 👇
