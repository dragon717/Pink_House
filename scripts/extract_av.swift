#!/usr/bin/swift

import Foundation
import AVFoundation

// 扩展 String 以方便路径处理
extension String {
    var fileURL: URL {
        return URL(fileURLWithPath: self)
    }
    var fileName: String {
        return URL(fileURLWithPath: self).deletingPathExtension().lastPathComponent
    }
    var fileExtension: String {
        return URL(fileURLWithPath: self).pathExtension
    }
    var directory: String {
        return URL(fileURLWithPath: self).deletingLastPathComponent().path
    }
}

class MediaSeparator {
    let inputPath: String
    let fileManager = FileManager.default
    
    init(inputPath: String) {
        self.inputPath = inputPath
    }
    
    func run() {
        guard fileManager.fileExists(atPath: inputPath) else {
            print("❌ 错误：文件不存在 - \(inputPath)")
            exit(1)
        }
        
        let asset = AVAsset(url: inputPath.fileURL)
        
        // 异步加载必要的属性
        let keys = ["tracks", "duration"]
        asset.loadValuesAsynchronously(forKeys: keys) {
            var error: NSError? = nil
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            
            if status == .loaded {
                self.startExtraction(asset: asset)
            } else {
                print("❌ 无法加载视频轨道信息: \(error?.localizedDescription ?? "未知错误")")
                exit(1)
            }
        }
        
        dispatchMain()
    }
    
    private func startExtraction(asset: AVAsset) {
        let group = DispatchGroup()
        
        print("🎬 开始处理: \(inputPath.fileName)")
        
        // 1. 提取音频
        group.enter()
        extractAudio(from: asset) { success in
            group.leave()
        }
        
        // 2. 提取无声视频
        group.enter()
        extractVideo(from: asset) { success in
            group.leave()
        }
        
        group.notify(queue: .main) {
            print("✨ 所有任务完成！")
            exit(0)
        }
    }
    
    private func extractAudio(from asset: AVAsset, completion: @escaping (Bool) -> Void) {
        let outputURL = URL(fileURLWithPath: inputPath.directory)
            .appendingPathComponent("\(inputPath.fileName)_audio.m4a")
        
        // 删除旧文件
        try? fileManager.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            print("❌ 无法创建音频导出会话")
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        print("🎵 正在提取音频...")
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("✅ 音频已保存: \(outputURL.lastPathComponent)")
                completion(true)
            case .failed:
                print("❌ 音频提取失败: \(exportSession.error?.localizedDescription ?? "未知错误")")
                completion(false)
            case .cancelled:
                print("⚠️ 音频提取取消")
                completion(false)
            default:
                completion(false)
            }
        }
    }
    
    private func extractVideo(from asset: AVAsset, completion: @escaping (Bool) -> Void) {
        let outputURL = URL(fileURLWithPath: inputPath.directory)
            .appendingPathComponent("\(inputPath.fileName)_video.mov")
        
        // 删除旧文件
        try? fileManager.removeItem(at: outputURL)
        
        let composition = AVMutableComposition()
        
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            print("⚠️ 未找到视频轨道")
            completion(false)
            return
        }
        
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("❌ 无法创建合成视频轨道")
            completion(false)
            return
        }
        
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
        } catch {
            print("❌ 插入视频轨道失败: \(error)")
            completion(false)
            return
        }
        
        // 使用 HighestQuality 进行重编码（因为 composition 无法直接 pass-through）
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("❌ 无法创建视频导出会话")
            completion(false)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        print("📹 正在提取无声视频 (正在重新编码，请稍候)...")
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                print("✅ 无声视频已保存: \(outputURL.lastPathComponent)")
                completion(true)
            case .failed:
                print("❌ 视频提取失败: \(exportSession.error?.localizedDescription ?? "未知错误")")
                completion(false)
            case .cancelled:
                print("⚠️ 视频提取取消")
                completion(false)
            default:
                completion(false)
            }
        }
    }
}

// 主入口
if CommandLine.arguments.count < 2 {
    print("使用方法: swift extract_av.swift <video_file_path>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let separator = MediaSeparator(inputPath: inputPath)
separator.run()
