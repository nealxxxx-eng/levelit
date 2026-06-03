import UIKit
import LevelItShared

/// 食物照片本地存储管理
enum FoodImageStore {
    private static let directoryName = "FoodImages"
    private static let jpegQuality: CGFloat = 0.85
    private static let maxDimension: CGFloat = 1600

    /// 获取存储目录路径（自动创建）
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        excludeFromBackup(dir)
        return dir
    }

    /// 保存食物照片，返回文件名
    @discardableResult
    static func save(image: UIImage, taskId: String) -> String? {
        let fileName = "\(taskId).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        guard let data = jpegDataFittingLimit(image) else { return nil }
        return write(data: data, to: fileURL, fileName: fileName)
    }

    /// 从 Data 保存（用于 FoodAnalysisResult.imageData 链路）
    @discardableResult
    static func save(data: Data, taskId: String) -> String? {
        let fileName = "\(taskId).jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        let outputData: Data
        if data.count <= AppConstants.maxFoodImageSize {
            outputData = data
        } else if let image = UIImage(data: data),
                  let compressed = jpegDataFittingLimit(image) {
            outputData = compressed
        } else {
            return nil
        }
        return write(data: outputData, to: fileURL, fileName: fileName)
    }

    private static func write(data: Data, to fileURL: URL, fileName: String) -> String? {
        do {
            try data.write(to: fileURL, options: .atomic)
            excludeFromBackup(fileURL)
            protectFile(at: fileURL)
            return fileName
        } catch {
            print("[FoodImageStore] Save failed: \(error)")
            return nil
        }
    }

    /// 读取食物照片
    static func load(fileName: String) -> UIImage? {
        let fileURL = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    /// 通过 taskId 读取
    static func load(taskId: String) -> UIImage? {
        load(fileName: "\(taskId).jpg")
    }

    /// 删除食物照片
    static func delete(fileName: String) {
        let fileURL = directory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 照片是否存在
    static func exists(taskId: String) -> Bool {
        let fileURL = directory.appendingPathComponent("\(taskId).jpg")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private static func jpegDataFittingLimit(_ image: UIImage) -> Data? {
        var dimension = min(maxDimension, max(image.size.width, image.size.height))
        var quality = jpegQuality

        while dimension >= 320 {
            let resized = resize(image, maxDimension: dimension)
            while quality >= 0.45 {
                guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
                if data.count <= AppConstants.maxFoodImageSize {
                    return data
                }
                quality -= 0.1
            }
            dimension *= 0.8
            quality = jpegQuality
        }

        guard let fallback = resize(image, maxDimension: 320).jpegData(compressionQuality: 0.45),
              fallback.count <= AppConstants.maxFoodImageSize else {
            return nil
        }
        return fallback
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }

        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private static func protectFile(at url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}
