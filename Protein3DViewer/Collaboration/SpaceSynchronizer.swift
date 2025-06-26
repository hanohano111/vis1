import Foundation
import RealityKit
import ARKit
import simd

/// 空间同步管理器
@MainActor
class SpaceSynchronizer: ObservableObject {
    // MARK: - Properties
    private var anchor: AnchorEntity?
    private var worldTracking: WorldTrackingProvider
    private var collaborationManager: CollaborationManager
    
    @Published var isSpaceAligned: Bool = false
    @Published var alignmentError: String?
    
    // MARK: - Initialization
    init(collaborationManager: CollaborationManager) {
        self.collaborationManager = collaborationManager
        self.worldTracking = WorldTrackingProvider()
    }
    
    // MARK: - Public Methods
    func setupSharedSpace() async throws {
        // 创建共享锚点
        do {
            anchor = try await AnchorEntity(named: "sharedSpace")
            
            // 启动世界追踪
            try await ARKitSession().run([worldTracking])
        } catch {
            alignmentError = "无法启动世界追踪: \(error.localizedDescription)"
            throw error
        }
    }
    
    func getDeviceTransform() -> Transform? {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: Date().timeIntervalSince1970) else {
            return nil
        }
        return Transform(matrix: deviceAnchor.originFromAnchorTransform)
    }
    
    func updateDevicePosition() {
        guard let transform = getDeviceTransform() else { return }
        
        // 发送设备位置更新
        let message = CollaborationMessage.userPosition(position: transform.translation)
        // TODO: 通过 CollaborationManager 发送消息
    }
    
    func alignWithHost(_ hostTransform: Transform) {
        guard let deviceTransform = getDeviceTransform() else { return }
        
        // 计算相对变换
        let hostMatrix = hostTransform.matrix
        let deviceMatrix = deviceTransform.matrix
        let relativeMatrix = simd_mul(simd_inverse(hostMatrix), deviceMatrix)
        let relativeTransform = Transform(matrix: relativeMatrix)
        
        // 应用相对变换到模型
        // TODO: 更新模型位置
    }
} 