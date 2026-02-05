import Foundation
import AVFoundation

/// 程序化音频生成器
/// 用于在没有音频文件资源时，动态生成简单的音效（如爆炸、点击等）
class AudioGenerator {
    
    /// 生成爆炸音效 (白噪声 + 指数衰减)
    /// - Returns: 生成的 WAV 文件 URL
    static func generateExplosionSound() -> URL? {
        let sampleRate: Double = 44100
        let duration: Double = 1.0 // 1秒足够了
        let numSamples = Int(sampleRate * duration)
        
        // 创建临时文件路径
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("generated_explosion.wav")
        
        // 简单的 WAV Header 和 PCM 数据写入逻辑
        // 注意：为了代码简洁，这里使用 AudioFile API 而不是手动写字节
        
        var audioFile: AudioFileID?
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        let err = AudioFileCreateWithURL(
            fileURL as CFURL,
            kAudioFileWAVEType,
            &audioFormat,
            .eraseFile,
            &audioFile
        )
        
        guard err == noErr, let fileID = audioFile else {
            print("AudioGenerator: Failed to create file: \(err)")
            return nil
        }
        
        // 生成 PCM 数据 (Int16)
        // 算法：White Noise * Exponential Decay
        // 还可以加一个低通滤波器模拟低沉的爆炸声，或者简单地混合一点低频正弦波
        
        let bufferSize = numSamples * MemoryLayout<Int16>.size
        let buffer = UnsafeMutablePointer<Int16>.allocate(capacity: numSamples)
        defer { buffer.deallocate() }
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            
            // 1. 白噪声 (-1.0 to 1.0)
            let noise = Double.random(in: -1.0...1.0)
            
            // 2. 包络 (快速攻击，慢速衰减)
            // 简单的指数衰减：e^(-5t)
            let envelope = exp(-6.0 * t)
            
            // 3. 混合一点低频 (50Hz) 增加厚度
            let subBass = sin(2.0 * .pi * 50.0 * t) * 0.5 * envelope
            
            // 4. 最终混合
            var signal = (noise * 0.7 + subBass * 0.3) * envelope
            
            // Clipping
            if signal > 1.0 { signal = 1.0 }
            if signal < -1.0 { signal = -1.0 }
            
            // Convert to Int16
            buffer[i] = Int16(signal * 32767.0)
        }
        
        var bytesToWrite = UInt32(bufferSize)
        let writeErr = AudioFileWriteBytes(fileID, false, 0, &bytesToWrite, buffer)
        
        AudioFileClose(fileID)
        
        if writeErr == noErr {
            return fileURL
        } else {
            print("AudioGenerator: Failed to write bytes: \(writeErr)")
            return nil
        }
    }

    /// 生成 "Pew Pew" 激光/射击音效
    /// - Returns: 生成的 WAV 文件 URL
    static func generatePewSound() -> URL? {
        let sampleRate: Double = 44100
        let duration: Double = 0.2
        let numSamples = Int(sampleRate * duration)
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("generated_pew.wav")
        
        var audioFile: AudioFileID?
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        let err = AudioFileCreateWithURL(
            fileURL as CFURL,
            kAudioFileWAVEType,
            &audioFormat,
            .eraseFile,
            &audioFile
        )
        
        guard err == noErr, let fileID = audioFile else { return nil }
        
        let bufferSize = numSamples * MemoryLayout<Int16>.size
        let buffer = UnsafeMutablePointer<Int16>.allocate(capacity: numSamples)
        defer { buffer.deallocate() }
        
        // Chirp parameters
        let startFreq = 880.0
        let endFreq = 220.0
        let k = (endFreq - startFreq) / duration
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            // Phase = 2*pi * integral(f(t) dt)
            // f(t) = startFreq + k*t
            // Integral = startFreq*t + 0.5*k*t^2
            let currentPhase = 2.0 * .pi * (startFreq * t + 0.5 * k * t * t)
            
            let sine = sin(currentPhase)
            
            // Envelope: Fast attack, exponential decay
            let envelope = exp(-3.0 * progress)
            
            var signal = sine * envelope * 0.8
            
            if signal > 1.0 { signal = 1.0 }
            if signal < -1.0 { signal = -1.0 }
            
            buffer[i] = Int16(signal * 32767.0)
        }
        
        var bytesToWrite = UInt32(bufferSize)
        let _ = AudioFileWriteBytes(fileID, false, 0, &bytesToWrite, buffer)
        AudioFileClose(fileID)
        
        return fileURL
    }

    /// 生成蝴蝶扇动翅膀的音效
    /// - Returns: 生成的 WAV 文件 URL
    static func generateWingFlapSound() -> URL? {
        let sampleRate: Double = 44100
        let duration: Double = 0.15
        let numSamples = Int(sampleRate * duration)
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("generated_wing_flap.wav")
        
        var audioFile: AudioFileID?
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        let err = AudioFileCreateWithURL(
            fileURL as CFURL,
            kAudioFileWAVEType,
            &audioFormat,
            .eraseFile,
            &audioFile
        )
        
        guard err == noErr, let fileID = audioFile else { return nil }
        
        let bufferSize = numSamples * MemoryLayout<Int16>.size
        let buffer = UnsafeMutablePointer<Int16>.allocate(capacity: numSamples)
        defer { buffer.deallocate() }
        
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let progress = t / duration
            
            // 简单的低频正弦波 (80Hz - 120Hz)
            let freq = 100.0
            let sine = sin(2.0 * .pi * freq * t)
            
            // 加上一点点高频噪音模拟空气摩擦
            let noise = Double.random(in: -0.2...0.2)
            
            // 包络：正弦形状的包络，模拟一次扇动
            // sin(pi * progress) 会在 0 到 1 之间形成一个半圆拱形
            let envelope = sin(.pi * progress)
            
            var signal = (sine * 0.8 + noise) * envelope
            
            if signal > 1.0 { signal = 1.0 }
            if signal < -1.0 { signal = -1.0 }
            
            buffer[i] = Int16(signal * 32767.0)
        }
        
        var bytesToWrite = UInt32(bufferSize)
        let _ = AudioFileWriteBytes(fileID, false, 0, &bytesToWrite, buffer)
        AudioFileClose(fileID)
        
        return fileURL
    }
}
