import Flutter
import UIKit
import QuickLook
import os.log

class FilePickerHandler: NSObject, QLPreviewControllerDataSource {
    private let logger = Logger(subsystem: "FilePicker", category: "Handler")
    private var methodChannel: FlutterMethodChannel
    private var pendingResult: FlutterResult?
    private var previewController: QLPreviewController?
    private var previewFileURL: URL?
    
    init(methodChannel: FlutterMethodChannel) {
        self.methodChannel = methodChannel
        super.init()
        
        setupFilePickerCallbacks()
    }
    
    private func setupFilePickerCallbacks() {
        FilePicker.shared.onFilePicked = { [weak self] filePaths in
            guard let self = self, let result = self.pendingResult else { return }
            
            self.logger.info("Files picked: \(filePaths.count)")
            
            let resultData: [[String: Any]] = filePaths.map { filePath in
                let fileURL = URL(fileURLWithPath: filePath)
                let fileName = fileURL.lastPathComponent
                let fileSize = self.getFileSize(at: fileURL)
                let fileExtension = fileURL.pathExtension.lowercased()
                
                return [
                    "filePath": filePath,
                    "fileName": fileName,
                    "fileSize": fileSize,
                    "extension": fileExtension
                ]
            }
            
            DispatchQueue.main.async {
                result(resultData)
                self.pendingResult = nil
            }
        }
        
        FilePicker.shared.onCanceled = { [weak self] in
            guard let self = self, let result = self.pendingResult else { return }
            
            self.logger.info("File picker cancelled")
            
            DispatchQueue.main.async {
                result([])
                self.pendingResult = nil
            }
        }
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        logger.info("Received method call: \(call.method)")
        
        switch call.method {
        case "pickFiles":
            pickFiles(call, result: result)
        case "openFile":
            openFile(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func pickFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        logger.info("pickFiles called")
        
        guard let args = call.arguments as? [String: Any] else {
            logger.error("Invalid arguments")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        
        let maxCount = args["maxCount"] as? Int ?? 1
        let allowedTypes = args["allowedMimeTypes"] as? [String] ?? []
        
        logger.info("maxCount: \(maxCount), allowedTypes: \(allowedTypes)")
        
        self.pendingResult = result
        
        // Ensure UI operations happen on main thread
        //
        // 确保 UI 操作在主线程上进行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("Calling FilePicker.shared.pickFiles")
            let config = FilePickerConfig(maxCount: maxCount, allowedTypes: allowedTypes)
            FilePicker.shared.pickFiles(config: config)
        }
    }
    
    private func openFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        logger.info("openFile called")
        
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
            logger.error("Invalid arguments for openFile")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "File path is required", details: nil))
            return
        }
        
        logger.info("Opening file: \(filePath)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                result(false)
                return
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            
            // Check if file exists
            //
            // 检查文件是否存在
            guard FileManager.default.fileExists(atPath: filePath) else {
                self.logger.error("File does not exist: \(filePath)")
                result(false)
                return
            }
            
            // Get the root view controller
            //
            // 获取根视图控制器
            guard let rootViewController = self.getRootViewController() else {
                self.logger.error("No root view controller found")
                result(false)
                return
            }
            
            // Use QuickLook to preview the file
            //
            // 使用 QuickLook 预览文件
            let previewController = QLPreviewController()
            previewController.dataSource = self
            
            // Store the file URL and preview controller
            //
            // 存储文件 URL 和预览控制器
            self.previewFileURL = fileURL
            self.previewController = previewController
            
            // Present the preview controller
            //
            // 展示预览控制器
            rootViewController.present(previewController, animated: true) {
                self.logger.info("File preview presented successfully")
            }
            
            result(true)
        }
    }
    
    private func getRootViewController() -> UIViewController? {
        var rootViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                rootViewController = keyWindow.rootViewController
            } else {
                rootViewController = UIApplication.shared.windows.first?.rootViewController
            }
        } else {
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
    
    private func getFileSize(at url: URL) -> Int {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? Int) ?? 0
        } catch {
            logger.error("Failed to get file size: \(error.localizedDescription)")
            return 0
        }
    }
    
    func dispose() {
        logger.info("Disposing FilePickerHandler")
        pendingResult = nil
        previewController = nil
        previewFileURL = nil
        FilePicker.shared.onFilePicked = nil
        FilePicker.shared.onCanceled = nil
    }
    
    // MARK: - QLPreviewControllerDataSource
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return previewFileURL != nil ? 1 : 0
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return previewFileURL! as QLPreviewItem
    }
}
