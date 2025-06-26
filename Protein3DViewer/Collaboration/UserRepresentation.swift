import Foundation
import RealityKit
import SwiftUI

/// 用户表示管理器
@MainActor
class UserRepresentation: ObservableObject {
    // MARK: - Properties
    private var userEntities: [String: ModelEntity] = [:]
    private var collaborationManager: CollaborationManager
    
    @Published var connectedUsers: [String: UserInfo] = [:]
    
    // MARK: - Types
    struct UserInfo {
        let id: String
        var position: SIMD3<Float>
        var avatar: ModelEntity
        var name: String
    }
    
    // MARK: - Initialization
    init(collaborationManager: CollaborationManager) {
        self.collaborationManager = collaborationManager
    }
    
    // MARK: - Public Methods
    func createUserAvatar(for userID: String, name: String) -> ModelEntity {
        // 创建用户头像实体
        let avatar = ModelEntity(mesh: .generateSphere(radius: 0.05))
        avatar.model?.materials = [SimpleMaterial(color: .blue, isMetallic: false)]
        
        // 创建用户名标签
        let textMesh = MeshResource.generateText(
            name,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.1),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let textEntity = ModelEntity(mesh: textMesh)
        textEntity.model?.materials = [SimpleMaterial(color: .white, isMetallic: false)]
        textEntity.position = [0, 0.08, 0]
        
        avatar.addChild(textEntity)
        
        // 存储用户信息
        let userInfo = UserInfo(id: userID, position: .zero, avatar: avatar, name: name)
        connectedUsers[userID] = userInfo
        userEntities[userID] = avatar
        
        return avatar
    }
    
    func updateUserPosition(_ userID: String, position: SIMD3<Float>) {
        guard var userInfo = connectedUsers[userID] else { return }
        userInfo.position = position
        connectedUsers[userID] = userInfo
        
        // 更新头像位置
        userEntities[userID]?.position = position
    }
    
    func removeUser(_ userID: String) {
        // 移除用户实体
        userEntities[userID]?.removeFromParent()
        userEntities.removeValue(forKey: userID)
        connectedUsers.removeValue(forKey: userID)
    }
    
    func clearAllUsers() {
        // 清除所有用户
        userEntities.values.forEach { $0.removeFromParent() }
        userEntities.removeAll()
        connectedUsers.removeAll()
    }
} 