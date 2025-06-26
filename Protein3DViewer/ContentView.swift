//
//  ContentView.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit

// 使用条件编译处理RealityKitContent模块导入
#if canImport(RealityKitContent)
import RealityKitContent
#endif

import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var proteinViewer = ProteinViewer()
    
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedAtomIndex: Int?
    @State private var displayMode: ProteinViewer.DisplayMode = .ballAndStick
    @State private var showBonds = true
    @State private var isMeasuring = false
    @State private var measurementDistance: Float?
    @State private var scale: Float = 1.0
    @State private var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var modelLoaded = false
    @State private var isLoading = false
    @State private var showSuccessMessage = false
    @State private var lowQualityMode = true // 默认低质量模式
    
    // 新增：UI布局参数
    @State private var leftSidePadding: CGFloat = 20
    @State private var rightSidePadding: CGFloat = 20
    
    var body: some View {
        VStack {
            // 分子切换栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Array(appModel.proteinModels.values), id: \ .id) { model in
                        Button(action: {
                            appModel.setActiveProteinModel(model.id)
                        }) {
                            Text("分子\(model.id.uuidString.prefix(4))")
                                .padding(8)
                                .background(appModel.activeProteinModelID == model.id ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }.padding(.top)
            // 添加分子按钮
            Button("添加分子") {
                // 这里应弹出文件选择或加载新分子逻辑
                let newViewer = ProteinViewer() // 需根据实际加载
                let newModel = ProteinModelData(proteinViewer: newViewer)
                appModel.addProteinModel(newModel)
            }.padding(.bottom)
            // 只渲染当前激活分子
            if let activeID = appModel.activeProteinModelID, appModel.proteinModels[activeID] != nil {
                ProteinModelView(modelID: activeID)
            } else {
                Text("请添加并选择一个分子")
            }
        }
    }
    
    // 根据模型尺寸调整UI布局
    private func adjustUILayout(modelWidth: Float) {
        let recommendedPadding = proteinViewer.getRecommendedUIPadding()
        let scaleFactor: CGFloat = 50.0 // 缩放因子，将浮点值转换为合适的UI尺寸
        
        // 根据模型宽度动态计算边距
        let basePadding: CGFloat = 20
        let additionalPadding = CGFloat(recommendedPadding) * scaleFactor
        
        // 设置新的边距值
        withAnimation(.easeInOut(duration: 0.5)) {
            leftSidePadding = basePadding + additionalPadding
            rightSidePadding = basePadding + additionalPadding
        }
        
        print("调整UI布局: 模型宽度 = \(modelWidth), 建议边距 = \(recommendedPadding), UI边距 = \(leftSidePadding)")
    }
    
    // 控制面板独立成View
    private var controlPanel: some View {
        VStack(spacing: 16) {
            
            HStack(spacing: 20) {
                Button(action: {
                    showFileImporter = true
                }) {
                    Label("打开PDB文件", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                
                Button(action: {
                    isMeasuring.toggle()
                    if !isMeasuring {
                        // 结束测量模式时，清除测量结果
                        proteinViewer.clearMeasurement()
                        measurementDistance = nil
                        print("测量模式已关闭，测量数据已清除")
                    } else {
                        // 开始测量模式
                        print("测量模式已开启，请点击两个原子进行测量")
                    }
                }) {
                    Label(isMeasuring ? "结束测量" : "开始测量", systemImage: isMeasuring ? "xmark" : "ruler")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!modelLoaded || isLoading)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("显示模式:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $displayMode) {
                        Text("球棍模型").tag(ProteinViewer.DisplayMode.ballAndStick)
                        Text("空间填充").tag(ProteinViewer.DisplayMode.spaceFilling)
                        Text("飘带模型").tag(ProteinViewer.DisplayMode.proteinRibbon)
                        Text("表面模型").tag(ProteinViewer.DisplayMode.proteinSurface)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(minWidth: 350)
                }
                .onChange(of: displayMode) { _, newMode in
                    Task {
                        await proteinViewer.updateDisplayMode(newMode)
                    }
                }
                .disabled(!modelLoaded || isLoading)
            }
            
            if let distance = measurementDistance {
                Text(String(format: "原子间距离: %.2f Å", distance))
                    .font(.headline)
                    .padding(.top, 8)
            }
            
            if isMeasuring {
                Text("请点击两个原子进行距离测量")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }
    
    // 点击事件处理
    private func handleTap(entity: ModelEntity) {
        if let index = getAtomIndex(entity) {
            if isMeasuring {
                // 只在测量模式下才处理原子点击
                proteinViewer.addMeasurementPoint(index)
                measurementDistance = proteinViewer.getDistance()
                print("测量模式：添加测量点，索引: \(index)")
            } else {
                // 非测量模式下不处理原子点击
                print("非测量模式，忽略原子点击")
            }
        }
    }
    
    private func getAtomIndex(_ entity: ModelEntity) -> Int? {
        // TODO: 根据你的逻辑，返回对应原子索引
        return nil
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environmentObject(AppModel())
}
