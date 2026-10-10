import Foundation

/// 旧版本在终止前只落了图片、没写最终清单；按原请求环境找回这些工作目录。
public enum OpsDownloadedMediaRecovery {
    public static func directories(in jobs: URL, environment: String, fileManager: FileManager = .default) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(at: jobs, includingPropertiesForKeys: nil)) ?? []
        return entries.sorted { $0.path < $1.path }.compactMap { job in
            guard job.lastPathComponent.hasPrefix("fetch-"),
                  let data = try? Data(contentsOf: job.appendingPathComponent("request.json")),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  request["targetEnvironment"] as? String == environment,
                  let path = request["outputDirectory"] as? String else { return nil }
            let images = job.appendingPathComponent("images", isDirectory: true).resolvingSymlinksInPath()
            guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path == images.path,
                  fileManager.fileExists(atPath: images.path) else { return nil }
            return images
        }
    }
}
