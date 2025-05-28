import SwiftUI
import RealityKit

struct ProteinModelView: View {
    let modelID: UUID //用于标识特定的蛋白质模型。
    @EnvironmentObject private var appModel: AppModel
    //创建一个本地的视图模型ProteinViewModel，用于管理视图内的交互状态，如旋转、移动、缩放等操作状态。
    @State private var viewModel = ProteinViewModel()
    
    var body: some View {
        ZStack {
            // 背景
            //Color.black.opacity(0.01)
                //.edgesIgnoringSafeArea(.all)
            
            // 主内容
            modelContentView
            
            // 状态标签
            statusLabelsView
        }
        //通过.ornament修饰符分别在场景右侧和左侧添加装饰物。
        .ornament(
            visibility: .automatic,
            attachmentAnchor: .scene(.trailing)
        ) {
            modelControlsOrnament
        }
        // 添加左侧装饰物，包含模型显示控制和测量功能
        .ornament(
            visibility: .automatic,
            attachmentAnchor: .scene(.leading)
        ) {
            displayControlsOrnament
        }
        //.onAppear修饰符调用setupOnAppear方法，在视图出现时确保应用当前的显示设置，包括显示模式、化学键显示设置，以及重置模型位置以最佳显示。
        .onAppear {
            setupOnAppear()
        }
    }
    
    // MARK: - 子视图
    
    // 模型内容视图
    private var modelContentView: some View {
        Group {
            if let modelData = appModel.proteinModels[modelID] {
                // 3D蛋白质模型视图
                proteinModelView(modelData: modelData)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        viewModel.isMoving ? .green.opacity(0.7) :
                                        viewModel.isRotating ? .blue.opacity(0.7) :
                                        viewModel.isScaling ? .purple.opacity(0.7) :
                                        viewModel.isChangingColor ? .orange.opacity(0.7) :
                                        .clear.opacity(0.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: viewModel.isMoving || viewModel.isRotating || viewModel.isScaling || viewModel.isChangingColor ? 3 : 0
                            )
                            .animation(.easeInOut(duration: 0.3), value: viewModel.isMoving)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.isRotating)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.isScaling)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.isChangingColor)
                    )
            } else {
                // 显示错误信息
                Text("无法加载模型数据")
                    .foregroundColor(.red)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
            }
        }
    }
    
    // 蛋白质模型视图
    private func proteinModelView(modelData: ProteinModelData) -> some View {
        RealityView { content in
            // 初始化场景
            modelData.proteinViewer.setupRealityView(content: content)
            
            // 更新视图模型
            viewModel.isModelLoaded = true
            
            // 设置初始位置
            if let rootEntity = modelData.proteinViewer.getScene() {
                // 确保初始位置位于用户前方适当距离
                rootEntity.position = [0, 0, -0.5]
                print("RealityView初始化：设置rootEntity位置为\(rootEntity.position)")
                
                // 确保实体可交互
                if rootEntity.components[InputTargetComponent.self] == nil {
                    rootEntity.components[InputTargetComponent.self] = InputTargetComponent()
                    print("RealityView：添加InputTargetComponent")
                }
                
                if rootEntity.components[CollisionComponent.self] == nil {
                    rootEntity.components[CollisionComponent.self] = CollisionComponent(
                        shapes: [.generateBox(size: [1, 1, 1])],
                        mode: .trigger,
                        filter: .sensor
                    )
                    print("RealityView：添加CollisionComponent")
                }
            }
        } update: { content in
            // 更新视图内容 
            if let rootEntity = modelData.proteinViewer.getScene() {
                print("RealityView更新：当前rootEntity位置\(rootEntity.position), 缩放\(rootEntity.scale)")
            }
        }
        // 直接应用手势，不再使用条件应用
        .gesture(spatialTapGesture(modelData: modelData))
        .gesture(dragGesture(modelData: modelData))
        .gesture(rotationGesture(modelData: modelData))
        .gesture(magnificationGesture(modelData: modelData))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(10)
        .onChange(of: viewModel.isMoving) { _, isActive in
            if isActive {
                playHapticFeedback()
                print("移动模式已激活，可拖拽模型")
            }
        }
        .onChange(of: viewModel.isRotating) { _, isActive in
            if isActive {
                playHapticFeedback()
                print("旋转模式已激活，可旋转模型")
            }
        }
        .onChange(of: viewModel.isScaling) { _, isActive in
            if isActive {
                playHapticFeedback()
                print("缩放模式已激活，可缩放模型")
            }
        }
        .onChange(of: viewModel.isChangingColor) { _, isActive in
            if isActive {
                playHapticFeedback()
                print("颜色修改模式已激活，可选择颜色并应用到原子")
                viewModel.lastAction = "颜色修改模式已启动：请先选择一个颜色，然后点击想要更改的原子"
            } else {
                print("颜色修改模式已关闭")
                viewModel.lastAction = "颜色修改模式已关闭，如需继续修改请再次点击颜色修改按钮"
            }
        }
    }
    
    // 提供适合visionOS的反馈机制
    private func playHapticFeedback() {
        #if os(iOS)
        // 在iOS上使用UIImpactFeedbackGenerator
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #else
        // 在visionOS中不执行任何操作，仅依赖视觉反馈
        // 未来可以添加visionOS特定的反馈机制
        #endif
    }
    
    // 状态标签视图
    private var statusLabelsView: some View {
        VStack {
            // 操作提示标签
            if !viewModel.lastAction.isEmpty {
                Text(viewModel.lastAction)
                    .font(.system(size: 14, weight: .medium))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .opacity(0.95)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.lastAction)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // 当前活动操作模式
                if viewModel.isRotating || viewModel.isMoving || viewModel.isScaling || viewModel.isChangingColor {
                    Label(
                        viewModel.isRotating ? "旋转模式" : 
                         viewModel.isMoving ? "移动模式" : 
                        viewModel.isScaling ? "缩放模式" : "颜色修改模式",
                        systemImage: viewModel.isRotating ? "rotate.3d" : 
                                    viewModel.isMoving ? "hand.draw" : 
                                    viewModel.isScaling ? "plus.magnifyingglass" : "paintbrush"
                    )
                    .font(.system(size: 14, weight: .medium))
                        .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                        .foregroundStyle(viewModel.isChangingColor ? .orange : .blue)
                }
                
                // 测量模式标签
                if appModel.isMeasuring {
                    Label("测量模式", systemImage: "ruler")
                        .font(.system(size: 14, weight: .medium))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                        )
                        .foregroundStyle(.green)
                }
                
                // 测量距离标签
                if let distance = appModel.measurementDistance {
                    Label(
                        String(format: "%.2f Å", distance),
                        systemImage: "ruler.fill"
                    )
                    .font(.system(size: 14, weight: .medium))
                        .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    .foregroundStyle(.green)
                }
            }
            .padding()
        }
    }
    
    // 模型控制装饰物
    private var modelControlsOrnament: some View {
        // 简洁的模型控制工具条
        VStack(spacing: 20) {
            Spacer()
            
            Text("模型控制")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.bottom, 10)
            
            ModelControlButton(
                systemName: "rotate.3d",
                label: "自由旋转",
                isActive: $viewModel.isRotating
            ) {
                viewModel.toggleRotation()
            }
            
            ModelControlButton(
                systemName: "hand.draw",
                label: "移动模型",
                isActive: $viewModel.isMoving
            ) {
                viewModel.toggleMoving()
            }
            
            ModelControlButton(
                systemName: "plus.magnifyingglass",
                label: "缩放",
                isActive: $viewModel.isScaling
            ) {
                viewModel.toggleScaling()
            }
            
            Divider()
                .padding(.vertical, 10)
            
            ModelControlButton(
                systemName: "house",
                label: "重置位置"
            ) {
                resetModelPosition()
            }
            
            Spacer()
        }
        .padding(20)
        .glassBackgroundEffect()
        .frame(width: 300, height: 800)
    }
    
    // 显示控制装饰物 
    private var displayControlsOrnament: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // 显示模式选择
            displayModeSection
            
            Divider()
                .padding(.vertical, 10)
            
            // 蛋白质信息部分
            modelInfoSection
            
            Divider()
                .padding(.vertical, 10)
            
            // 测距功能
            measurementSection
            
            Divider()
                .padding(.vertical, 10)
            
            // 颜色修改部分
            colorChangeSection
            
            Spacer()
        }
        .padding(20)
        .frame(width: 300, height: 800)
        .glassBackgroundEffect()
    }
    
    // 显示模式选择部分
    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("显示模式")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // 自定义的显示模式选择
            VStack(spacing: 12) {
                ForEach(ProteinViewer.DisplayMode.allCases, id: \.self) { mode in
                    displayModeRow(mode)
                }
            }
            
           
            
            
        }
    }
    
    // 显示模式行
    private func displayModeRow(_ mode: ProteinViewer.DisplayMode) -> some View {
        HStack {
            Text(mode.displayName)
                .foregroundColor(appModel.displayMode == mode ? .blue : .primary)
                .font(.body)
            Spacer()
            if appModel.displayMode == mode {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                appModel.displayMode = mode
                await appModel.updateDisplayMode(mode)
            }
        }
    }
    
    // 模型信息部分
    private var modelInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型信息")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let modelData = appModel.proteinModels[modelID] {
                VStack(alignment: .leading, spacing: 8) {
                    Text("蛋白质名称:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(modelData.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text("原子数量: \(modelData.atomCount)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("分子量: \(String(format: "%.1f", modelData.molecularWeight)) Da")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if modelData.sequence != "未获取序列" {
                        Text("氨基酸序列:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        Text(modelData.sequence)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
            } else {
                Text("未加载模型数据")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // 测量部分
    private var measurementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("测量工具")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(appModel.isMeasuring ? "结束测量" : "开始测量") {
                appModel.toggleMeasuring()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            
            if appModel.isMeasuring {
                Text("请点击两个原子进行测量")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let distance = appModel.measurementDistance {
                HStack {
                    Text("原子间距离:")
                    Text(String(format: "%.2f Å", distance))
                        .bold()
                        .foregroundColor(.green)
                }
            }
        }
    }
    
    // 颜色修改部分
    private var colorChangeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("修改颜色")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // 使用系统标准按钮样式确保更好的点击响应
            Button(viewModel.isChangingColor ? "退出颜色修改" : "开始修改颜色") {
                viewModel.toggleColorChange()
                
                // 额外确保选中状态被清除，因为我们已经在viewModel中处理了选中颜色
                if !viewModel.isChangingColor {
                    appModel.selectedAtomIndex = nil
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isChangingColor ? .orange : .blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .controlSize(.large)
            
            if viewModel.isChangingColor {
                // 状态指示器
                HStack {
                    Circle()
                        .fill(.orange)
                        .frame(width: 10, height: 10)
                    
                    Text("颜色修改模式已激活")
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                .padding(.bottom, 10)
                
                // 颜色选择区域
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("请选择要应用的颜色:")
                            .font(.callout)
                            .foregroundColor(.primary)
                        
                        // 添加当前选中的颜色显示
                        if let selectedColor = viewModel.selectedColor {
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                .shadow(color: Color(selectedColor).opacity(0.7), radius: 1)
                            
                            // 添加选中状态的文本指示
                            Text("(已选择)")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, 2)
                    
                    // 颜色选择状态指示
                    if viewModel.selectedColor != nil {
                        Text("点击任意原子应用此颜色")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 5)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // 使用一个网格布局包裹所有颜色按钮，无需滚动
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 40, maximum: 45), spacing: 3),
                        GridItem(.adaptive(minimum: 40, maximum: 45), spacing: 3),
                        GridItem(.adaptive(minimum: 40, maximum: 45), spacing: 3),
                        GridItem(.adaptive(minimum: 40, maximum: 45), spacing: 3),
                        GridItem(.adaptive(minimum: 40, maximum: 45), spacing: 3)
                    ], spacing: 1) {
                        // 标准颜色
                        ColorButton(color: .red, isSelected: viewModel.selectedColor == .red, onSelect: { setSelectedColor(.red) })
                            .id("red_\(viewModel.selectedColor == .red)")
                        ColorButton(color: .orange, isSelected: viewModel.selectedColor == .orange, onSelect: { setSelectedColor(.orange) })
                            .id("orange_\(viewModel.selectedColor == .orange)")
                        ColorButton(color: .yellow, isSelected: viewModel.selectedColor == .yellow, onSelect: { setSelectedColor(.yellow) })
                            .id("yellow_\(viewModel.selectedColor == .yellow)")
                        ColorButton(color: .green, isSelected: viewModel.selectedColor == .green, onSelect: { setSelectedColor(.green) })
                            .id("green_\(viewModel.selectedColor == .green)")
                        ColorButton(color: .blue, isSelected: viewModel.selectedColor == .blue, onSelect: { setSelectedColor(.blue) })
                            .id("blue_\(viewModel.selectedColor == .blue)")
                        
                        // 更多颜色
                        ColorButton(color: .purple, isSelected: viewModel.selectedColor == .purple, onSelect: { setSelectedColor(.purple) })
                            .id("purple_\(viewModel.selectedColor == .purple)")
                        ColorButton(color: .pink, isSelected: viewModel.selectedColor == .pink, onSelect: { setSelectedColor(.pink) })
                            .id("pink_\(viewModel.selectedColor == .pink)")
                        ColorButton(color: .teal, isSelected: viewModel.selectedColor == .teal, onSelect: { setSelectedColor(.teal) })
                            .id("teal_\(viewModel.selectedColor == .teal)")
                        ColorButton(color: .brown, isSelected: viewModel.selectedColor == .brown, onSelect: { setSelectedColor(.brown) })
                            .id("brown_\(viewModel.selectedColor == .brown)")
                        ColorButton(color: .cyan, isSelected: viewModel.selectedColor == .cyan, onSelect: { setSelectedColor(.cyan) })
                            .id("cyan_\(viewModel.selectedColor == .cyan)")
                        
                        // 额外颜色
                        ColorButton(color: .indigo, isSelected: viewModel.selectedColor == .indigo, onSelect: { setSelectedColor(.indigo) })
                            .id("indigo_\(viewModel.selectedColor == .indigo)")
                        ColorButton(color: .mint, isSelected: viewModel.selectedColor == .mint, onSelect: { setSelectedColor(.mint) })
                            .id("mint_\(viewModel.selectedColor == .mint)")
                        ColorButton(color: .gray, isSelected: viewModel.selectedColor == .gray, onSelect: { setSelectedColor(.gray) })
                            .id("gray_\(viewModel.selectedColor == .gray)")
                        ColorButton(color: .black, isSelected: viewModel.selectedColor == .black, onSelect: { setSelectedColor(.black) })
                            .id("black_\(viewModel.selectedColor == .black)")
                        ColorButton(color: .white, isSelected: viewModel.selectedColor == .white, onSelect: { setSelectedColor(.white) })
                            .id("white_\(viewModel.selectedColor == .white)")
                    }
                    .padding(2)
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(12)
                }
                .padding(.vertical, 10)
                
                // 当前选中的颜色和操作说明
                if let selectedColor = viewModel.selectedColor {
                    HStack {
                        Text("已选颜色:")
                            .font(.caption)
                        
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .shadow(color: Color(selectedColor).opacity(0.6), radius: 1)
                    }
                    .padding(.top, 5)
                    
                    Text("请点击原子应用颜色")
                    .font(.caption)
                    .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                } else {
                    Text("请先选择上方的颜色")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                }
                
                // 选中原子信息显示
                if let selectedIndex = appModel.selectedAtomIndex {
                    Text("已选中原子 \(selectedIndex)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.vertical, 2)
                }
                
                // 快捷操作按钮 - 增大按钮尺寸
                Button("应用到所有原子") {
                    applyColorToAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.selectedColor == nil)
                .padding(.top, 8)
                .frame(maxWidth: .infinity)
            } else {
                Text("点击上方按钮开始修改原子颜色")
                    .font(.callout)
                    .foregroundColor(.secondary)
                .padding(.vertical, 6)
            }
        }
    }
    
    // MARK: - 手势处理
    
    // 空间点击手势
    private func spatialTapGesture(modelData: ProteinModelData) -> some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                if let entity = value.entity as? ModelEntity {
                    Task {
                        print("用户点击了3D空间中的实体")
                        if let index = getAtomIndex(entity: entity, proteinViewer: modelData.proteinViewer) {
                            print("识别到点击的原子索引: \(index)")
                            handleAtomTap(at: index)
                        } else {
                            print("未能识别点击的原子")
                        }
                    }
                }
            }
    }
    
    // 拖拽手势
    private func dragGesture(modelData: ProteinModelData) -> some Gesture {
        // 添加对移动状态的跟踪
        DragGesture(minimumDistance: 5) // 大幅提高最小识别距离，避免轻微抖动触发移动
            .onChanged { value in
                // 只有在移动模式下才处理拖拽
                guard viewModel.isMoving else { return }
                
                // 忽略过小的移动距离，防止抖动
                let totalDistance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                guard totalDistance > 10 else { return } // 忽略过小的移动
                
                print("⚠️ 拖拽手势检测到变化: dx=\(value.translation.width), dy=\(value.translation.height)")
                
                guard let rootEntity = modelData.proteinViewer.getScene() else {
                    print("❌ 拖拽手势：未能获取场景实体")
                    return
                }
                
                // 极大降低灵敏度，提高控制性
                let sensitivity: Float = 0.0005 // 极低敏感度
                
                // 应用非线性变换，小移动时敏感度更低
                let nonLinearFactor = Float(min(1.0, totalDistance / 200))
                let effectiveSensitivity = sensitivity * nonLinearFactor
                
                let deltaX = Float(value.translation.width) * effectiveSensitivity
                let deltaY = Float(-value.translation.height) * effectiveSensitivity
                
                // 获取当前位置并应用偏移
                let currentPosition = rootEntity.position
                rootEntity.position = SIMD3<Float>(
                    currentPosition.x + deltaX,
                    currentPosition.y + deltaY,
                    currentPosition.z
                )
                
                // 添加实时反馈信息
                viewModel.lastAction = "正在移动模型"
            }
            .onEnded { _ in
                if viewModel.isMoving {
                    // 操作结束时更新状态
                    viewModel.lastAction = "移动操作已完成"
                }
            }
    }
    
    // 旋转手势
    private func rotationGesture(modelData: ProteinModelData) -> some Gesture {
        RotationGesture()
            .onChanged { value in
                // 只有在旋转模式下才处理旋转
                guard viewModel.isRotating else { return }
                
                print("⚠️ 旋转手势检测到变化，角度: \(value.degrees)度")
                
                guard let rootEntity = modelData.proteinViewer.getScene() else {
                    print("❌ 旋转手势：未能获取场景实体")
                    return
                }
                
                // 将旋转角度转换为四元数
                let rotationAngle = Float(value.radians * 2.0) // 增强旋转灵敏度
                let rotationAxis = SIMD3<Float>(0, 1, 0) // 主要围绕Y轴旋转
                
                let rotationQuat = simd_quatf(angle: rotationAngle, axis: rotationAxis)
                
                // 应用旋转
                rootEntity.orientation = rotationQuat
                
                // 添加实时反馈信息
                viewModel.lastAction = "正在旋转模型 [角度: \(String(format: "%.1f", value.degrees))°]"
            }
            .onEnded { _ in
                if viewModel.isRotating {
                    // 操作结束时更新状态
                    viewModel.lastAction = "旋转操作已完成"
                }
            }
    }
    
    // 缩放手势
    private func magnificationGesture(modelData: ProteinModelData) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // 只有在缩放模式下才处理缩放
                guard viewModel.isScaling else { return }
                
                print("⚠️ 缩放手势检测到变化，比例: \(value.magnitude)")
                
                guard let rootEntity = modelData.proteinViewer.getScene() else {
                    print("❌ 缩放手势：未能获取场景实体")
                    return
                }
                
                // 计算更灵敏的缩放因子
                let scaleFactor = Float(value.magnitude * 1.5)
                let currentScale = rootEntity.scale
                
                // 直接设置缩放值
                rootEntity.scale = SIMD3<Float>(
                    scaleFactor,
                    scaleFactor,
                    scaleFactor
                )
                
                // 添加实时反馈信息
                viewModel.lastAction = "正在缩放模型 [比例: \(String(format: "%.1f", scaleFactor))x]"
            }
            .onEnded { _ in
                if viewModel.isScaling {
                    // 操作结束时更新状态
                    viewModel.lastAction = "缩放操作已完成"
                }
            }
    }
    
    // MARK: - 辅助方法
    
    // 应用初始设置
    private func setupOnAppear() {
        // 确保在窗口打开时应用当前的显示设置
        if let modelData = appModel.proteinModels[modelID] {
            // 重置操作状态
            viewModel.resetAllModes()
            
            Task {
                // 应用当前显示模式
                await appModel.updateDisplayMode(appModel.displayMode)
                
                // 应用当前化学键显示设置
                if !appModel.showBonds {
                    appModel.toggleBonds()
                }
                
                // 重置位置以最佳显示
                await modelData.proteinViewer.resetAndAdaptToScreen()
                
                // 设置初始化完成提示
                viewModel.lastAction = "模型加载完成"
            }
        }
    }
    
    // 处理原子点击
    private func handleAtomTap(at index: Int) {
        print("处理原子点击，索引: \(index)")
        
        if appModel.isMeasuring {
            print("测量模式：添加测量点")
            appModel.addMeasurementPoint(at: index)
            print("已添加测量点，索引: \(index)，当前测量点数: \(appModel.measurementDistance != nil ? "2" : "1")")
        } else if viewModel.isChangingColor {
            print("颜色修改模式：选择原子")
            
            // 先清除之前选中的原子，确保界面状态正确更新
            appModel.selectedAtomIndex = nil
            
            // 选择原子
            appModel.selectAtom(at: index)
            
            // 只有当已经选择了颜色时，才应用颜色
            if let selectedColor = viewModel.selectedColor {
                print("已选择颜色，应用到原子: \(index)")
                applyColorToAtom(at: index, color: selectedColor)
                viewModel.lastAction = "已将颜色应用到原子 \(index)"
            } else {
                // 如果还没有选择颜色，提示用户选择颜色
                viewModel.lastAction = "已选中原子 \(index)，请先选择要应用的颜色"
            }
        } else {
            // 普通模式：仅显示原子信息，不选择原子，也不改变颜色
            print("普通模式：显示原子信息")
            // 不再调用selectAtom，仅显示信息
            viewModel.lastAction = "原子 \(index) 信息：点击颜色修改按钮可修改颜色"
        }
    }
    
    // 根据实体获取原子索引
    private func getAtomIndex(entity: ModelEntity, proteinViewer: ProteinViewer) -> Int? {
        // 委托给ProteinViewer获取索引
        return proteinViewer.getEntityAtomIndex(entity)
    }
    
    // 重置模型位置
    private func resetModelPosition() {
        if let modelData = appModel.proteinModels[modelID] {
            // 重置所有操作模式
            viewModel.resetAllModes()
            
            // 调用ProteinViewer的自适应方法来重置模型
            Task {
                await modelData.proteinViewer.resetAndAdaptToScreen()
                // 更新操作状态提示
                viewModel.lastAction = "模型位置已重置，所有颜色已恢复为默认"
                
                // 如果有选中的原子，取消选择
                if appModel.selectedAtomIndex != nil {
                    appModel.selectedAtomIndex = nil
                }
            }
        }
    }
    
    // 设置选中的颜色
    private func setSelectedColor(_ color: Color) {
        print("🎨 设置颜色: \(color)")
        
        // 播放触觉反馈增强用户体验
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        // 使用更生动的动画切换颜色
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            // 先判断是否为同一颜色，如果是则取消选择
            if viewModel.selectedColor == color {
                viewModel.selectedColor = nil
                print("🎨 取消选择颜色")
            } else {
                viewModel.selectedColor = color
                print("🎨 选择新颜色: \(color)")
            }
        }
        
        // 强制刷新UI，确保选中状态立即更新
        viewModel.objectWillChange.send()
        
        // 如果之前已经选中了原子，提示用户点击原子应用颜色
        if appModel.selectedAtomIndex != nil {
            viewModel.lastAction = "已选择颜色，点击原子应用此颜色"
        } else {
            viewModel.lastAction = "已选择颜色，点击需要改变颜色的原子"
        }
        
        // 不再自动应用颜色到之前选中的原子
        // 要求用户必须明确点击原子来应用颜色
    }
    
    // 将颜色应用到指定的原子
    private func applyColorToAtom(at index: Int, color: Color) {
        guard viewModel.isChangingColor else { return }
        guard let modelData = appModel.proteinModels[modelID] else {
            viewModel.lastAction = "模型数据不可用"
            return
        }
        
        // 应用颜色
        Task { @MainActor in
            // 将SwiftUI颜色转换为UIColor
            let uiColor = UIColor(color)
            
            // 调用ProteinViewer中的方法来更改原子颜色
            await modelData.proteinViewer.changeAtomColor(at: index, to: uiColor)
            
            // 更新用户界面反馈
            viewModel.lastAction = "已将原子 \(index) 的颜色修改为新颜色"
        }
    }
    
    // 应用颜色到所有原子
    private func applyColorToAll() {
        guard let selectedColor = viewModel.selectedColor else {
            viewModel.lastAction = "请先选择颜色"
            return
        }
        
        guard let modelData = appModel.proteinModels[modelID] else {
            viewModel.lastAction = "模型数据不可用"
            return
        }
        
        // 应用颜色到所有原子
        Task { @MainActor in
            // 将SwiftUI颜色转换为UIColor
            let uiColor = UIColor(selectedColor)
            
            // 调用ProteinViewer中的方法来更改所有原子颜色
            await modelData.proteinViewer.changeAllAtomsColor(to: uiColor)
            
            // 更新用户界面反馈
            viewModel.lastAction = "已将所有原子的颜色修改为新颜色"
        }
    }
}

// 扩展DisplayMode以支持在UI中显示和循环
extension ProteinViewer.DisplayMode: CaseIterable {
    static var allCases: [ProteinViewer.DisplayMode] {
        [.ballAndStick, .spaceFilling, .proteinRibbon, .proteinSurface]
    }
    
    var displayName: String {
        switch self {
        case .ballAndStick:
            return "球棍模型"
        case .spaceFilling:
            return "空间填充"
        case .proteinRibbon:
            return "飘带模型"
        case .proteinSurface:
            return "表面模型"
        }
    }
}

// 模型控制按钮
struct ModelControlButton: View {
    let systemName: String
    let label: String
    var isActive: Binding<Bool>? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: buttonAction) {
            buttonContent
        }
        .buttonStyle(.plain)
    }
    
    // 按钮点击动作
    private func buttonAction() {
            print("点击按钮: \(label)")
            action()
    }
    
    // 按钮内容视图
    private var buttonContent: some View {
        VStack(spacing: 8) {
            // 图标
                Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(isActiveValue ? .white : .primary)
                
            // 标签文本
                Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActiveValue ? .white : .primary)
        }
        .frame(width: 80, height: 80)
        .background(backgroundView)
        .overlay(overlayBorder)
        .scaleEffect(isActiveValue ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isActiveValue)
    }
    
    // 判断按钮是否激活
    private var isActiveValue: Bool {
        isActive?.wrappedValue == true
    }
    
    // 背景视图
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isActiveValue ? 
                  Color.blue.opacity(0.9) : 
                  Color(UIColor.systemBackground).opacity(0.6))
            .shadow(color: isActiveValue ? 
                    .blue.opacity(0.4) : 
                    .black.opacity(0.05), 
                    radius: 8, x: 0, y: 3)
    }
    
    // 边框叠加视图
    private var overlayBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isActiveValue ? 
                          Color.white.opacity(0.3) : 
                          Color.gray.opacity(0.2), 
                          lineWidth: 1)
    }
    
    init(systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
        print("初始化按钮: \(label)")
    }
    
    init(systemName: String, label: String, isActive: Binding<Bool>, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.isActive = isActive
        self.action = action
        print("初始化带状态的按钮: \(label), 初始状态: \(isActive.wrappedValue)")
    }
}

// 视图模型 - 控制状态
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
        
        // 使用更生动的动画效果
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        isChangingColor.toggle()
        }
        
        // 强制UI立即更新
        objectWillChange.send()
        
        if isChangingColor {
            print("🎨 已进入颜色修改模式，等待用户选择颜色")
            lastAction = "颜色修改模式已激活，请选择一个颜色，然后点击原子应用此颜色"
            // 关闭其他模式
            isRotating = false
            isMoving = false
            isScaling = false
        } else {
            print("🎨 已退出颜色修改模式")
            lastAction = "颜色修改模式已关闭"
            // 退出颜色修改模式时清除选择的颜色
            DispatchQueue.main.async {
                self.selectedColor = nil
                self.objectWillChange.send()
                print("💧 清除已选颜色")
            }
        }
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

// 颜色选择按钮
struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let onSelect: () -> Void
    
    // 添加指示是否按下的状态
    @State private var isPressed: Bool = false
    @State private var showConfirmation: Bool = false
    
    var body: some View {
        Button(action: buttonAction) {
            buttonContent
        }
        .buttonStyle(.plain)
        // 使用极大的点击区域确保能被点击
        .contentShape(Circle().scale(1.8))
        .padding(1)
        // 添加按下状态追踪
        .onLongPressGesture(minimumDuration: .infinity, pressing: handlePressing, perform: {})
        // 选中状态的动画
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.15), value: isSelected)
    }
    
    // 按钮点击动作
    private func buttonAction() {
        // 增加按钮点击时的日志，帮助调试
        print("颜色按钮被点击: \(color)")
        
        // 播放触觉反馈
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
        
        // 显示选择确认动画
        withAnimation(.spring(response: 0.2)) {
            showConfirmation = true
        }
        
        // 短暂延迟后隐藏确认动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                showConfirmation = false
            }
        }
        
        // 调用选择回调
        onSelect()
    }
    
    // 处理按下状态变化
    private func handlePressing(_ pressing: Bool) {
        withAnimation(.easeInOut(duration: 0.1)) {
            self.isPressed = pressing
        }
    }
    
    // 按钮内容视图
    private var buttonContent: some View {
        ZStack {
            // 使用更大的圆形背景增加点击区域
            Circle()
                .fill(Color.clear)
                .frame(width: 50, height: 50)
            
            // 实际颜色圆形
            colorCircle
            
            // 边框和选中状态
            selectionIndicator
            
            // 选择确认动画
            confirmationAnimation
        }
    }
    
    // 颜色圆形
    private var colorCircle: some View {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
            .shadow(color: color.opacity(isPressed ? 0.8 : 0.6), 
                    radius: isPressed ? 3 : 2, 
                    x: 0, 
                    y: isPressed ? 1 : 2)
            // 按下时缩小效果
            .scaleEffect(isPressed ? 0.95 : 1.0)
    }
    
    // 边框和选中状态指示器
    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            // 选中状态显示边框和对勾
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                .frame(width: 36, height: 36)
            
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 36, height: 36)
        }
    }
    
    // 选择确认动画
    @ViewBuilder
    private var confirmationAnimation: some View {
        if showConfirmation && !isSelected {
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(showConfirmation ? 1.2 : 1.0)
                .opacity(showConfirmation ? 0 : 1)
        }
    }
    
    init(color: Color, isSelected: Bool = false, onSelect: @escaping () -> Void) {
        self.color = color
        self.isSelected = isSelected
        self.onSelect = onSelect
        print("初始化颜色按钮: \(color), 选中状态: \(isSelected)")
    }
}

#Preview {
    // 创建一个临时的UUID和AppModel用于预览
    let previewModelID = UUID()
    let appModel = AppModel()
    let previewViewer = ProteinViewer()
    let modelData = ProteinModelData(id: previewModelID, proteinViewer: previewViewer)
    appModel.proteinModels[previewModelID] = modelData
    
    return ProteinModelView(modelID: previewModelID)
        .environmentObject(appModel)
}
