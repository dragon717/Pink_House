---
name: "swiftui-image-viewer"
description: "SwiftUI 图片查看器实现指南。解决 fullScreenCover 白屏、视图延迟创建、图片异步加载等问题。Invoke when implementing image viewer with zoom/pan in SwiftUI."
---

# SwiftUI 图片查看器实现指南

## 问题场景

在 SwiftUI 中实现点击图片查看大图功能时，常见以下问题：

1. **白屏问题**：使用 `fullScreenCover` 打开图片查看器时，视图创建被延迟，导致白屏
2. **图片加载时机**：异步加载图片时，视图容器未准备好
3. **缩放功能**：需要实现双指缩放、双击放大等功能

## 根本原因

`fullScreenCover` 的视图创建时机问题：
- 当 content 包含复杂的条件表达式（如 `if let`）时
- SwiftUI 可能延迟创建视图，直到某些条件满足
- 导致 `UIViewRepresentable` 的 `makeUIView`/`updateUIView` 延迟调用

## 解决方案

### 方案 1：使用 Sheet 替代 FullScreenCover（推荐）

```swift
.sheet(isPresented: $showingImageViewer) {
    ImageViewer(imagePath: imagePath)
        .presentationBackground(.black)
        .ignoresSafeArea()
}
```

**优点**：
- 视图创建时机更可靠
- 通过 `.presentationBackground(.black)` 实现全屏黑色背景

### 方案 2：确保状态预设置

如果使用 `fullScreenCover`，确保路径在显示前已设置：

```swift
// 不要这样
.onTapGesture {
    imagePath = newPath  // 状态更新和 sheet 显示同时进行
    showingViewer = true
}

// 推荐这样
.onTapGesture {
    imagePath = newPath
    DispatchQueue.main.async {
        showingViewer = true  // 延迟显示，确保状态已更新
    }
}
```

### 方案 3：使用 Group 包装条件内容

```swift
.fullScreenCover(isPresented: $showingViewer) {
    Group {  // 使用 Group 确保视图立即创建
        if let path = imagePath {
            ImageViewer(imagePath: path)
        } else {
            Color.black
        }
    }
}
```

## 完整实现示例

### 1. 图片查看器组件

```swift
struct ImageViewer: View {
    let imagePath: String
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 使用已有的 ZoomableImageView
            ZoomableImageView(imagePath: imagePath)
            
            // 顶部控制栏
            VStack {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
            }
        }
    }
}
```

### 2. 可缩放图片视图（UIKit 桥接）

```swift
struct ZoomableImageView: UIViewRepresentable {
    let imagePath: String
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = scrollView.bounds
        
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        
        // 双击缩放
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.currentPath != imagePath {
            context.coordinator.currentPath = imagePath
            uiView.zoomScale = 1.0
            
            Task {
                if let image = await ImageManager.shared.loadImageAsync(fileName: imagePath) {
                    await MainActor.run {
                        context.coordinator.imageView?.image = image
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var currentPath: String?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scrollSize = scrollView.frame.size
                let size = CGSize(width: scrollSize.width / 3,
                                  height: scrollSize.height / 3)
                let origin = CGPoint(x: point.x - size.width / 2,
                                     y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}
```

### 3. 使用示例

```swift
struct DetailView: View {
    @State private var showingImageViewer = false
    @State private var selectedImagePath: String?
    
    var body: some View {
        VStack {
            // 缩略图
            Image(uiImage: loadThumbnail())
                .onTapGesture {
                    selectedImagePath = "image_path"
                    showingImageViewer = true
                }
        }
        .sheet(isPresented: $showingImageViewer) {
            if let path = selectedImagePath {
                ImageViewer(imagePath: path) {
                    showingImageViewer = false
                }
                .presentationBackground(.black)
                .ignoresSafeArea()
            }
        }
    }
}
```

## 调试技巧

在 `UIViewRepresentable` 中添加日志追踪视图生命周期：

```swift
func makeUIView(context: Context) -> UIScrollView {
    print("[ZoomableImageView] makeUIView called")
    // ...
}

func updateUIView(_ uiView: UIScrollView, context: Context) {
    print("[ZoomableImageView] updateUIView called, path: \(imagePath)")
    // ...
}
```

## 最佳实践总结

1. **优先使用 `sheet`** 而不是 `fullScreenCover`，视图创建更可靠
2. **使用 `.presentationBackground(.black)`** 实现全屏黑色背景
3. **延迟显示策略**：如果必须用 `fullScreenCover`，先设置数据再延迟显示
4. **使用 `Group` 包装**：避免复杂的条件表达式影响视图创建
5. **UIKit 桥接**：对于复杂手势（缩放、拖动），使用 `UIViewRepresentable` 桥接 `UIScrollView`
