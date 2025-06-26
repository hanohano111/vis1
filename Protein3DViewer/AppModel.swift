//
//  AppModel.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit
import UniformTypeIdentifiers
import MultipeerConnectivity

/// 模型标注
struct ModelAnnotation: Codable, Identifiable {
    let id: UUID
    let position: SIMD3<Float>
    let text: String
    let color: SIMD4<Float>
}

/// 维护全局应用状态
@MainActor
class AppModel: ObservableObject {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    @Published var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // UI 控制
    @Published var showUI: Bool = true
    @Published var showSuccessMessage: Bool = false
    
    // 多窗口管理
    @Published var activeProteinModelID: UUID? = nil
    @Published var proteinModels: [UUID: ProteinModelData] = [:]
    @Published var isLoadingModel: Bool = false
    @Published var loadingProgress: Float = 0.0
    @Published var errorMessage: String? = nil
    @Published var shouldOpenModelWindow: Bool = false
    
    // 显示设置
    @Published var displayMode: ProteinViewer.DisplayMode = .ballAndStick
    @Published var showBonds: Bool = true
    @Published var isMeasuring: Bool = false
    @Published var measurementDistance: Float? = nil
    @Published var lowQualityMode: Bool = true // 默认低质量模式
    @Published var selectedAtomIndex: Int? = nil // 当前选中的原子索引
    
    // 文件导入控制
    @Published var showFileImporter: Bool = false
    @Published var showError: Bool = false
    
    // 协作相关状态
    @Published var collaborationManager: CollaborationManager?
    @Published var spaceSynchronizer: SpaceSynchronizer?
    @Published var userRepresentation: UserRepresentation?
    @Published var showCollaborationView: Bool = false
    
    // 标注相关
    @Published var annotations: [ModelAnnotation] = []
    @Published var selectedAtoms: Set<Int> = []
    
    // 打开PDB文件
    func openPDBFile(url: URL) async {
        do {
            // 检查是否在模拟器环境中
            #if targetEnvironment(simulator)
            // 模拟器环境不需要安全作用域访问权限
            #else
            // 真机环境需要申请安全作用域访问权限
            let granted = url.startAccessingSecurityScopedResource()
            defer {
                if granted {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            #endif
            
            // 设置加载状态
            isLoadingModel = true
            loadingProgress = 0.0
            showSuccessMessage = false  // 重置成功消息
            
            // 读取 PDB 文件数据
            let pdbData = try Data(contentsOf: url)
            print("[AppModel] 读取 PDB 文件数据，大小：\(pdbData.count) 字节")
            
            // 创建新的ProteinViewer和模型ID
            let newModelID = UUID()
            let proteinViewer = ProteinViewer()
            let modelData = ProteinModelData(proteinViewer: proteinViewer)
            modelData.pdbData = pdbData  // 保存 PDB 数据
            proteinModels[newModelID] = modelData
            
            // 异步加载模型
            try await proteinViewer.loadPDBFile(from: url, lowQualityMode: lowQualityMode)
            
            // 更新蛋白质信息
            // 从PDB文件内容提取蛋白质名称，而非仅使用文件名
            let proteinName = extractProteinName(from: url)
            
            // 从ProteinViewer获取原子数量
            let atomCount = proteinViewer.getAtomsData().count
            
            // 计算估计分子量 (根据原子数量粗略估计)
            let estimatedMolecularWeight = calculateMolecularWeight(atomCount: atomCount)
            
            // 获取氨基酸序列 (如果可用)
            let sequence = extractSequence(from: proteinViewer)
            
            // 更新模型数据
            modelData.updateProteinInfo(
                name: proteinName,
                atomCount: atomCount,
                molecularWeight: estimatedMolecularWeight,
                sequence: sequence
            )
            
            // 模型加载成功后，激活并打开窗口
            activeProteinModelID = newModelID
            
            // 设置标志，表示应该自动打开模型窗口
            shouldOpenModelWindow = true
            
            // 更新状态
            isLoadingModel = false
            loadingProgress = 1.0
            showSuccessMessage = true  // 显示成功消息
            
            // 设置定时器在3秒后隐藏成功消息
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                showSuccessMessage = false
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoadingModel = false
            print("加载文件错误: \(error.localizedDescription)")
        }
    }
    
    // 计算估计分子量的辅助方法
    private func calculateMolecularWeight(atomCount: Int) -> Double {
        // 粗略估计：平均每个原子约20道尔顿
        // 实际计算应该基于具体原子类型和数量
        return Double(atomCount) * 20.0
    }
    
    // 提取氨基酸序列的辅助方法
    private func extractSequence(from proteinViewer: ProteinViewer) -> String {
        // 尝试从proteinViewer获取氨基酸序列信息
        // 如果无法获取，返回占位符文本
        
        // 这里应该根据实际PDB解析逻辑获取序列
        // 简化实现：返回示例序列
        let sampleSequence = "MET-ALA-GLY-SER-THR-VAL-LEU-LYS-GLU-ASP-..." // 仅作演示
        
        return sampleSequence
    }
    
    // 从PDB文件提取蛋白质名称的辅助方法
    private func extractProteinName(from url: URL) -> String {
        do {
            // 读取PDB文件内容
            let pdbData = try String(contentsOf: url, encoding: .utf8)
            let lines = pdbData.components(separatedBy: .newlines)
            
            // 首先尝试从COMPND记录中提取分子名称
            for line in lines where line.hasPrefix("COMPND") {
                // 查找MOLECULE字段
                if line.contains("MOLECULE:") {
                    let parts = line.components(separatedBy: "MOLECULE:")
                    if parts.count > 1 {
                        let moleculeName = parts[1].trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: ";", with: "")
                        return moleculeName
                    }
                }
            }
            
            // 如果没有找到COMPND记录，尝试从HEADER记录提取
            for line in lines where line.hasPrefix("HEADER") {
                if line.count > 10 {
                    // HEADER记录通常包含蛋白质描述
                    let headerContent = line.dropFirst(10).trimmingCharacters(in: .whitespaces)
                    if !headerContent.isEmpty {
                        return headerContent
                    }
                }
            }
            
            // 如果上述方法都失败，尝试从TITLE记录提取
            for line in lines where line.hasPrefix("TITLE") {
                if line.count > 10 {
                    let titleContent = line.dropFirst(10).trimmingCharacters(in: .whitespaces)
                    if !titleContent.isEmpty {
                        return titleContent
                    }
                }
            }
            
            // 如果所有方法都失败，使用文件名
            let fileName = url.deletingPathExtension().lastPathComponent
            return fileName.count > 0 ? fileName : "未知蛋白质"
            
        } catch {
            print("读取PDB文件出错: \(error.localizedDescription)")
            // 如果读取失败，返回文件名
            let fileName = url.deletingPathExtension().lastPathComponent
            return fileName.count > 0 ? fileName : "未知蛋白质"
        }
    }
    
    // 更新显示模式
    func updateDisplayMode(_ newMode: ProteinViewer.DisplayMode) async {
        displayMode = newMode
        
        // 更新所有活动模型
        if let modelID = activeProteinModelID, let modelData = proteinModels[modelID] {
            await modelData.proteinViewer.updateDisplayMode(newMode)
        }
    }
    
    // 切换化学键显示
    func toggleBonds() {
        showBonds.toggle()
        
        // 更新所有活动模型
        if let modelID = activeProteinModelID, let modelData = proteinModels[modelID] {
            modelData.proteinViewer.toggleBonds()
        }
    }
    
    // 切换测量模式
    func toggleMeasuring() {
        isMeasuring.toggle()
        
        // 清除之前的测量
        if let modelID = activeProteinModelID, let modelData = proteinModels[modelID] {
            modelData.proteinViewer.clearMeasurement()
            measurementDistance = nil
        }
        
        print("测量模式已\(isMeasuring ? "开启" : "关闭")")
    }
    
    // 添加测量点
    func addMeasurementPoint(at index: Int) {
        if let modelID = activeProteinModelID, let modelData = proteinModels[modelID] {
            modelData.proteinViewer.addMeasurementPoint(index)
            measurementDistance = modelData.proteinViewer.getDistance()
        }
    }
    
    // 选择原子
    func selectAtom(at index: Int) {
        print("AppModel: 收到选择原子请求，索引: \(index)")
        
        // 更新选中的原子索引
        if selectedAtomIndex == index {
            // 如果是再次点击同一个原子，取消选择
            selectedAtomIndex = nil
            print("AppModel: 取消选择原子 \(index)")
        } else {
            // 否则选择新的原子
            selectedAtomIndex = index
            print("AppModel: 选择新原子，索引: \(index)")
        }
        
        if let modelID = activeProteinModelID {
            if let modelData = proteinModels[modelID] {
                print("AppModel: 找到活动模型，正在调用proteinViewer.selectAtom")
                modelData.proteinViewer.selectAtom(at: index)
            } else {
                print("AppModel: 错误 - 找不到ID为\(modelID)的蛋白质模型数据")
            }
        } else {
            print("AppModel: 错误 - 没有活动的蛋白质模型ID")
        }
    }
    
    // 强制刷新选中原子颜色
    func refreshSelectedAtomsColor() {
        print("AppModel: 强制刷新选中原子颜色")
        
        if let modelID = activeProteinModelID, let modelData = proteinModels[modelID] {
            let selectedAtoms = modelData.proteinViewer.getSelectedAtoms()
            print("找到\(selectedAtoms.count)个选中原子")
            
            // 对每个选中的原子重新应用选中效果
            for index in selectedAtoms {
                // 先取消选中
                modelData.proteinViewer.selectAtom(at: index)
                // 再重新选中
                modelData.proteinViewer.selectAtom(at: index)
                print("刷新原子\(index)的选中状态")
            }
        } else {
            print("AppModel: 没有活动模型，无法刷新选中原子")
        }
    }
    
    // 添加新分子
    func addProteinModel(_ model: ProteinModelData) {
        proteinModels[model.id] = model
        activeProteinModelID = model.id
        // 协作状态下自动同步新模型
        if let manager = collaborationManager, manager.isConnected {
            if let state = manager.currentModelStateProvider?() {
                manager.sendModelState(state)
            }
        }
    }
    
    // 切换当前激活分子
    func setActiveProteinModel(_ id: UUID) {
        if proteinModels[id] != nil {
            activeProteinModelID = id
            // 协作状态下自动同步切换后的模型
            if let manager = collaborationManager, manager.isConnected {
                if let state = manager.currentModelStateProvider?() {
                    manager.sendModelState(state)
                }
            }
        }
    }
    
    // 初始化协作组件
    func initializeCollaboration() {
        print("[AppModel] 初始化协作组件")
        
        // 初始化协作管理器
        let manager = CollaborationManager()
        
        // 创建并初始化 MCSession
        let peerID = MCPeerID(displayName: UIDevice.current.name)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        print("[AppModel] 创建 MCSession，设备名称: \(peerID.displayName)")
        
        // 初始化协作管理器
        manager.initialize(
            session: session,
            modelStateProvider: { [weak self] in
                guard let self = self else {
                    print("[AppModel] 警告：self 已被释放")
                    return ModelState(
                        transform: .identity,
                        scale: [1, 1, 1],
                        annotations: [],
                        selectedAtoms: [],
                        currentModel: nil,
                        modelData: nil
                    )
                }
                
                // 获取当前模型状态
                guard let modelID = self.activeProteinModelID,
                      let modelData = self.proteinModels[modelID] else {
                    print("[AppModel] 警告：当前没有活动的模型")
                    return ModelState(
                        transform: .identity,
                        scale: [1, 1, 1],
                        annotations: [],
                        selectedAtoms: [],
                        currentModel: nil,
                        modelData: nil
                    )
                }
                
                let transform = modelData.proteinViewer.getScene()?.transform ?? .identity
                let scale = modelData.proteinViewer.getScene()?.scale ?? [1, 1, 1]
                let selectedAtoms = self.selectedAtoms
                
                print("[AppModel] 提供当前模型状态:")
                print("- 模型名称: \(modelData.name)")
                print("- 变换: 位置(\(transform.translation)), 旋转(\(transform.rotation)), 缩放(\(scale))")
                print("- 选中原子数: \(selectedAtoms.count)")
                print("- 标注数: \(self.annotations.count)")
                
                // 确保 PDB 数据存在
                guard let pdbData = modelData.pdbData else {
                    print("[AppModel] 错误：模型没有 PDB 数据")
                    return ModelState(
                        transform: transform,
                        scale: scale,
                        annotations: self.annotations,
                        selectedAtoms: selectedAtoms,
                        currentModel: modelData.name,
                        modelData: nil
                    )
                }
                
                print("- PDB数据大小: \(pdbData.count) 字节")
                
                return ModelState(
                    transform: transform,
                    scale: scale,
                    annotations: self.annotations,
                    selectedAtoms: selectedAtoms,
                    currentModel: modelData.name,
                    modelData: pdbData
                )
            },
            modelDataProvider: { [weak self] in
                guard let self = self,
                      let modelID = self.activeProteinModelID,
                      let modelData = self.proteinModels[modelID] else {
                    print("[AppModel] 警告：无法获取当前模型")
                    return Data()
                }
                
                guard let pdbData = modelData.pdbData else {
                    print("[AppModel] 错误：模型没有 PDB 数据")
                    return Data()
                }
                
                // 验证数据
                if pdbData.count == 0 {
                    print("[AppModel] 错误：PDB 数据为空")
                } else {
                    print("[AppModel] 提供模型数据，大小: \(pdbData.count) 字节")
                }
                
                return pdbData
            },
            onModelStateReceived: { [weak self] state in
                guard let self = self else {
                    print("[AppModel] 警告：self 已被释放")
                    return
                }
                
                Task { @MainActor in
                    print("[AppModel] 收到模型状态更新:")
                    print("- 模型名称: \(state.currentModel ?? "未知")")
                    print("- 变换: 位置(\(state.transform.translation)), 旋转(\(state.transform.rotation)), 缩放(\(state.scale))")
                    print("- 选中原子数: \(state.selectedAtoms.count)")
                    print("- 标注数: \(state.annotations.count)")
                    if let modelData = state.modelData {
                        print("- 收到模型数据，大小: \(modelData.count) 字节")
                    } else {
                        print("- 模型数据: 无")
                    }
                    
                    // 检查是否需要加载新模型
                    if let modelData = state.modelData,
                       let modelName = state.currentModel {
                        print("[AppModel] 开始加载新模型:")
                        print("- 模型名称: \(modelName)")
                        print("- 数据大小: \(modelData.count) 字节")
                        
                        // 创建新的 ProteinViewer
                        let proteinViewer = ProteinViewer()
                        print("[AppModel] 创建新的 ProteinViewer")
                        
                        // 创建新的模型数据
                        let newModelData = ProteinModelData(proteinViewer: proteinViewer)
                        newModelData.name = modelName
                        newModelData.pdbData = modelData
                        print("[AppModel] 创建新的 ProteinModelData，ID: \(newModelData.id)")
                        
                        do {
                            // 使用 FileManager 的临时目录
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).pdb")
                            
                            // 写入数据到临时文件
                            try modelData.write(to: tempFile, options: .atomic)
                            print("[AppModel] 创建临时文件: \(tempFile.path)")
                            
                            // 确保文件存在
                            guard FileManager.default.fileExists(atPath: tempFile.path) else {
                                throw NSError(domain: "AppModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "临时文件创建失败"])
                            }
                            
                            // 加载模型
                            print("[AppModel] 开始加载 PDB 数据")
                            try await proteinViewer.loadPDBFile(from: tempFile, lowQualityMode: true)
                            print("[AppModel] PDB 数据加载成功")
                            
                            // 更新模型状态
                            if let scene = proteinViewer.getScene() {
                                scene.transform = state.transform
                                scene.scale = state.scale
                                print("[AppModel] 更新模型变换:")
                                print("- 位置: \(scene.transform.translation)")
                                print("- 旋转: \(scene.transform.rotation)")
                                print("- 缩放: \(scene.scale)")
                            } else {
                                print("[AppModel] 警告：无法获取场景")
                            }
                            
                            // 添加到模型列表并设置为活动模型
                            self.proteinModels[newModelData.id] = newModelData
                            self.activeProteinModelID = newModelData.id
                            print("[AppModel] 模型已添加到列表并设置为活动模型")
                            
                            // 更新其他状态
                            self.selectedAtoms = state.selectedAtoms
                            self.annotations = state.annotations
                            print("[AppModel] 更新状态:")
                            print("- 选中原子数: \(self.selectedAtoms.count)")
                            print("- 标注数: \(self.annotations.count)")
                            
                            // 删除临时文件
                            try? FileManager.default.removeItem(at: tempFile)
                            print("[AppModel] 临时文件已删除")
                            
                            print("[AppModel] 模型同步完成")
                        } catch {
                            print("[AppModel] 错误：加载模型失败")
                            print("- 错误信息: \(error.localizedDescription)")
                            if let decodingError = error as? DecodingError {
                                print("- 解码错误详情: \(decodingError)")
                            }
                        }
                    } else if let modelID = self.activeProteinModelID,
                              let modelData = self.proteinModels[modelID] {
                        print("[AppModel] 更新现有模型状态:")
                        print("- 模型ID: \(modelID)")
                        print("- 模型名称: \(modelData.name)")
                        
                        // 只更新现有模型的状态
                        if let scene = modelData.proteinViewer.getScene() {
                            scene.transform = state.transform
                            scene.scale = state.scale
                            print("- 更新变换:")
                            print("  - 位置: \(scene.transform.translation)")
                            print("  - 旋转: \(scene.transform.rotation)")
                            print("  - 缩放: \(scene.scale)")
                        } else {
                            print("- 警告：无法获取场景")
                        }
                        
                        self.selectedAtoms = state.selectedAtoms
                        self.annotations = state.annotations
                        print("- 更新状态:")
                        print("  - 选中原子数: \(self.selectedAtoms.count)")
                        print("  - 标注数: \(self.annotations.count)")
                    } else {
                        print("[AppModel] 警告：无法找到活动模型")
                    }
                }
            }
        )
        
        self.collaborationManager = manager
        print("[AppModel] 协作管理器初始化完成")
        
        // 初始化空间同步器
        self.spaceSynchronizer = SpaceSynchronizer(collaborationManager: manager)
        print("[AppModel] 空间同步器初始化完成")
        
        // 初始化用户表示
        self.userRepresentation = UserRepresentation(collaborationManager: manager)
        print("[AppModel] 用户表示初始化完成")
    }
    
    // MARK: - Public Methods for Collaboration
    
    /// 获取当前选中的原子
    func getSelectedAtoms() -> Set<Int> {
        return selectedAtoms
    }
    
    /// 设置选中的原子
    func setSelectedAtoms(_ atoms: Set<Int>) {
        selectedAtoms = atoms
    }
    
    // 清理协作组件
    func cleanupCollaboration() {
        collaborationManager?.leaveSession()
        collaborationManager = nil
        spaceSynchronizer = nil
        userRepresentation = nil
    }
}
