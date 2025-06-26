import Foundation
import MultipeerConnectivity
import RealityKit
import SwiftUI

/// 协作消息类型
enum CollaborationMessage: Codable {
    case modelTransform(transform: Transform)
    case userPosition(position: SIMD3<Float>)
    case annotation(annotation: ModelAnnotation)
    case joinRequest(userID: String)
    case modelState(state: ModelState)
    case syncRequest(from: String)
    case userState(userData: Data)
    case disconnect
}

/// 模型状态
struct ModelState: Codable {
    var transform: Transform
    var scale: SIMD3<Float>
    var annotations: [ModelAnnotation]
    var selectedAtoms: Set<Int>
    var currentModel: String? // 当前模型名称
    var modelData: Data? // 新增：模型数据
}

/// 注释结构
struct Annotation: Codable, Identifiable {
    let id: UUID
    let position: SIMD3<Float>
    let text: String
    let authorID: String
    let timestamp: Date
    let color: SIMD4<Float>
}

/// 协作管理器
@MainActor
class CollaborationManager: NSObject, ObservableObject {
    // MARK: - Properties
    @Published var isConnected = false
    @Published var isHosting = false
    @Published var isHost = false
    @Published var errorMessage: String?
    @Published var showSyncRequest = false
    @Published var syncRequestFrom = ""
    @Published var connectedPeers: [MCPeerID] = [] {
        didSet {
            print("[CollaborationManager] 当前连接的 peers: \(connectedPeers.map { $0.displayName })")
        }
    }
    
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peerID: MCPeerID?
    private var receivedData: [MCPeerID: Data] = [:]
    private let serviceType = "protein-viewer"
    private var hasConfirmedSync: Bool = false // 新增：是否已经确认过同步
    
    /// 用于获取当前模型状态的闭包，由外部注入
    var currentModelStateProvider: (() -> ModelState)?
    
    /// 用于获取当前模型数据的闭包
    var currentModelDataProvider: (() -> Data)?
    
    var onModelStateReceived: ((ModelState) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        print("[CollaborationManager] 初始化")
    }
    
    // MARK: - Public Methods
    func initialize(session: MCSession,
                   modelStateProvider: @escaping () -> ModelState,
                   modelDataProvider: @escaping () -> Data,
                   onModelStateReceived: @escaping (ModelState) -> Void) {
        print("[CollaborationManager] 初始化协作管理器")
        self.session = session
        self.currentModelStateProvider = modelStateProvider
        self.currentModelDataProvider = modelDataProvider
        self.onModelStateReceived = onModelStateReceived
        session.delegate = self
    }
    
    // MARK: - Setup
    private func setupMultipeerConnectivity() {
        let peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        print("[CollaborationManager] 初始化会话，设备名称: \(peerID.displayName)")
    }
    
    // MARK: - Public Methods
    func startHosting() {
        guard let session = session else {
            errorMessage = "会话未初始化"
            return
        }
        
        // 如果已经在主持会话，先停止
        if isHosting {
            stopHosting()
        }
        
        // 确保没有活动的浏览器
        if browser != nil {
            browser?.stopBrowsingForPeers()
            browser = nil
        }
        
        // 重置会话状态
        session.disconnect()
        connectedPeers.removeAll()
        isConnected = false
        hasConfirmedSync = false
        
        // 创建新的广播者
        advertiser = MCNearbyServiceAdvertiser(
            peer: session.myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        isHosting = true
        isHost = true
        print("[CollaborationManager] 开始主持会话")
    }
    
    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isHosting = false
        isHost = false
        print("[CollaborationManager] 停止主持会话")
    }
    
    func joinSession() {
        guard let session = session else {
            errorMessage = "会话未初始化"
            return
        }
        
        // 如果已经在浏览会话，先停止
        if browser != nil {
            browser?.stopBrowsingForPeers()
            browser = nil
        }
        
        // 确保没有活动的广播者
        if advertiser != nil {
            advertiser?.stopAdvertisingPeer()
            advertiser = nil
        }
        
        // 重置会话状态
        session.disconnect()
        connectedPeers.removeAll()
        isConnected = false
        hasConfirmedSync = false
        
        // 创建并启动浏览器
        browser = MCNearbyServiceBrowser(peer: session.myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        isHost = false
        print("[CollaborationManager] 开始搜索会话")
    }
    
    func leaveSession() {
        browser?.stopBrowsingForPeers()
        browser = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        isConnected = false
        isHosting = false
        isHost = false
        connectedPeers.removeAll()
        print("[CollaborationManager] 离开会话")
    }
    
    func requestModelSync() {
        guard let session = session else {
            print("会话未初始化")
            return
        }
        
        // 检查是否有连接的节点
        guard !session.connectedPeers.isEmpty else {
            print("没有连接的节点")
            return
        }
        
        do {
            let message = CollaborationMessage.syncRequest(from: session.myPeerID.displayName)
            let messageData = try JSONEncoder().encode(message)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            print("已发送同步请求")
        } catch {
            print("发送同步请求失败：\(error.localizedDescription)")
        }
    }
    
    func sendModelState(_ state: ModelState) {
        guard let session = session, !connectedPeers.isEmpty else { return }
        // 新增：确保所有 peer 都是 .connected 状态
        let allConnected = session.connectedPeers.count == connectedPeers.count
        if !allConnected {
            print("[CollaborationManager] 有 peer 未完全连接，暂不发送模型状态")
            return
        }
        do {
            // 获取当前模型数据
            var updatedState = state
            updatedState.modelData = currentModelDataProvider?()
            
            let message = CollaborationMessage.modelState(state: updatedState)
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: connectedPeers, with: .reliable)
        } catch {
            errorMessage = "发送模型状态失败: \(error.localizedDescription)"
        }
    }
    
    func handleSyncRequest(from peer: MCPeerID, accept: Bool) {
        print("[CollaborationManager] 处理来自 \(peer.displayName) 的同步请求，接受状态：\(accept)")
        if accept {
            // 检查会话是否存在
            guard let session = session else {
                print("[CollaborationManager] 错误：会话未初始化")
                return
            }
            
            // 检查模型状态提供者是否存在
            guard let modelStateProvider = currentModelStateProvider else {
                print("[CollaborationManager] 错误：模型状态提供者未设置")
                return
            }
            
            // 获取当前模型状态
            let modelState = modelStateProvider()
            print("[CollaborationManager] 获取到当前模型状态：\(modelState)")
            
            do {
                // 获取当前模型数据
                var updatedState = modelState
                if let modelData = currentModelDataProvider?() {
                    if modelData.count == 0 {
                        print("[CollaborationManager] 错误：模型数据为空")
                        return
                    }
                    updatedState.modelData = modelData
                    print("[CollaborationManager] 获取到当前模型数据，大小：\(modelData.count) 字节")
                } else {
                    print("[CollaborationManager] 错误：无法获取当前模型数据")
                    return
                }
                
                let message = CollaborationMessage.modelState(state: updatedState)
                let messageData = try JSONEncoder().encode(message)
                
                // 验证编码后的数据
                print("[CollaborationManager] 编码后的消息大小：\(messageData.count) 字节")
                
                try session.send(messageData, toPeers: [peer], with: .reliable)
                print("[CollaborationManager] 已发送模型状态到 \(peer.displayName)")
                
                // 标记已确认同步
                hasConfirmedSync = true
            } catch {
                print("[CollaborationManager] 发送模型状态失败：\(error.localizedDescription)")
            }
        }
        // 重置同步请求状态
        showSyncRequest = false
        syncRequestFrom = ""
    }
    
    // 处理接收到的模型数据
    private func handleReceivedModelData(_ modelState: ModelState) {
        print("[CollaborationManager] 处理接收到的模型数据")
        
        // 验证模型数据
        guard let modelData = modelState.modelData else {
            print("[CollaborationManager] 错误：接收到的模型数据为空")
            return
        }
        
        if modelData.count == 0 {
            print("[CollaborationManager] 错误：接收到的模型数据大小为0")
            return
        }
        
        print("[CollaborationManager] 接收到的模型数据大小：\(modelData.count) 字节")
        
        // 确保在主线程更新UI
        Task { @MainActor in
            // 调用回调函数处理模型状态
            self.onModelStateReceived?(modelState)
        }
    }
    
    // 处理接收到的用户数据
    private func handleReceivedUserData(_ userData: Data) {
        print("[CollaborationManager] 处理接收到的用户数据")
        // 这里可以添加处理用户数据的逻辑
        // 例如更新用户列表等
    }
    
    // 处理接收到的消息
    private func handleReceivedMessage(_ message: CollaborationMessage, from peerID: MCPeerID) {
        print("[CollaborationManager] 处理来自 \(peerID.displayName) 的消息")
        
        switch message {
        case .syncRequest(let fromName):
            print("[CollaborationManager] 收到同步请求，来自: \(fromName)")
            // 如果是主机，且已经确认过同步，直接处理
            if isHost {
                if hasConfirmedSync {
                    // 直接处理同步请求，不需要用户确认
                    handleSyncRequest(from: peerID, accept: true)
                } else {
                    // 首次同步请求，需要用户确认
                    Task { @MainActor in
                        syncRequestFrom = fromName
                        showSyncRequest = true
                    }
                }
            }
            
        case .modelState(let state):
            print("[CollaborationManager] 收到模型状态")
            // 调用 handleReceivedModelData 处理模型数据
            handleReceivedModelData(state)
            
        case .modelTransform(let transform):
            print("[CollaborationManager] 收到模型变换")
            // 更新模型变换
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .modelTransformReceived,
                    object: nil,
                    userInfo: ["transform": transform]
                )
            }
            
        case .userPosition(let position):
            print("[CollaborationManager] 收到用户位置")
            // 更新用户位置
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .userPositionReceived,
                    object: nil,
                    userInfo: ["position": position]
                )
            }
            
        case .annotation(let annotation):
            print("[CollaborationManager] 收到注释")
            // 添加注释
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .annotationReceived,
                    object: nil,
                    userInfo: ["annotation": annotation]
                )
            }
            
        case .joinRequest(let userID):
            print("[CollaborationManager] 收到加入请求")
            // 处理加入请求
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .joinRequestReceived,
                    object: nil,
                    userInfo: ["userID": userID]
                )
            }
            
        case .userState(let userData):
            print("[CollaborationManager] 收到用户状态")
            // 处理用户状态
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .userStateReceived,
                    object: nil,
                    userInfo: ["userData": userData]
                )
            }
            
        case .disconnect:
            print("[CollaborationManager] 收到断开连接请求")
            // 处理断开连接请求
            Task { @MainActor in
                leaveSession()
            }
        }
    }
}

// MARK: - MCSessionDelegate
extension CollaborationManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .connected:
                print("[CollaborationManager] 与 \(peerID.displayName) 建立连接")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.isConnected = true
                self.errorMessage = nil
                
                // 如果是主机，且有模型状态，自动同步给新用户
                if self.isHosting, let modelState = self.currentModelStateProvider?() {
                    do {
                        // 获取当前模型数据
                        var updatedState = modelState
                        updatedState.modelData = self.currentModelDataProvider?()
                        
                        let data = try JSONEncoder().encode(CollaborationMessage.modelState(state: updatedState))
                        try session.send(data, toPeers: [peerID], with: .reliable)
                        print("[CollaborationManager] 已向新用户 \(peerID.displayName) 发送模型状态")
                    } catch {
                        self.errorMessage = "自动同步模型状态失败: \(error.localizedDescription)"
                        print("[CollaborationManager] 同步失败: \(error.localizedDescription)")
                    }
                }
            case .notConnected:
                print("[CollaborationManager] 与 \(peerID.displayName) 断开连接")
                self.connectedPeers.removeAll { $0 == peerID }
                self.isConnected = !self.connectedPeers.isEmpty
                if !self.isConnected {
                    self.errorMessage = "会话已断开"
                }
            case .connecting:
                print("[CollaborationManager] 正在与 \(peerID.displayName) 建立连接")
                self.errorMessage = "正在连接..."
            @unknown default:
                print("[CollaborationManager] 未知的连接状态变化")
                self.errorMessage = "未知的连接状态"
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            print("[CollaborationManager] 收到来自 \(peerID.displayName) 的数据")
            self.receivedData[peerID] = data
            self.handleReceivedMessage(data, from: peerID)
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("[CollaborationManager] 收到来自 \(peerID.displayName) 的流: \(streamName)")
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("[CollaborationManager] 开始接收来自 \(peerID.displayName) 的资源: \(resourceName)")
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("[CollaborationManager] 接收资源 \(resourceName) 失败: \(error.localizedDescription)")
        } else {
            print("[CollaborationManager] 成功接收资源: \(resourceName)")
        }
    }
}

// MARK: - Private Methods
private extension CollaborationManager {
    func handleReceivedMessage(_ data: Data, from peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(CollaborationMessage.self, from: data)
            handleReceivedMessage(message, from: peerID)
        } catch {
            print("处理消息失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension CollaborationManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("[CollaborationManager] 发现对等点: \(peerID.displayName)")
        // 发现新的对等点，立即发送邀请
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[CollaborationManager] 失去对等点: \(peerID.displayName)")
        Task { @MainActor in
            connectedPeers.removeAll { $0 == peerID }
            isConnected = !connectedPeers.isEmpty
            if !isConnected {
                errorMessage = "与 \(peerID.displayName) 的连接已断开"
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[CollaborationManager] 无法开始搜索对等点: \(error.localizedDescription)")
        Task { @MainActor in
            errorMessage = "无法开始搜索会话: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension CollaborationManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("[CollaborationManager] 收到来自 \(peerID.displayName) 的邀请")
        
        // 确保会话存在
        guard let session = session else {
            print("[CollaborationManager] 错误：会话未初始化")
            invitationHandler(false, nil)
            return
        }
        
        // 检查是否已经在连接中
        if session.connectedPeers.contains(peerID) {
            print("[CollaborationManager] 已经与 \(peerID.displayName) 连接")
            invitationHandler(true, session)
            return
        }
        
        // 立即接受邀请
        print("[CollaborationManager] 接受来自 \(peerID.displayName) 的邀请")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[CollaborationManager] 无法开始广播: \(error.localizedDescription)")
        Task { @MainActor in
            errorMessage = "无法创建会话: \(error.localizedDescription)"
            isHosting = false
            isHost = false
        }
    }
}

// 修改：通知名称
extension Notification.Name {
    static let modelStateReceived = Notification.Name("modelStateReceived")
    static let modelTransformReceived = Notification.Name("modelTransformReceived")
    static let userPositionReceived = Notification.Name("userPositionReceived")
    static let annotationReceived = Notification.Name("annotationReceived")
    static let joinRequestReceived = Notification.Name("joinRequestReceived")
    static let userStateReceived = Notification.Name("userStateReceived")
} 