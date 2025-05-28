//
//  ContentView.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit
import RealityKitContent
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
        GeometryReader { geometry in
            ZStack {
                // 3D场景部分
                RealityView { content in
                    print("初始化RealityView")
                    proteinViewer.setupRealityView(content: content)
                }
                .id(modelLoaded) // 强制刷新
                .gesture(
                    SpatialTapGesture()
                        .targetedToAnyEntity()
                        .onEnded { value in
                            if let entity = value.entity as? ModelEntity {
                                Task { @MainActor in
                                    handleTap(entity: entity)
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let sensitivity: Float = 0.01
                            let deltaX = Float(value.translation.width) * sensitivity
                            rotation = simd_quatf(angle: deltaX, axis: [0, 1, 0]) * rotation
                            if let scene = proteinViewer.getScene() {
                                scene.orientation = rotation
                            }
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let scaleFactor = Float(value)
                            proteinViewer.scale(by: scaleFactor)
                            scale = scaleFactor
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 左侧操作面板
                if modelLoaded {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("操作菜单")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Button(action: {
                            // 旋转操作
                        }) {
                            Image(systemName: "rotate.3d")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(Color.blue.opacity(0.7))
                        .clipShape(Circle())
                        
                        Button(action: {
                            // 缩放操作
                        }) {
                            Image(systemName: "plus.magnifyingglass")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(Color.blue.opacity(0.7))
                        .clipShape(Circle())
                        
                        Spacer()
                    }
                    .padding()
                    .frame(width: 100)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(15)
                    .padding(.leading, leftSidePadding)
                    .position(x: 50 + leftSidePadding/2, y: geometry.size.height / 2)
                    .animation(.easeInOut, value: leftSidePadding)
                    
                    // 右侧信息面板
                    VStack(alignment: .leading, spacing: 12) {
                        Text("分子信息")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        if let pdbInfo = proteinViewer.pdbInfo {
                            Text("名称: \(pdbInfo.name)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            
                            Text("原子数: \(pdbInfo.atomCount)")
                                .font(.subheadline)
                                .foregroundColor(.white)
                                
                            if let resolution = pdbInfo.resolution {
                                Text(String(format: "分辨率: %.2f Å", resolution))
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                            
                            if !pdbInfo.description.isEmpty {
                                Text("描述: \(pdbInfo.description)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                            }
                        } else {
                            Text("暂无分子信息")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .frame(width: 150)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(15)
                    .padding(.trailing, rightSidePadding)
                    .position(x: geometry.size.width - 75 - rightSidePadding/2, y: geometry.size.height / 2)
                    .animation(.easeInOut, value: rightSidePadding)
                }
                
                // 加载进度与提示
                if isLoading {
                    ProgressView("正在加载模型...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                } else if !modelLoaded {
                    Text("请加载PDB文件")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                } else if showSuccessMessage {
                    Text("模型已加载")
                        .font(.headline)
                        .foregroundColor(.green)
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation {
                                    showSuccessMessage = false
                                }
                            }
                        }
                }
                
                // 控制面板部分
                VStack {
                    Spacer()
                    controlPanel
                        .padding()
                        .frame(maxWidth: 700) // 限制面板宽度
                        .background(.thinMaterial) // 毛玻璃背景
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 10)
                        .padding(.bottom, 20)
                        .disabled(isLoading)
                }
            }
        }
        .onReceive(proteinViewer.$modelWidth) { width in
            adjustUILayout(modelWidth: width)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.init(filenameExtension: "pdb")!],
            allowsMultipleSelection: false
        ) { result in
            Task {
                do {
                    let urls = try result.get()
                    if let url = urls.first {
                        print("选择了文件: \(url.lastPathComponent)")
                        isLoading = true
                        modelLoaded = false
                        
                        try await proteinViewer.loadPDBFile(from: url, lowQualityMode: lowQualityMode)
                        
                        modelLoaded = true
                        isLoading = false
                        showSuccessMessage = true
                        print("模型加载完成")
                        
                        // 加载完成后调整布局
                        adjustUILayout(modelWidth: proteinViewer.modelWidth)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                    print("加载文件错误: \(error.localizedDescription)")
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定") {
                showError = false
            }
        } message: {
            Text(errorMessage ?? "未知错误")
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
