import SwiftUI
import RealityKit

@MainActor
class ProteinViewModel: ObservableObject {
    @Published var isRotating: Bool = false
    @Published var isMoving: Bool = false
    @Published var isScaling: Bool = false
    @Published var isModelLoaded: Bool = false
    @Published var isChangingColor: Bool = false
    @Published var lastAction: String = ""
    @Published var selectedColor: Color? = nil {
        didSet {
            // 当颜色变化时立即通知UI更新
            if selectedColor != oldValue {
                print("选中颜色已更改: \(String(describing: oldValue)) -> \(String(describing: selectedColor))")
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    func toggleRotation() {
        print("🔄 切换旋转模式: 从\(isRotating)到\(!isRotating)")
        isRotating.toggle()
        if isRotating {
            lastAction = "旋转模式已激活，可使用旋转手势调整模型角度"
            isMoving = false
            isScaling = false
            isChangingColor = false
        } else {
            lastAction = "旋转模式已关闭"
        }
    }
    
    func toggleMoving() {
        print("🔄 切换移动模式: 从\(isMoving)到\(!isMoving)")
        isMoving.toggle()
        if isMoving {
            lastAction = "移动模式已激活，可使用拖拽手势调整模型位置"
            isRotating = false
            isScaling = false
            isChangingColor = false
        } else {
            lastAction = "移动模式已关闭"
        }
    }
    
    func toggleScaling() {
        print("🔄 切换缩放模式: 从\(isScaling)到\(!isScaling)")
        isScaling.toggle()
        if isScaling {
            lastAction = "缩放模式已激活，可使用捏合手势调整模型大小"
            isRotating = false
            isMoving = false
            isChangingColor = false
        } else {
            lastAction = "缩放模式已关闭"
        }
    }
    
    func toggleColorChange() {
        print("🔄 切换颜色修改模式: 从\(isChangingColor)到\(!isChangingColor)")
        
        // 播放触觉反馈
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        // 切换颜色修改模式
        isChangingColor.toggle()
        
        if isChangingColor {
            // 进入颜色修改模式
            lastAction = "请从颜色面板中选择一个颜色"
            // 关闭其他模式
            isRotating = false
            isMoving = false
            isScaling = false
            // 重置选中的颜色
            selectedColor = nil
        } else {
            // 退出颜色修改模式
            lastAction = "已退出颜色修改模式"
            // 清除选中的颜色
            selectedColor = nil
        }
        
        // 通知UI更新
        objectWillChange.send()
    }
    
    // 重置所有操作状态
    func resetAllModes() {
        print("🔄 重置所有模式")
        isRotating = false
        isMoving = false
        isScaling = false
        isChangingColor = false
        lastAction = "所有操作模式已重置"
    }
} 