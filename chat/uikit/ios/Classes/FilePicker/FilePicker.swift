import Foundation
import UIKit
import UniformTypeIdentifiers
import os.log

public struct FilePickerConfig {
    var maxCount: Int = 1
    var allowedTypes: [String] = []
    
    public init(maxCount: Int = 1, allowedTypes: [String] = []) {
        self.maxCount = maxCount
        self.allowedTypes = allowedTypes
    }
}

public class FilePicker: NSObject, UIDocumentPickerDelegate {
    private let logger = Logger(subsystem: "FilePicker", category: "Core")
    
    public static let shared = FilePicker()
    
    public var onFilePicked: ((_ filePaths: [String]) -> Void)?
    public var onCanceled: (() -> Void)?
    
    private weak var presentingViewController: UIViewController?
    private var currentConfig: FilePickerConfig?
    
    private override init() {
        super.init()
    }
    
    public func pickFiles(config: FilePickerConfig) {
        logger.info("pickFiles called with maxCount: \(config.maxCount)")
        
        self.currentConfig = config
        
        // Get root view controller - iOS 13+ compatible
        //
        // 获取根视图控制器 - 兼容 iOS 13+
        guard let rootViewController = getRootViewController() else {
            logger.error("No root view controller found")
            onCanceled?()
            return
        }
        
        self.presentingViewController = rootViewController
        
        // Create document picker
        //
        // 创建文档选择器
        let documentPicker: UIDocumentPickerViewController
        
        if #available(iOS 14.0, *) {
            let contentTypes = getContentTypes(from: config.allowedTypes)
            // Use asCopy: true to enable file selection and copy mode
            // Without asCopy: true, the picker opens files for viewing instead of selecting
            //
            // 使用 asCopy: true 启用文件选择和复制模式 没有 asCopy: true 时，选择器会打开文件进行查看，而不是选择
            documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        } else {
            let documentTypes = config.allowedTypes.isEmpty ? ["public.item"] : config.allowedTypes
            documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        }
        
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = config.maxCount > 1
        
        // Present on main thread
        //
        // 在主线程呈现
        DispatchQueue.main.async { [weak self] in
            self?.presentingViewController?.present(documentPicker, animated: true)
        }
    }
    
    // MARK: - UIDocumentPickerDelegate
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        logger.info("Picked \(urls.count) documents")
        
        var filePaths: [String] = []
        
        for url in urls {
            let securityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if securityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Copy file to app's documents directory
            //
            // 将文件复制到应用的文档目录
            if let copiedPath = copyFileToDocuments(url: url) {
                filePaths.append(copiedPath)
            } else {
                logger.error("Failed to copy file: \(url.lastPathComponent)")
            }
        }
        
        if filePaths.isEmpty {
            logger.warning("No files were successfully copied")
            onCanceled?()
        } else {
            onFilePicked?(filePaths)
        }
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        logger.info("Document picker was cancelled")
        onCanceled?()
    }
    
    // MARK: - Helper Methods
    //
    // 标记: - 辅助方法
    
    private func getRootViewController() -> UIViewController? {
        var rootViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            // iOS 13+ 使用 scene-based approach
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                rootViewController = keyWindow.rootViewController
            } else {
                // Fallback to first window
                //
                // 回退到第一个窗口
                rootViewController = UIApplication.shared.windows.first?.rootViewController
            }
        } else {
            // iOS 12 及以下
            rootViewController = UIApplication.shared.keyWindow?.rootViewController
        }
        
        // Find the topmost presented view controller
        //
        // 找到最顶部的呈现视图控制器
        return getTopmostViewController(from: rootViewController)
    }
    
    /// Recursively find the topmost presented view controller
    ///
    /// 递归查找最顶部的呈现视图控制器
    private func getTopmostViewController(from viewController: UIViewController?) -> UIViewController? {
        guard let vc = viewController else { return nil }
        
        if let presented = vc.presentedViewController {
            return getTopmostViewController(from: presented)
        }
        
        if let navigationController = vc as? UINavigationController {
            return getTopmostViewController(from: navigationController.visibleViewController)
        }
        
        if let tabBarController = vc as? UITabBarController {
            return getTopmostViewController(from: tabBarController.selectedViewController)
        }
        
        return vc
    }
    
    @available(iOS 14.0, *)
    private func getContentTypes(from allowedTypes: [String]) -> [UTType] {
        if allowedTypes.isEmpty {
            return [.item]
        }
        
        var contentTypes: [UTType] = []
        for typeString in allowedTypes {
            // Try to parse as UTType identifier
            //
            // 尝试解析为 UTType 标识符
            if let utType = UTType(typeString) {
                contentTypes.append(utType)
            } else if let utType = UTType(filenameExtension: typeString.replacingOccurrences(of: ".", with: "")) {
                contentTypes.append(utType)
            }
        }
        
        return contentTypes.isEmpty ? [.item] : contentTypes
    }
    
    private func copyFileToDocuments(url: URL) -> String? {
        do {
            let fileManager = FileManager.default
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let filesDirectory = documentsDirectory.appendingPathComponent("files", isDirectory: true)
            
            // Create files directory if it doesn't exist
            //
            // 如果文件目录不存在则创建
            if !fileManager.fileExists(atPath: filesDirectory.path) {
                try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Generate unique filename
            //
            // 生成唯一文件名
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let fileName = url.lastPathComponent
            let uniqueFileName = "\(timestamp)_\(fileName)"
            let destinationURL = filesDirectory.appendingPathComponent(uniqueFileName)
            
            // Remove existing file if it exists
            //
            // 如果文件存在则删除
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy file
            //
            // 复制文件
            try fileManager.copyItem(at: url, to: destinationURL)
            
            logger.info("File copied to: \(destinationURL.path)")
            return destinationURL.path
            
        } catch {
            logger.error("Error copying file: \(error.localizedDescription)")
            return nil
        }
    }
}
