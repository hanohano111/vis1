//
//  AppModel.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit
import UniformTypeIdentifiers

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
    
    // 多窗口管理
    @Published var activeProteinModelID: UUID?
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
    
    // 打开PDB文件
    func openPDBFile(url: URL) async {
        do {
            // 设置加载状态
            isLoadingModel = true
            loadingProgress = 0.0
            
            // 创建新的ProteinViewer和模型ID
            let newModelID = UUID()
            let proteinViewer = ProteinViewer()
            let modelData = ProteinModelData(id: newModelID, proteinViewer: proteinViewer)
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
}
