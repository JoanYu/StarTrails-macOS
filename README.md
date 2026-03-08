# StarTrails macOS CoreML Edition

[English](#english) | [中文](#chinese)

## English
StarTrails macOS is a high-performance, native Apple Silicon rewrite of the open-source machine learning tool [gkyle/startrails](https://github.com/gkyle/startrails), which automates the laborious process of creating star trail images by eliminating airplane and satellite streaks using AI.

Originally implemented in Python with PySide6 and CUDA, this repository contains a complete architectural overhaul built with **SwiftUI** and hardware-accelerated via **CoreML**, **Vision**, and **vDSP (Accelerate Framework)**.

This project was developed through the assistance of **Gemini Pro 3.1 Vibe Coding**.

### Architectural Improvements & Optimizations
The transition from a pure Python application to a native macOS environment brings substantial upgrades to speed, usability, and resource footprint:

1. **Native Metal/Neural Engine Acceleration**: By pre-compiling the YOLO and UNet (`fillGaps`) models into `.mlpackage` format using `coremltools`, we successfully mapped the neural network layers directly into Apple's Neural Engine (ANE) and GPU via the CoreML framework, utilizing iOS-native `CVPixelBuffer` rendering to implicitly handle pixel scaling rather than heavy CPU array parsing.
2. **Slicing Aided Hyper Inference (SAHI)**: The Swift implementation was retrofitted with an custom SAHI patch-iteration engine natively. To prevent sub-pixel streaks from disappearing during full-image down-scaling, large frames are sliced into overlapping 1024x1024 chunks natively inside the `YOLOPredictor` class. 
3. **Weighted Boxes Fusion (WBF) algorithm**: Classical Non-Maximum Suppression (NMS) bounding boxes were completely stripped out and replaced with trigonometric Weighted Boxes Fusion merging to perfectly match overlapping and angled (OBB) satellite streaks.
4. **vImage Max Blending**: The computationally expensive image stacking stage was migrated entirely away from OpenCV `numpy.maximum` matrices to the Apple Accelerate framework's highly optimized `vImageMax` vector instruction set.
5. **Memory Concurrency**: The pipeline introduces rigorous Swift `autoreleasepool` chunking and `Task.detached` concurrent actors, enabling users to stack upwards of 1,000 frames using gigabytes of local images without destroying the app's unified RAM consumption.
6. **UI/UX Ground-up Rewrite**: Crafted a zero-latency native UI using SwiftUI that binds non-blocking asynchronous progress polling to the rendering sequence. The canvas integrates `NSViewRepresentable` interception for deep Trackpad & Scroll Wheel interactivity without freezing the UI thread.
7. **Static persistent streak filtration**: Contains a newly implemented multi-frame tracking matrix that compares OBB centroid positions over the entirety of the sequence to automatically de-register and whitelist static foreground structures (telephone poles, buildings) from being masked.

---

## Chinese

StarTrails macOS 是开源机器学习星轨去痕工具 [gkyle/startrails](https://github.com/gkyle/startrails) 的原生 Apple Silicon 超高性能重构版本。它通过人工智能自动消除星轨照片中的飞机、人造卫星和太空垃圾轨迹。

它最初基于 Python (PySide6 和 CUDA) 构建。本代码仓库对其架构进行了深度的底层重写，使用了纯净的 **SwiftUI** 构建，并通过 **CoreML**、**Vision** 以及 **vDSP (Accelerate 框架)** 提供了深度的硬件加速支持。

本项目是在 **Gemini Pro 3.1 Vibe Coding** 的全程辅佐下编写开发的。

### 架构改进与核心优化
从纯 Python 转移到 macOS 原生生态环境，使得此应用在执行速度、友好程度和内存占用上迎来了质的飞跃：

1. **原生 Metal/神经网络引擎 (ANE) 硬件加速**：我们通过 `coremltools` 将 YOLO 和 UNet（`fillGaps` 模型）提前编译成了 `.mlpackage`，成功地通过 CoreML 将神经网络直接映射进了硬件底层。我们规避了沉重的 CPU 数组处理，并改用 iOS 原生的 `CVPixelBuffer` 向显存喂图，让苹果底层引擎自动并行缩放处理。
2. **切片辅助高超分辨率推理 (SAHI)**：Swift 实现版内置了纯原生编写的 SAHI 瓦片迭代引擎。为了防止细弱的星轨在全图拉伸缩放下被算法吃掉，大图会在 `YOLOPredictor` 中被自动裁切成重叠的 1024x1024 小块进行高精度局部侦察，然后再拼合结果。
3. **加权边界框融合 (WBF)**：剔除了传统的非极大值抑制 (NMS)，并使用针对带倾角的旋转矩形框 (OBB) 特别重构的加权框融合系统，运用三角函数精准合并多块探测结果中的破碎航迹线段。
4. **vImage Max 原生高强度叠图**：把消耗性能极大的堆栈混合阵列完全从 OpenCV 的 `numpy` 中抽离，并转换到了 Apple Accelerate (高性能矢量数学框架) 极度优化过的 `vImageMax` 像素级矢量运算组中。
5. **内存释放与并发处理**：运行管线全线引入了严苛的 Swift `autoreleasepool` 内存释放锁与 `Task.detached` 高并发机制。该应用现在可以毫无压力地一口气直接吞吐堆栈上千张高分原图且不撑爆和锁住 macOS 的统一内存 (Unified RAM)。
6. **界面从零重写**：采用了 SwiftUI 进行零延迟原生页面开发。在执行超高强度图片堆栈时，底层的异步任务链不会对主线程 UI 产生任何堵塞拖延；大图工作台植入了深度的 `NSViewRepresentable`底层劫持，实现真正的鼠标滚轮/触控板极速无级缩放与拖拽。
7. **静态物体静默保护特征层**：原生应用加入了多帧跟踪比对功能库，自动在所有的侦测结果中计算所有遮罩中心点的偏移方差。若它在一个位置出现次数超过整批图片序列的 50%，系统直接判定为误报的前景目标（比如电线杆或房屋天线）并放行，防止将其纳入飞机线的擦除流水线。

### License / 开源协议

This project adopts the **MIT License** inherited from the original [gkyle/startrails](https://github.com/gkyle/startrails) codebase due to its heavily derived architectural nature, in addition to attributing Gemini Vibe Coding implementations.

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Contact
Reach out via email at: `imufu@vip.qq.com`
