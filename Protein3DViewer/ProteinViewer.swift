import SwiftUI
import RealityKit
import Metal
import MetalKit
import Combine
import Foundation
import ModelIO
import simd

// 添加PDB信息结构体
struct PDBInfo {
    var name: String = "未知"
    var description: String = ""
    var atomCount: Int = 0
    var resolution: Float? = nil
}

@MainActor
class ProteinViewer: ObservableObject {
    // MARK: - Display Mode
    enum DisplayMode {
        case ballAndStick    // 球棍模型
        case spaceFilling    // 空间填充模型
        case proteinRibbon   // 蛋白质飘带模型
        case proteinSurface  // 蛋白质表面模型
    }
    
    // MARK: - Data Types
    struct AtomData {
        let element: String
        let position: SIMD3<Float>
        let index: Int
    }
    
    struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let index: UInt32
    }
    
    // MARK: - Metal & RealityKit Properties
    private var metalDevice: MTLDevice?
    private var metalCommandQueue: MTLCommandQueue?
    // Metal着色器相关属性
    private var metalLibrary: MTLLibrary?
    private var vertexFunction: MTLFunction?
    private var fragmentFunction: MTLFunction?
    private var pipelineState: MTLRenderPipelineState?
    
    private var rootEntity: Entity?
    private var atomsEntity = Entity()
    private var bondsEntity = Entity()
    
    // 状态和数据
    private var atomsData: [AtomData] = []
    private var displayMode: DisplayMode = .ballAndStick
    private var selectedAtoms: Set<Int> = []
    private var showBonds: Bool = true
    private var atomEntityMap: [Int: ModelEntity] = [:] // 映射原子索引到实体
    private var directionalLight: DirectionalLight?
    
    // 测量相关
    private var measurementPoints: [Int] = []
    private var measurementLines: [Entity] = []
    
    // 状态跟踪
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Float = 0.0
    @Published var errorMessage: String? = nil
    
    // MARK: - Constants
    private enum Constants {
        static let atomColors: [String: SIMD4<Float>] = [
            "H": SIMD4<Float>(1.0, 1.0, 1.0, 1.0), // 白色
            "C": SIMD4<Float>(0.8, 0.8, 0.8, 1.0), // 灰色
            "N": SIMD4<Float>(0.0, 0.0, 1.0, 1.0), // 蓝色
            "O": SIMD4<Float>(1.0, 0.0, 0.0, 1.0), // 红色
            "P": SIMD4<Float>(1.0, 0.5, 0.0, 1.0), // 橙色
            "S": SIMD4<Float>(1.0, 1.0, 0.0, 1.0), // 黄色
            "FE": SIMD4<Float>(0.65, 0.35, 0.2, 1.0), // 棕色
            "ZN": SIMD4<Float>(0.5, 0.5, 0.5, 1.0), // 灰色
            "MG": SIMD4<Float>(0.0, 0.8, 0.0, 1.0), // 绿色
            "CA": SIMD4<Float>(1.0, 0.5, 0.8, 1.0), // 粉色
            
            "CL": SIMD4<Float>(0.0, 1.0, 0.0, 1.0), // 氯 - 绿色
            "F": SIMD4<Float>(0.0, 0.8, 0.8, 1.0), // 氟 - 青绿色
            "BR": SIMD4<Float>(0.6, 0.2, 0.2, 1.0), // 溴 - 深红棕
            "I": SIMD4<Float>(0.4, 0.0, 0.8, 1.0), // 碘 - 深紫
            
            "CU": SIMD4<Float>(0.8, 0.5, 0.2, 1.0), // 铜 - 铜橘色
            "MN": SIMD4<Float>(0.6, 0.6, 0.8, 1.0), // 锰 - 蓝灰
            "CO": SIMD4<Float>(1.0, 0.0, 1.0, 1.0), // 钴 - 紫色
            "NI": SIMD4<Float>(0.3, 0.8, 0.8, 1.0), // 镍 - 青蓝色
            
            "NA": SIMD4<Float>(0.2, 0.2, 1.0, 1.0), // 钠 - 蓝紫
            "K": SIMD4<Float>(0.5, 0.1, 1.0, 1.0), // 钾 - 紫色
            
            "B": SIMD4<Float>(1.0, 0.7, 0.7, 1.0), // 硼 - 淡粉红
            "X": SIMD4<Float>(0.8, 0.0, 0.8, 1.0) // 紫红色
        ]
        
        // 增加原子半径，使其更接近真实的van der Waals半径
        static let atomRadii: [String: Float] = [
            "H": 0.030,
            "C": 0.040, 
            "N": 0.038, 
            "O": 0.035, 
            "P": 0.042, 
            "S": 0.043, 
            "FE": 0.045, 
            "ZN": 0.042, 
            "MG": 0.041, 
            "CA": 0.047, 
            
            "CL": 0.044, 
            "F": 0.038,  
            "BR": 0.045, 
            "I": 0.048, 
            
            "CU": 0.045, 
            "MN": 0.043, 
            "CO": 0.035,
            "NI": 0.041, 
            
            "NA": 0.045, 
            "K": 0.050,  
            
            "B": 0.038, 
            "X": 0.040   
        ]
        
        
        static let maxAtoms = 1000
        static let bondRadius: Float = 0.01 // 从0.02增加到0.01，使键更细以确保可见
        static let bondMaxLength: Float = 2.5 // 从2.0增加到2.5，允许更长的化学键
        static let measurementLineRadius: Float = 0.02
        static let bondColor: UIColor = .gray // 使用灰色
        
        // 增加van der Waals半径，使其更接近真实的van der Waals半径
        static let vanDerWaalsRadii: [String: Float] = [
            "H": 0.030,
            "C": 0.040, 
            "N": 0.038, 
            "O": 0.035, 
            "P": 0.042, 
            "S": 0.043, 
            "FE": 0.045, 
            "ZN": 0.042, 
            "MG": 0.041, 
            "CA": 0.047, 
            
            "CL": 0.044, 
            "F": 0.038,  
            "BR": 0.045, 
            "I": 0.048, 
            
            "CU": 0.045, 
            "MN": 0.043, 
            "CO": 0.035,
            "NI": 0.041, 
            
            "NA": 0.045, 
            "K": 0.050,  
            
            "B": 0.038, 
            "X": 0.040   
        ]
    }
    
    // MARK: - Initialization
    init() {
        print("初始化ProteinViewer")
        setupMetal()
        setupScene()
    }
    
    private func setupMetal() {
        // 获取默认Metal设备
        metalDevice = MTLCreateSystemDefaultDevice()
        
        guard let device = metalDevice else {
            print("警告：无法创建Metal设备")
            return
        }
        
        metalCommandQueue = device.makeCommandQueue()
        print("Metal设备初始化成功")
        
        // 加载Metal着色器
        do {
            // 从默认位置加载着色器文件
            metalLibrary = try device.makeDefaultLibrary(bundle: Bundle.main)
            print("Metal库加载成功")
            
            // 获取顶点和片段着色器函数
            if let library = metalLibrary {
                vertexFunction = library.makeFunction(name: "vertexShader")
                fragmentFunction = library.makeFunction(name: "fragmentShader")
                
                if vertexFunction != nil && fragmentFunction != nil {
                    print("着色器函数加载成功")
                    
                    // 创建渲染管线状态
                    let pipelineDescriptor = MTLRenderPipelineDescriptor()
                    pipelineDescriptor.vertexFunction = vertexFunction
                    pipelineDescriptor.fragmentFunction = fragmentFunction
                    
                    // 设置颜色格式
                    pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                    
                    // 创建顶点描述符
                    let vertexDescriptor = MTLVertexDescriptor()
                    vertexDescriptor.attributes[0].format = .float3
                    vertexDescriptor.attributes[0].offset = 0
                    vertexDescriptor.attributes[0].bufferIndex = 0
                    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
                    
                    // 添加纹理坐标属性
                    vertexDescriptor.attributes[1].format = .float2
                    vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
                    vertexDescriptor.attributes[1].bufferIndex = 0
                    vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
                    
                    // 将顶点描述符设置到渲染管线描述符
                    pipelineDescriptor.vertexDescriptor = vertexDescriptor
                    
                    // 创建渲染管线状态
                    do {
                        pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                        print("渲染管线状态创建成功")
                    } catch {
                        print("创建渲染管线状态失败: \(error.localizedDescription)")
                    }
                } else {
                    print("警告：无法加载着色器函数，请检查函数名称是否正确")
                }
            }
        } catch {
            print("加载Metal库失败: \(error.localizedDescription)")
        }
    }
    
    private func setupScene() {
        // 创建根实体和子实体
        rootEntity = Entity()
        atomsEntity = Entity()
        bondsEntity = Entity()
        bondsEntity.isEnabled = true // 确保键实体默认可见
        
        if let rootEntity = rootEntity {
            // 添加子实体到根实体
            rootEntity.addChild(atomsEntity)
            rootEntity.addChild(bondsEntity)
            print("场景初始化：bondsEntity已添加到rootEntity，isEnabled=\(bondsEntity.isEnabled)")
        }
    }
    
    // MARK: - Public Methods
    func getScene() -> Entity? {
        return rootEntity
    }
    
    // 新增自适应屏幕的重置方法
    @MainActor
    func resetAndAdaptToScreen() async {
        print("重置模型位置并自适应屏幕")
        
        // 如果没有根实体或没有原子数据，直接返回
        guard let rootEntity = rootEntity, !atomsData.isEmpty else {
            print("没有可重置的模型")
            return
        }
        
        // 重置所有修改过颜色的原子到原始颜色
        print("准备重置所有修改过的原子颜色")
        resetAllModifiedAtomColors()
        print("已恢复所有原子到默认颜色")
        
        // 完全重置状态
        // 重置缩放到1.0
        rootEntity.scale = [1.0, 1.0, 1.0]
        // 重置位置到原点
        rootEntity.position = [0, 0, 0]
        // 重置原子位置
        atomsEntity.position = [0, 0, 0]
        
        // 重置旋转到默认方向
        rootEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        
        // 应用自适应调整
        adjustModelForVisibility()
        
        // 对每个原子材质重新应用默认设置，确保一切恢复正常
        for (index, atomData) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] as? ModelEntity {
                // 获取原子元素
                let element = atomData.element.uppercased()
                
                // 获取元素的默认颜色
                let colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
                
                // 创建UIColor
                let defaultColor = UIColor(
                    red: CGFloat(colorRGBA.x),
                    green: CGFloat(colorRGBA.y),
                    blue: CGFloat(colorRGBA.z),
                    alpha: CGFloat(colorRGBA.w)
                )
                
                // 创建新材质
                var material = SimpleMaterial()
                material.color = .init(tint: defaultColor)
                material.roughness = .init(floatLiteral: 0.5)
                material.metallic = .init(floatLiteral: 0.05)
                
                // 应用材质
                atomEntity.model?.materials = [material]
            }
        }
        
        // 发送变更通知
        objectWillChange.send()
        
        print("模型已完全重置并自适应屏幕，所有颜色已恢复默认")
    }
    
    func loadPDBFile(from url: URL, lowQualityMode: Bool = true) async throws {
        // 设置状态
        isLoading = true
        loadingProgress = 0.0
        errorMessage = nil
        objectWillChange.send()
        
        print("开始加载PDB文件: \(url.lastPathComponent), 低质量模式: \(lowQualityMode)")
        
        do {
            // 完全重置根实体的状态
            if let rootEntity = rootEntity {
                rootEntity.scale = [1.0, 1.0, 1.0]  // 重置缩放
                rootEntity.position = [0, 0, 0]     // 重置位置
                if atomsEntity.parent != nil {
                    atomsEntity.position = [0, 0, 0]    // 重置原子位置
                }
            }
            
            // 解析PDB文件
            let pdbData = try String(contentsOf: url, encoding: .utf8)
            
            // 创建和填充PDB信息对象
            var newPDBInfo = PDBInfo()
            newPDBInfo.name = url.deletingPathExtension().lastPathComponent
            
            // 扫描PDB头信息
            let lines = pdbData.split(separator: "\n")
            for line in lines.prefix(50) { // 只检查前50行以找到头信息
                let lineStr = String(line)
                
                if lineStr.hasPrefix("HEADER") && lineStr.count > 10 {
                    // 提取标题信息
                    let headerInfo = lineStr.dropFirst(10).trimmingCharacters(in: .whitespaces)
                    if !headerInfo.isEmpty {
                        newPDBInfo.name = headerInfo
                    }
                } else if lineStr.hasPrefix("TITLE") && lineStr.count > 10 {
                    // 提取描述信息
                    let titleInfo = lineStr.dropFirst(10).trimmingCharacters(in: .whitespaces)
                    if !titleInfo.isEmpty {
                        if newPDBInfo.description.isEmpty {
                            newPDBInfo.description = titleInfo
                        } else {
                            newPDBInfo.description += " " + titleInfo
                        }
                    }
                } else if lineStr.hasPrefix("REMARK   2 RESOLUTION.") && lineStr.count > 25 {
                    // 提取分辨率信息
                    let resolutionText = lineStr.dropFirst(25).trimmingCharacters(in: .whitespaces)
                    if let endIndex = resolutionText.firstIndex(of: "A") {
                        let valueText = resolutionText[..<endIndex].trimmingCharacters(in: .whitespaces)
                        newPDBInfo.resolution = Float(valueText)
                    }
                }
            }
            
            var allAtoms = try parsePDBFile(pdbData)
            print("成功解析PDB文件，获取到\(allAtoms.count)个原子")
            
            // 更新原子数量信息
            newPDBInfo.atomCount = allAtoms.count
            
            // 限制原子数量
            let maxAtoms = Constants.maxAtoms
            if allAtoms.count > maxAtoms {
                let step = allAtoms.count / maxAtoms
                allAtoms = stride(from: 0, to: allAtoms.count, by: step).map { allAtoms[$0] }
                print("限制后原子数量: \(allAtoms.count)")
            }
            
            // 发布PDB信息
            self.pdbInfo = newPDBInfo
            
            loadingProgress = 0.3
            objectWillChange.send()
            
            // 预处理数据
            prepareAtomData(from: allAtoms)
            print("准备原子数据完成，总共\(atomsData.count)个原子")
            
            loadingProgress = 0.5
            objectWillChange.send()
            
            // 使用RealityKit创建基础模型
            await createRealityKitModel(lowQualityMode: lowQualityMode)
            print("模型创建完成")
            
            loadingProgress = 0.8
            objectWillChange.send()
            
            // 使用自适应方法调整模型位置和大小
            let modelSize = calculateModelSize()
            adjustModelForVisibility(modelSize: modelSize)
            print("模型已自适应屏幕，大小: \(modelSize)")
            
            // 发布模型尺寸信息，通知UI可能需要调整
            modelSizeChanged(modelSize)
            
            loadingProgress = 1.0
            isLoading = false
            objectWillChange.send()
            print("PDB文件加载完成，通知已发送")
            
        } catch {
            print("处理PDB文件时出错: \(error.localizedDescription)")
            isLoading = false
            errorMessage = "加载失败: \(error.localizedDescription)"
            objectWillChange.send()
            throw error
        }
    }
    
    // 新增：计算模型的尺寸信息
    private func calculateModelSize() -> SIMD3<Float> {
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        
        for atom in atomsData {
            minBounds = min(minBounds, atom.position)
            maxBounds = max(maxBounds, atom.position)
        }
        
        return maxBounds - minBounds
    }
    
    // 添加用于通知外部的模型尺寸变化方法
    @Published var modelWidth: Float = 0
    @Published var modelHeight: Float = 0
    @Published var modelDepth: Float = 0
    
    private func modelSizeChanged(_ size: SIMD3<Float>) {
        modelWidth = size.x
        modelHeight = size.y
        modelDepth = size.z
        
        // 发布通知以便UI组件可以响应尺寸变化
        objectWillChange.send()
    }
    
    // 修改后的模型调整方法，增加对称居中处理
    private func adjustModelForVisibility(modelSize: SIMD3<Float>? = nil) {
        print("自动调整模型大小和位置以适应屏幕")
        
        guard !atomsData.isEmpty else {
            print("没有原子数据，无法调整视图")
            return
        }
        
        guard let rootEntity = rootEntity else { return }
        
        // 使用传入的模型尺寸或重新计算
        let size = modelSize ?? calculateModelSize()
        
        // 计算边界
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        
        for atomData in atomsData {
            let position = atomData.position
            let element = atomData.element
            let radius = (Constants.atomRadii[element] ?? 0.04) * 1.2
            
            let atomMin = position - SIMD3<Float>(radius, radius, radius)
            let atomMax = position + SIMD3<Float>(radius, radius, radius)
            
            minBounds = min(minBounds, atomMin)
            maxBounds = max(maxBounds, atomMax)
        }
        
        let center = (minBounds + maxBounds) * 0.5
        let maxDimension = max(max(size.x, size.y), size.z)
        
        var scaleFactor: Float = 1.0
        if maxDimension > 0.001 {
            // 调整缩放因子算法，确保大型分子有合适的显示大小
            scaleFactor = 1.0 / maxDimension
            
            // 更智能的缩放算法 - 根据分子大小动态调整
            if maxDimension > 5.0 {
                // 特大分子
                scaleFactor *= 0.8
            } else if maxDimension > 3.0 {
                // 大分子
                scaleFactor *= 0.9
            } else if maxDimension < 0.5 {
                // 小分子
                scaleFactor *= 1.2
            }
            
            // 确保缩放在合理范围内
            scaleFactor = min(max(scaleFactor, 0.001), 5.0)
        }
        
        // 设置原子实体的位置为中心的负值，使模型居中
        atomsEntity.position = -center
        atomsEntity.scale = [1.0, 1.0, 1.0] // 重置atomsEntity的scale
        
        bondsEntity.position = -center
        bondsEntity.scale = [1.0, 1.0, 1.0] // bondsEntity也重置
        
        // 最后统一调整rootEntity的缩放
        rootEntity.scale = [scaleFactor, scaleFactor, scaleFactor]
        
        // 重要：确保模型在z轴上有合适的位置
        let zOffset: Float = -1.0 // 基础z偏移
        
        // 根据模型大小调整z轴位置，越大的分子显示位置越远
        let sizeBasedZOffset = min(maxDimension * 0.1, 0.5) // 限制额外偏移最大为0.5
        rootEntity.position.z = zOffset - sizeBasedZOffset
        
        print("调整完成: center=\(center), scale=\(scaleFactor), size=\(size), z位置=\(rootEntity.position.z)")
    }
    
    // 新增：获取模型显示推荐UI边距的方法
    func getRecommendedUIPadding() -> Float {
        // 根据模型宽度计算推荐的UI边距
        let baseMargin: Float = 0.1 // 基础边距
        let sizeMargin = max(modelWidth - 1.0, 0) * 0.05 // 根据大小动态增加边距
        return baseMargin + sizeMargin
    }
    
    // MARK: - 数据准备和渲染
    private func prepareAtomData(from pdbAtoms: [PDBAtom]) {
        // 清空现有数据
        atomsData.removeAll()
        
        // 转换为AtomData
        for (index, atom) in pdbAtoms.enumerated() {
            let atomData = AtomData(
                element: atom.element,
                position: [atom.x, atom.y, atom.z],
                index: index
            )
            atomsData.append(atomData)
        }
    }
    
    private func createRealityKitModel(lowQualityMode: Bool) async {
        // 清空当前实体
        atomsEntity.children.removeAll()
        bondsEntity.children.removeAll()
        atomEntityMap.removeAll()
        
        // 定义共享网格资源 - 为了提高性能，只为每种元素创建一个网格
        var meshResources: [String: MeshResource] = [:]
        
        // 创建原子模型
        for (index, atomData) in atomsData.enumerated() {
            let element = atomData.element
            
            // 跳过未知原子（X元素）的显示
            if element == "X" {
                print("跳过未知原子 (X) 的显示，索引: \(index)")
                continue
            }
            
            // 获取或创建该元素的网格资源
            if meshResources[element] == nil {
                var radius: Float = 0.0
                
                // 获取半径
                radius = Constants.atomRadii[element] ?? 0.25  // 使用常量中定义的半径
                
                // 使用较高的细分度来提高球体质量
                let subdivision = lowQualityMode ? 8 : 12  // 增加细分度
                meshResources[element] = .generateSphere(radius: radius)
            }
            
            if let mesh = meshResources[element] {
                // 使用共享网格创建原子实体
                let atomEntity = ModelEntity(mesh: mesh)
                atomEntity.position = atomData.position
                atomEntity.name = "atom_\(index)" // ✅ 添加名称
                atomEntity.generateCollisionShapes(recursive: false)

                
                // 设置材质 - 使用更高质量的材质
                var material = SimpleMaterial()
                
                // 使用常量中的颜色
                var colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0) // 默认紫色
                
                material.color = .init(tint: UIColor(red: CGFloat(colorRGBA.x),
                                                     green: CGFloat(colorRGBA.y),
                                                     blue: CGFloat(colorRGBA.z),
                                                     alpha: CGFloat(colorRGBA.w)))
                
                // 添加适度的材质属性，降低金属感和光滑度
                material.roughness = .init(floatLiteral: 0.5)  // 增加粗糙度
                material.metallic = .init(floatLiteral: 0.05)  // 大幅降低金属感
                
                atomEntity.model?.materials = [material]
                atomsEntity.addChild(atomEntity)
                atomEntityMap[index] = atomEntity
                
                // 每批次处理后暂停一下，避免UI冻结
                if index % 20 == 0 && index > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
        
        // 在球棍模型或蛋白质飘带模型下创建化学键
        if displayMode == .ballAndStick || displayMode == .proteinRibbon {
            // 球棍模型下创建更真实的化学键
            if displayMode == .ballAndStick {
                print("球棍模型：准备创建化学键，总原子数：\(atomsData.count)")
                // 使用新方法创建符合化学原理的键
                await createChemicalBonds()
            }
            // 飘带模型下，仅当原子数量较少时创建键
            else if displayMode == .proteinRibbon && !lowQualityMode && atomsData.count < 100 {
                await createSimpleBonds()
            }
        }
        
        // 在空间填充模型下，优化原子间距离以使其更贴合
        if displayMode == .spaceFilling {
            await optimizeSpaceFillingPositions()
        }
        
        // 在所有模型创建完成后自动调整大小和位置
        adjustModelForVisibility()
    }
    
    // 添加新方法恢复原子的原始位置
    private func restoreOriginalAtomPositions() async {
        // 恢复原子位置到原始数据
        for (index, atomData) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] {
                // 恢复原始位置
                atomEntity.position = atomData.position
                
                // 恢复材质和颜色
                let element = atomData.element
                var material = SimpleMaterial()
                
                // 获取原始颜色
                let colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                
                // 设置基本材质属性
                material.color = .init(tint: UIColor(
                    red: CGFloat(colorRGBA.x),
                    green: CGFloat(colorRGBA.y),
                    blue: CGFloat(colorRGBA.z),
                    alpha: CGFloat(colorRGBA.w)))
                
                material.roughness = .init(floatLiteral: 0.5)  // 标准粗糙度
                material.metallic = .init(floatLiteral: 0.05)  // 低金属感
                
                atomEntity.model?.materials = [material]
                
                // 确保原子可见
                atomEntity.isEnabled = true
                
                // 每批次处理后暂停一下避免UI冻结
                if index % 20 == 0 && index > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                }
            }
        }
        
        // 恢复完成后，立即应用合适的缩放和属性
        updateAtomDisplay()
        
        // 居中模型确保视野正确
        centerModel()
    }
    
    // 修改optimizeSpaceFillingPositions方法，改进原子间的紧凑算法，确保空间填充模型中原子之间无间隙
    private func optimizeSpaceFillingPositions() async {
        print("优化空间填充模型原子位置")
        
        // 备份原始位置，以便切换回其他模式时恢复
        var originalPositions: [Int: SIMD3<Float>] = [:]
        for (index, _) in atomsData.enumerated() {
            if let atom = atomEntityMap[index] {
                originalPositions[index] = atom.position
            }
        }
        
        // 使用负值使原子彼此重叠
        let distanceAdjustmentFactor: Float = 0.82
        // 增大原子尺寸
        let atomScaleFactor: Float = 4.0
        
        // 创建临时数据结构用于优化
        var positions: [Int: SIMD3<Float>] = [:]
        var radii: [Int: Float] = [:]
        var adjustedPositions: [Int: SIMD3<Float>] = [:]
        
        // 初始化原子数据
        for (index, atomData) in atomsData.enumerated() {
            guard let atom = atomEntityMap[index] else { continue }
            positions[index] = atom.position
            let element = atomData.element
            
            // 根据元素类型调整半径
            var radiusMultiplier: Float = 1.0
            if element == "H" { radiusMultiplier = 0.9 }    // 氢原子稍小
            else if element == "C" { radiusMultiplier = 1.0 } // 碳原子标准大小
            else if element == "O" { radiusMultiplier = 1.05 } // 氧原子稍大
            else if element == "N" { radiusMultiplier = 1.05 } // 氮原子稍大
            else if element == "S" { radiusMultiplier = 1.1 }  // 硫原子更大
            else if element == "CO" { radiusMultiplier = 0.6 } // 钴原子明显缩小，避免体积超大
            
            radii[index] = (Constants.atomRadii[element] ?? 0.25) * atomScaleFactor * radiusMultiplier
        }
        
        // 创建网格以优化相邻原子搜索
        let gridSize: Float = 1.0
        var grid: [SIMD3<Int>: [Int]] = [:]
        
        // 将原子放入网格
        for (index, position) in positions {
            let gridPos = SIMD3<Int>(
                Int(position.x / gridSize),
                Int(position.y / gridSize),
                Int(position.z / gridSize)
            )
            grid[gridPos, default: []].append(index)
        }
        func getEntityAtomIndex(_ entity: ModelEntity) -> Int? {
            let name = entity.name
            if name.starts(with: "atom_") {
                let indexString = name.replacingOccurrences(of: "atom_", with: "")
                return Int(indexString)
            }
            return nil
        }


        // 获取一个原子邻近的网格位置
        func getNeighborGridPositions(_ position: SIMD3<Float>) -> [SIMD3<Int>] {
            let gridPos = SIMD3<Int>(
                Int(position.x / gridSize),
                Int(position.y / gridSize),
                Int(position.z / gridSize)
            )
            var neighbors: [SIMD3<Int>] = []
            
            // 检查周围27个网格位置
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        neighbors.append(SIMD3<Int>(gridPos.x + dx, gridPos.y + dy, gridPos.z + dz))
                    }
                }
            }
            return neighbors
        }
        
        // 执行多次迭代，逐步优化位置
        for iteration in 0..<6 {
            // 调整系数随迭代次数变化，后期迭代调整更精细
            let adjustFactor: Float = 1.0 - Float(iteration) * 0.15
            // 增加重叠因子，让分子越来越紧凑
            let overlapFactor: Float = distanceAdjustmentFactor + Float(iteration) * 0.02
            
            // 更新网格
            grid.removeAll()
            for (index, position) in positions {
                let gridPos = SIMD3<Int>(
                    Int(position.x / gridSize),
                    Int(position.y / gridSize),
                    Int(position.z / gridSize)
                )
                grid[gridPos, default: []].append(index)
            }
            
            for i in 0..<atomsData.count {
                guard let atom1Position = positions[i], let radius1 = radii[i] else { continue }
                
                var totalForce = SIMD3<Float>(0, 0, 0)
                var interactionCount = 0
                
                // 获取可能相互作用的邻近原子
                let neighborGridPositions = getNeighborGridPositions(atom1Position)
                var neighborIndices: [Int] = []
                
                for gridPos in neighborGridPositions {
                    if let atoms = grid[gridPos] {
                        neighborIndices.append(contentsOf: atoms)
                    }
                }
                
                // 对每个邻近原子计算力
                for j in neighborIndices where j != i {
                    guard let atom2Position = positions[j], let radius2 = radii[j] else { continue }
                    
                    let distance = length(atom1Position - atom2Position)
                    let idealDistance = (radius1 + radius2) * overlapFactor
                    
                    if distance < 0.01 { // 防止除以零或极小值
                        // 原子完全重合，随机分开
                        let randomDir = normalize(SIMD3<Float>(
                            Float.random(in: -1...1),
                            Float.random(in: -1...1),
                            Float.random(in: -1...1)
                        ))
                        totalForce += randomDir * 0.1
                        interactionCount += 1
                        continue
                    }
                    
                    if distance < idealDistance * 0.98 {
                        // 原子太近，需要推开
                        let direction = normalize(atom1Position - atom2Position)
                        let repulsionStrength = (idealDistance - distance) / idealDistance * 0.8 * adjustFactor
                        totalForce += direction * repulsionStrength * radius1
                        interactionCount += 1
                    } else if distance < idealDistance * 1.02 {
                        // 原子距离正好，不调整
                        continue
                    } else if distance < idealDistance * 3.0 {
                        // 原子太远，需要拉近 (从2.5增加到3.0)
                        let direction = normalize(atom2Position - atom1Position)
                        let attractionStrength = (distance - idealDistance) / idealDistance * 0.4 * adjustFactor
                        totalForce += direction * attractionStrength * radius1
                        interactionCount += 1
                    }
                }
                
                if interactionCount > 0 {
                    let averageForce = totalForce / Float(interactionCount)
                    let newPosition = atom1Position + averageForce
                    adjustedPositions[i] = newPosition
                } else {
                    adjustedPositions[i] = atom1Position
                }
            }
            
            // 更新位置
            for (index, newPosition) in adjustedPositions {
                positions[index] = newPosition
            }
            
            // 更短的暂停时间以提高性能
            if iteration % 2 == 0 {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        
        // 应用最终的优化位置
        for (index, finalPosition) in positions {
            if let atomEntity = atomEntityMap[index] {
                atomEntity.position = finalPosition
                atomEntity.scale = [atomScaleFactor, atomScaleFactor, atomScaleFactor]
            }
        }
        
        // 增强颜色
        enhanceSpaceFillingColors()
    }
    
    private func createSimpleBonds() async {
        let maxAtomsForBonds = atomsData.count
        // 使用非常细的键半径
        let bondRadius: Float = Constants.bondRadius * 0.4 // 使键更加细，从0.6减小到0.4
        let bondThreshold: Float = 2.2 // 从1.8增加到2.2埃，允许检测更长的化学键
        let maxBonds = Constants.maxAtoms * 5 // 增加最大键数量，从2倍增加到5倍
        var bondCount = 0
        
        // 创建一个词典来存储已经连接的原子对，避免重复连接
        var connectedPairs = Set<String>()
        
        print("开始创建化学键，阈值：\(bondThreshold)埃，最大键数：\(maxBonds)")
        
        for i in 0..<maxAtomsForBonds {
            for j in (i+1)..<atomsData.count {
                if bondCount >= maxBonds { break }
                
                // 计算两原子间距离
                let distance = length(atomsData[i].position - atomsData[j].position)
                
                // 创建一个原子对的唯一标识，避免重复连接
                let pairKey = "\(min(i, j))-\(max(i, j))"
                
                // 如果距离小于阈值且尚未连接，则创建键
                if distance <= bondThreshold && !connectedPairs.contains(pairKey) {
                    connectedPairs.insert(pairKey)
                    
                    let start = atomsData[i].position
                    let end = atomsData[j].position
                    let midpoint = (start + end) / 2
                    let direction = normalize(end - start)
                    
                    // 使用圆柱体表示化学键（很细的棒状）
                    let bondEntity = ModelEntity(
                        mesh: .generateCylinder(height: distance, radius: bondRadius),
                        materials: [SimpleMaterial(color: Constants.bondColor, roughness: 0.2, isMetallic: true)]
                    )
                    bondEntity.position = midpoint
                    if abs(direction.y) > 0.99 {
                        bondEntity.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
                    } else {
                        let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
                        let rotationAngle = acos(direction.y)
                        bondEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                    }
                    
                    // 调整材质为稍微带一点金属感
                    if var material = bondEntity.model?.materials.first as? SimpleMaterial {
                        material.metallic = .init(floatLiteral: 0.1) // 添加轻微金属感
                        bondEntity.model?.materials = [material]
                    }
                    
                    bondsEntity.addChild(bondEntity)
                    bondCount += 1
                }
            }
            if bondCount >= maxBonds { break }
            
            // 每处理50个原子暂停一下，避免UI冻结
            if i % 50 == 0 && i > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
        
        print("创建了\(bondCount)个化学键")
    }
    
    private func createChemicalBonds() async {
        // 清空现有键，确保从头创建
        bondsEntity.children.removeAll()
        
        let maxAtomsForBonds = atomsData.count
        // 使用较粗的键半径以确保可见性
        let bondRadius: Float = Constants.bondRadius * 0.8 // 使键粗细适中
        let bondThreshold: Float = 2.2 // 从1.8增加到2.2埃，允许检测更长的化学键
        let maxBonds = Constants.maxAtoms * 5 // 最大键数量
        var bondCount = 0
        
        print("开始创建真实化学键，阈值：\(bondThreshold)埃")
        
        // 跟踪每个原子已经形成的键数量
        var atomBondCounts: [Int: Int] = [:]
        
        // 创建一个词典来存储已经连接的原子对，避免重复连接
        var connectedPairs = Set<String>()
        
        // 获取原子允许的最大键数
        func getMaxBonds(forElement element: String) -> Int {
            switch element.uppercased() {
            case "C": return 4  // 碳原子连四个键
            case "N": return 3  // 氮原子连三个键
            case "O", "S": return 2  // 氧原子和硫原子连两个键
            case "H": return 1  // 氢原子连一个键
            default: return 2   // 其他元素默认连两个键
            }
        }
        
        // 首先为所有原子预设键数量为0
        for i in 0..<atomsData.count {
            atomBondCounts[i] = 0
        }
        
        // 按照距离排序所有可能的原子对，优先处理距离较短的原子对
        struct AtomPair {
            let atom1Index: Int
            let atom2Index: Int
            let distance: Float
        }
        
        var potentialBonds: [AtomPair] = []
        
        // 找出所有可能的原子对
        for i in 0..<maxAtomsForBonds {
            // 跳过未知原子（X元素）
            if atomsData[i].element == "X" {
                continue
            }
            
            // 确保原子实体存在
            guard let atom1 = atomEntityMap[i] else { continue }
            
            for j in (i+1)..<atomsData.count {
                // 同样跳过未知原子
                if atomsData[j].element == "X" {
                    continue
                }
                
                // 确保第二个原子实体存在
                guard let atom2 = atomEntityMap[j] else { continue }
                
                // 使用实体的当前位置计算距离，确保与视图一致
                let distance = length(atom1.position - atom2.position)
                if distance <= bondThreshold {
                    potentialBonds.append(AtomPair(atom1Index: i, atom2Index: j, distance: distance))
                }
            }
        }
        
        // 按距离排序（从短到长）
        potentialBonds.sort { $0.distance < $1.distance }
        
        // 创建键
        for pair in potentialBonds {
            let i = pair.atom1Index
            let j = pair.atom2Index
            
            if bondCount >= maxBonds { break }
            
            // 获取原子元素
            let element1 = atomsData[i].element
            let element2 = atomsData[j].element
            
            // 获取原子已有的键数
            let bondCount1 = atomBondCounts[i] ?? 0
            let bondCount2 = atomBondCounts[j] ?? 0
            
            // 检查原子是否已达到最大键数
            let maxBonds1 = getMaxBonds(forElement: element1)
            let maxBonds2 = getMaxBonds(forElement: element2)
            
            if bondCount1 >= maxBonds1 || bondCount2 >= maxBonds2 {
                continue // 如果任一原子已达到最大键数，则跳过
            }
            
            // 创建一个原子对的唯一标识，避免重复连接
            let pairKey = "\(min(i, j))-\(max(i, j))"
            
            // 如果尚未连接，则创建键
            if !connectedPairs.contains(pairKey) {
                connectedPairs.insert(pairKey)
                
                guard let atom1 = atomEntityMap[i], let atom2 = atomEntityMap[j] else { continue }
                
                let start = atom1.position
                let end = atom2.position
                let midpoint = (start + end) / 2
                let direction = normalize(end - start)
                let distance = length(end - start)
                
                // 使用圆柱体表示化学键
                let bondEntity = ModelEntity(
                    mesh: .generateCylinder(height: distance, radius: bondRadius),
                    materials: [SimpleMaterial(color: Constants.bondColor, roughness: 0.2, isMetallic: true)]
                )
                bondEntity.position = midpoint
                if abs(direction.y) > 0.99 {
                    bondEntity.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
                } else {
                    let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
                    let rotationAngle = acos(direction.y)
                    bondEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                }
                
                // 调整材质为稍微带一点金属感
                if var material = bondEntity.model?.materials.first as? SimpleMaterial {
                    material.metallic = .init(floatLiteral: 0.1) // 添加轻微金属感
                    bondEntity.model?.materials = [material]
                }
                
                bondsEntity.addChild(bondEntity)
                bondCount += 1
                
                // 更新原子的键数
                atomBondCounts[i] = bondCount1 + 1
                atomBondCounts[j] = bondCount2 + 1
            }
            
            // 每处理50个键暂停一下，避免UI冻结
            if bondCount % 50 == 0 && bondCount > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        }
        
        print("创建了\(bondCount)个化学键")
    }
    
    // 创建长距离化学键的帮助方法
    private func createLongRangeBonds() async {
        // 仅在球棍模型下启用
        guard displayMode == .ballAndStick else { return }
        
        // 清理现有键，重新创建
        bondsEntity.children.removeAll()
        
        let maxAtomsForBonds = atomsData.count
        let bondRadius: Float = Constants.bondRadius  // 使用标准半径
        
        // 使用更大的阈值捕获长距离键
        let longRangeBondThreshold: Float = 3.0  // 非常长的阈值
        let maxBonds = Constants.maxAtoms * 5
        var bondCount = 0
        
        // 创建一个词典来存储已经连接的原子对
        var connectedPairs = Set<String>()
        
        print("检测长距离化学键，阈值：\(longRangeBondThreshold)埃")
        
        // 为每种特定元素对创建专门的键
        // 检查特定类型的原子对
        for i in 0..<maxAtomsForBonds {
            let element1 = atomsData[i].element.uppercased()
            
            for j in (i+1)..<atomsData.count {
                if bondCount >= maxBonds { break }
                
                let element2 = atomsData[j].element.uppercased()
                let pairKey = "\(min(i, j))-\(max(i, j))"
                
                // 已连接的原子对跳过
                if connectedPairs.contains(pairKey) { continue }
                
                // 计算两原子间距离
                let distance = length(atomsData[i].position - atomsData[j].position)
                
                // 判断特定元素对是否应该形成键
                var shouldConnect = false
                
                // 氢键：氧-氢，氮-氢等
                if (element1 == "O" && element2 == "H" || element1 == "H" && element2 == "O") && distance <= 2.0 {
                    shouldConnect = true
                }
                // 氮-氢键
                else if (element1 == "N" && element2 == "H" || element1 == "H" && element2 == "N") && distance <= 2.0 {
                    shouldConnect = true
                }
                // 碳-碳键
                else if element1 == "C" && element2 == "C" && distance <= 1.8 {
                    shouldConnect = true
                }
                // 碳-氧键
                else if (element1 == "C" && element2 == "O" || element1 == "O" && element2 == "C") && distance <= 1.8 {
                    shouldConnect = true
                }
                // 碳-氮键
                else if (element1 == "C" && element2 == "N" || element1 == "N" && element2 == "C") && distance <= 1.8 {
                    shouldConnect = true
                }
                // 碳-硫键
                else if (element1 == "C" && element2 == "S" || element1 == "S" && element2 == "C") && distance <= 2.0 {
                    shouldConnect = true
                }
                // 其他常见键
                else if distance <= 1.5 { // 适用于常见共价键
                    shouldConnect = true
                }
                
                if shouldConnect {
                    connectedPairs.insert(pairKey)
                    
                    let start = atomsData[i].position
                    let end = atomsData[j].position
                    let midpoint = (start + end) / 2
                    let direction = normalize(end - start)
                    
                    // 创建键
                    let bondEntity = ModelEntity(
                        mesh: .generateCylinder(height: distance, radius: bondRadius),
                        materials: [SimpleMaterial(color: Constants.bondColor, roughness: 0.2, isMetallic: true)]
                    )
                    bondEntity.position = midpoint
                    
                    // 设置旋转
                    if abs(direction.y) > 0.99 {
                        bondEntity.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
                    } else {
                        let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
                        let rotationAngle = acos(direction.y)
                        bondEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
                    }
                    
                    bondsEntity.addChild(bondEntity)
                    bondCount += 1
                }
            }
        }
        
        print("创建了\(bondCount)个自定义化学键")
    }
    
    // MARK: - Display Mode Control
    func updateDisplayMode(_ mode: DisplayMode) async {
        let previousMode = displayMode
        displayMode = mode

        print("显示模式从\(previousMode)切换到\(mode)")

        // 先重置缩放，避免累积放大或缩小
        if let rootEntity = rootEntity {
            rootEntity.scale = [1.0, 1.0, 1.0]
            print("切换显示模式，重置rootEntity缩放")
        }

        // 如果从空间填充切换到其他模式，需要恢复原子原始位置
        if previousMode == .spaceFilling && (mode == .ballAndStick || mode == .proteinRibbon || mode == .proteinSurface) {
            print("从空间填充切换，恢复原子位置和材质")
            await restoreOriginalAtomPositions()
        }

        // 清除模式专属的子实体（比如球棍、飘带模型遗留的）
        clearDisplayModeSpecificEntities()

        // 保存已选中原子列表，以便在显示模式更新后恢复
        let savedSelectedAtoms = selectedAtoms

        // 针对不同显示模式，分别处理
        switch displayMode {
        case .spaceFilling:
            print("应用空间填充优化")
            await optimizeSpaceFillingPositions()
            adjustModelForVisibility()

        case .ballAndStick:
            print("创建球棍模型")
            bondsEntity.children.removeAll()
            bondsEntity.isEnabled = true
            await createChemicalBonds()

            // 若初次检测的键太少，再进行长距离检测
            if bondsEntity.children.count < atomsData.count / 2 {
                print("键数量较少，进行长距离键检测")
                await createLongRangeBonds()
            }

            showBonds = true
            bondsEntity.isEnabled = true

            // 更新原子显示
            updateAtomDisplay()

            adjustModelForVisibility()

        case .proteinRibbon:
            print("创建飘带模型")
            // 隐藏所有原子
            for (_, atomEntity) in atomEntityMap {
                atomEntity.isEnabled = false
            }

            // 创建飘带
            await createProteinRibbon()

            showBonds = false
            bondsEntity.isEnabled = false

            adjustModelForVisibility()

        case .proteinSurface:
            print("创建表面模型")
            
            // 隐藏所有原子，表面模型使用独立的实体显示
            for (_, atomEntity) in atomEntityMap {
                atomEntity.isEnabled = false
            }
            
            // 创建分子表面
            await createProteinSurface()
            
            // 表面模式下隐藏化学键
            showBonds = false
            bondsEntity.isEnabled = false
            
            adjustModelForVisibility()
        }

        // 更新原子样式（如需要）
        updateAtomDisplay()

        // 恢复选中原子的状态
        print("恢复\(savedSelectedAtoms.count)个已选中原子的状态")
        for index in savedSelectedAtoms {
            if let atomEntity = atomEntityMap[index] {
                // 确保原子在selectedAtoms集合中
                selectedAtoms.insert(index)
                
                // 应用选中材质
                let selectedMaterial = SimpleMaterial(
                    color: .green,
                    roughness: 0.1,
                    isMetallic: true
                )
                
                if let modelMesh = atomEntity.model?.mesh {
                    atomEntity.model = ModelComponent(mesh: modelMesh, materials: [selectedMaterial])
                    print("恢复原子\(index)的选中状态")
                    
                    // 如果在飘带模式，确保选中的原子可见
                    if displayMode == .proteinRibbon {
                        atomEntity.isEnabled = true
                        // 增加选中原子的大小以增强视觉效果
                        atomEntity.scale = [1.5, 1.5, 1.5]
                    }
                }
            }
        }

        // 最后通知UI刷新
        objectWillChange.send()
    }

    
    private func updateAtomDisplay() {
        // 在飘带模型和表面模型中隐藏所有原子
        if displayMode == .proteinRibbon || displayMode == .proteinSurface {
            for (_, atomEntity) in atomEntityMap {
                atomEntity.isEnabled = false
            }
            // 对于选中的原子，如果在飘带模式下，保持可见
            if displayMode == .proteinRibbon {
                for index in selectedAtoms {
                    if let atomEntity = atomEntityMap[index] {
                        atomEntity.isEnabled = true
                        atomEntity.scale = [1.5, 1.5, 1.5] // 增大选中原子的尺寸
                    }
                }
            }
            return
        }
        
        // 更新原子显示根据不同模式
        for (index, atomData) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] {
                // 确保原子可见（除了飘带模型和表面模型）
                atomEntity.isEnabled = true
                
                let element = atomData.element
                let baseRadius = Constants.atomRadii[element] ?? 0.25
                
                var scaleFactor: Float = 1.0
                var radiusMultiplier: Float = 1.0
                
                switch displayMode {
                case .ballAndStick:
                    scaleFactor = 2.0 // 从1.2增加到2.0，使球体更大，与标准球棍模型比例更加相符
                    radiusMultiplier = 1.0
                    
                    // 关键修改：确保不覆盖已选中原子的颜色
                    if !selectedAtoms.contains(index) {
                        let element = atomData.element
                        let color = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)

                        let material = SimpleMaterial(
                            color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)),
                            roughness: 0.3,
                            isMetallic: false
                        )

                        // 强制替换材质，确保刷新生效
                        if let model = atomEntity.model {
                            atomEntity.model = ModelComponent(mesh: model.mesh, materials: [material])
                        }
                    } else {
                        // 对于已选中的原子，确保它们保持绿色
                        print("保持原子\(index)的选中状态（绿色）")
                    }

                case .spaceFilling:
                    // 空间填充模型不在这里设置scale，交由optimizeSpaceFillingPositions处理
                    // 不做任何操作，让优化函数处理
                    continue
                
                case .proteinRibbon, .proteinSurface:
                    // 在飘带模型和表面模型中，已经在前面处理了
                    continue
                }
                
                // 应用缩放，但不改变已选中原子的大小
                if !selectedAtoms.contains(index) {
                    atomEntity.scale = [scaleFactor, scaleFactor, scaleFactor]
                } else {
                    // 选中原子使用更大的尺寸
                    atomEntity.scale = [scaleFactor * 1.2, scaleFactor * 1.2, scaleFactor * 1.2]
                }
                
                // 为空间填充模型应用更加紧凑的材质
                if displayMode == .spaceFilling && !selectedAtoms.contains(index) {
                    // 优化材质
                    let element = atomData.element
                    
                    // 创建新材质
                    var material = SimpleMaterial()
                    
                    // 使用基础颜色，不再依赖atomDistances
                    let baseColor = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                    
                    // 设置材质属性
                    material.roughness = .init(floatLiteral: 0.3) // 中等粗糙度
                    material.metallic = .init(floatLiteral: 0.1) // 低金属感
                    material.color = .init(tint: UIColor(red: CGFloat(baseColor.x),
                                                  green: CGFloat(baseColor.y),
                                                  blue: CGFloat(baseColor.z),
                                                  alpha: CGFloat(baseColor.w)))
                    
                    atomEntity.model?.materials = [material]
                }
            }
        }
        
        // 重新应用选中原子的颜色，确保它们不会被覆盖
        for index in selectedAtoms {
            if let atomEntity = atomEntityMap[index] {
                // 使用更鲜艳的绿色和更明显的材质效果
                let selectedMaterial = SimpleMaterial(
                    color: .green,
                    roughness: 0.1,
                    isMetallic: true
                )
                
                if let modelMesh = atomEntity.model?.mesh {
                    atomEntity.model = ModelComponent(mesh: modelMesh, materials: [selectedMaterial])
                    print("重新应用原子\(index)的绿色选中效果")
                }
            }
        }
        
        // 键的显示由模式控制
        bondsEntity.isEnabled = (displayMode == .ballAndStick && showBonds) || (displayMode == .proteinRibbon && showBonds)
        
        // 如果是空间填充模型，应用简化的深度着色
        if displayMode == .spaceFilling {
            applySimplifiedDepthShading()
        }
    }
    
    // 简化的深度着色方法，保持原子颜色不变但调整亮度
    private func applySimplifiedDepthShading() {
        // 找出所有原子的深度范围
        guard !atomsData.isEmpty else { return }
        
        // 计算相机位置
        let cameraPosition = SIMD3<Float>(0, 0, 10)
        
        // 计算每个原子到相机的距离
        var atomDistances: [(index: Int, distance: Float)] = []
        
        for (index, _) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] {
                let distance = length(atomEntity.position - cameraPosition)
                atomDistances.append((index: index, distance: distance))
            }
        }
        
        // 按距离排序
        atomDistances.sort { $0.distance < $1.distance }
        
        // 计算最近和最远距离
        guard let minDistance = atomDistances.first?.distance,
              let maxDistance = atomDistances.last?.distance else {
            return
        }
        
        let distanceRange = maxDistance - minDistance
        
        // 为每个原子基于深度应用简单的亮度调整
        for (index, distance) in atomDistances {
            if let atomEntity = atomEntityMap[index],
               var material = atomEntity.model?.materials.first as? SimpleMaterial {
                
                // 计算深度因子(0-1)，0表示最近，1表示最远
                let depthFactor = (distance - minDistance) / max(distanceRange, 0.001)
                
                // 仅轻微调整亮度，不改变色调
                let element = atomsData[index].element
                // 获取原始颜色
                var originalColor: SIMD4<Float>
                
                switch element {
                case "C":
                    // 保持碳原子的灰色
                    originalColor = SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
                case "H":
                    originalColor = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)
                case "O":
                    originalColor = SIMD4<Float>(1.0, 0.0, 0.0, 1.0)
                case "N":
                    originalColor = SIMD4<Float>(0.0, 0.0, 1.0, 1.0)
                case "S":
                    originalColor = SIMD4<Float>(1.0, 0.8, 0.0, 1.0)
                case "P":
                    originalColor = SIMD4<Float>(1.0, 0.5, 0.0, 1.0)
                default:
                    originalColor = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                }
                
                // 轻微减少远处原子的亮度
                let brightnessAdjustment = 1.0 - depthFactor * 0.25
                
                let finalColor = SIMD4<Float>(
                    originalColor.x * brightnessAdjustment,
                    originalColor.y * brightnessAdjustment,
                    originalColor.z * brightnessAdjustment,
                    1.0  // 保持完全不透明
                )
                
                material.color = .init(tint: UIColor(
                    red: CGFloat(finalColor.x),
                    green: CGFloat(finalColor.y),
                    blue: CGFloat(finalColor.z),
                    alpha: CGFloat(finalColor.w)))
                
                atomEntity.model?.materials = [material]
            }
        }
    }
    
    // MARK: - 以下是ContentView需要的方法
    
    // 切换键的显示
    func toggleBonds() {
        // 在飘带模型下，不允许显示键
        if displayMode == .proteinRibbon {
            showBonds = false
            bondsEntity.isEnabled = false
            print("飘带模型：已禁用键显示")
            objectWillChange.send()
            return
        }
        
        showBonds.toggle()
        
        // 在球棍模型下，不允许隐藏键
        if displayMode == .ballAndStick {
            showBonds = true
            bondsEntity.isEnabled = true
            print("球棍模型：键显示已强制启用")
        } else {
            bondsEntity.isEnabled = showBonds && (displayMode == .proteinRibbon)
        }
        
        objectWillChange.send()
    }
    
    // 测量相关函数
    func addMeasurementPoint(_ atomIndex: Int) {
        print("==== 添加测量点 ==== : 索引=\(atomIndex)，当前测量点数=\(measurementPoints.count)")
        
        // 验证原子是否存在
        guard let atom = atomEntityMap[atomIndex] else {
            print("错误：无法找到索引为\(atomIndex)的原子实体")
            return
        }
        
        // 如果已有两个点，清除现有测量
        if measurementPoints.count >= 2 {
            print("已有两个测量点，清除现有测量")
            clearMeasurement()
        }
        
        // 添加测量点
        measurementPoints.append(atomIndex)
        print("添加测量点成功，当前测量点列表：\(measurementPoints)")
        
        // 应用特殊高亮颜色
        if let atomEntity = atomEntityMap[atomIndex] as? ModelEntity {
            // 应用鲜明的蓝色高亮
            let highlightMaterial = SimpleMaterial(
                color: .cyan,
                roughness: 0.1, 
                isMetallic: true
            )
            
            if let modelMesh = atomEntity.model?.mesh {
                atomEntity.model = ModelComponent(mesh: modelMesh, materials: [highlightMaterial])
                print("已为原子\(atomIndex)应用高亮颜色")
            }
        }
        
        // 当有两个点时创建测量线
        if measurementPoints.count == 2 {
            print("已有两个测量点，准备创建测量线")
            createMeasurementLineWithDebug()
        }
        
        // 确保界面更新
        objectWillChange.send()
    }
    
    // 新的測量線创建方法，带有全面的调试输出
    private func createMeasurementLineWithDebug() {
        print("\n=========== 創建測量線開始 ===========")
        
        // 1. 确保有两个测量点
        guard measurementPoints.count == 2 else {
            print("错误：测量点数量不足，无法创建测量线")
            return
        }
        
        let point1 = measurementPoints[0]
        let point2 = measurementPoints[1]
        print("测量点对：\(point1)和\(point2)")
        
        // 2. 获取原子实体
        guard let atom1 = atomEntityMap[point1],
              let atom2 = atomEntityMap[point2] else {
            print("错误：无法找到原子实体，atom1存在=\(atomEntityMap[point1] != nil)，atom2存在=\(atomEntityMap[point2] != nil)")
            return
        }
        
        print("原子实体获取成功")
        
        // 3. 计算位置和距离
        let start = atom1.position
        let end = atom2.position
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        
        print("位置计算结果：起点=\(start)，终点=\(end)，中点=\(midpoint)，方向=\(direction)，距离=\(distance)")
        
        // 4. 清除现有测量线
        print("清除现有测量线，数量=\(measurementLines.count)")
        for line in measurementLines {
            line.removeFromParent()
        }
        measurementLines.removeAll()
        
        // 5. 创建和添加线条
        print("开始创建测量线元素")
        
        // 创建一个超大尺寸的线条，确保可见
        let lineRadius: Float = 0.05 // 使用绝对值而非相对值
        let line = ModelEntity(mesh: .generateCylinder(height: distance, radius: lineRadius))
        line.position = midpoint
        print("主线创建成功，位置=\(midpoint)，半径=\(lineRadius)，高度=\(distance)")
        
        // 设置旋转
        if abs(direction.y) > 0.99 {
            line.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
            print("线条使用Y轴特殊旋转")
        } else {
            let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
            let rotationAngle = acos(direction.y)
            line.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
            print("线条使用标准旋转，轴=\(rotationAxis)，角度=\(rotationAngle)")
        }
        
        // 创建明亮的材质
        let material = SimpleMaterial(
            color: .red, 
            roughness: 0.0,
            isMetallic: false
        )
        line.model?.materials = [material]
        print("线条材质应用完成，颜色=红色")
        
        // 6. 创建球体端点
        let sphereRadius: Float = 0.08 // 使用绝对值
        
        let startSphere = ModelEntity(mesh: .generateSphere(radius: sphereRadius))
        startSphere.position = start
        startSphere.model?.materials = [material]
        print("起点球体创建完成，位置=\(start)，半径=\(sphereRadius)")
        
        let endSphere = ModelEntity(mesh: .generateSphere(radius: sphereRadius))
        endSphere.position = end
        endSphere.model?.materials = [material]
        print("终点球体创建完成，位置=\(end)，半径=\(sphereRadius)")
        
        // 7. 创建距离标签
        let distanceText = "\(String(format: "%.2f", distance))Å"
        print("创建距离标签，文本=\(distanceText)")
        
        // 定义标签位置 - 确保在视野中
        let labelPos = midpoint + SIMD3<Float>(0, 0.15, 0)
        
        // 创建大尺寸文本
        let textMesh = MeshResource.generateText(
            distanceText,
            extrusionDepth: 0.01, // 显著增加厚度
            font: .boldSystemFont(ofSize: 0.2), // 使用粗体大字号
            containerFrame: CGRect(x: -0.5, y: -0.1, width: 1.0, height: 0.3),
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        let textEntity = ModelEntity(mesh: textMesh)
        textEntity.position = labelPos
        
        // 使用黄色材质，更容易看见
        let textMaterial = SimpleMaterial(
            color: .yellow,
            roughness: 0.0,
            isMetallic: false
        )
        textEntity.model?.materials = [textMaterial]
        print("距离标签创建完成，位置=\(labelPos)")
        
        // 8. 添加所有元素到场景
        print("添加所有元素到场景")
        
        // 检查根实体是否存在
        guard let root = rootEntity else {
            print("严重错误：根实体不存在，无法添加测量线")
            return
        }
        
        // 先将元素添加到数组
        measurementLines.append(line)
        measurementLines.append(startSphere)
        measurementLines.append(endSphere)
        measurementLines.append(textEntity)
        
        // 再添加到场景层次结构
        root.addChild(line)
        root.addChild(startSphere)
        root.addChild(endSphere)
        root.addChild(textEntity)
        
        print("所有元素已添加到场景和数组中，当前测量线数组大小=\(measurementLines.count)")
        
        // 9. 强制刷新
        objectWillChange.send()
        print("发送更新通知")
        
        print("============ 創建測量線完成 ===========\n")
    }
    
    // 清除测量
    func clearMeasurement() {
        print("清除所有测量线和测量点")
        
        // 恢复所有测量点原子的原始颜色
        for index in measurementPoints {
            if let atomEntity = atomEntityMap[index] {
                // 恢复原始颜色
                let element = atomsData[index].element
                let colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                
                let originalMaterial = SimpleMaterial(
                    color: UIColor(red: CGFloat(colorRGBA.x),
                                  green: CGFloat(colorRGBA.y),
                                  blue: CGFloat(colorRGBA.z),
                                  alpha: CGFloat(colorRGBA.w)),
                    roughness: 0.3,
                    isMetallic: false
                )
                
                if let modelMesh = atomEntity.model?.mesh {
                    atomEntity.model = ModelComponent(mesh: modelMesh, materials: [originalMaterial])
                }
                
                print("已恢复原子\(index)的原始颜色")
            }
        }
        
        // 移除测量点列表
        measurementPoints.removeAll()
        
        // 移除所有测量线
        print("移除\(measurementLines.count)个测量线元素")
        for line in measurementLines {
            line.removeFromParent()
        }
        measurementLines.removeAll()
        
        // 通知变更
        objectWillChange.send()
    }
    
    func getDistance() -> Float? {
        guard measurementPoints.count == 2,
              let atom1 = atomEntityMap[measurementPoints[0]],
              let atom2 = atomEntityMap[measurementPoints[1]] else {
            return nil
        }
        
        return length(atom1.position - atom2.position)
    }
    
    private func createMeasurementLine() {
        guard measurementPoints.count == 2,
              let atom1 = atomEntityMap[measurementPoints[0]],
              let atom2 = atomEntityMap[measurementPoints[1]] else {
            return
        }
        
        let start = atom1.position
        let end = atom2.position
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        
        // 使用更粗的线条 - 增加线条半径
        let lineRadius = Constants.measurementLineRadius * 2.0
        
        // 创建主线条 - 使用鲜明的红色
        let line = ModelEntity(mesh: .generateCylinder(height: distance, radius: lineRadius))
        line.position = midpoint
        
        // 设置旋转
        if abs(direction.y) > 0.99 {
            line.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
        } else {
            let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
            let rotationAngle = acos(direction.y)
            line.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
        }
        
        // 设置红色材质，更加鲜明
        var material = SimpleMaterial()
        material.color = .init(tint: .red)
        material.roughness = .init(floatLiteral: 0.1)
        material.metallic = .init(floatLiteral: 0.5)
        line.model?.materials = [material]
        
        // 在两端添加小球体，增强视觉效果
        let endpointRadius = lineRadius * 1.5
        
        // 起点球体
        let startSphere = ModelEntity(mesh: .generateSphere(radius: endpointRadius))
        startSphere.position = start
        startSphere.model?.materials = [material]
        
        // 终点球体
        let endSphere = ModelEntity(mesh: .generateSphere(radius: endpointRadius))
        endSphere.position = end
        endSphere.model?.materials = [material]
        
        // 添加所有视觉元素
        measurementLines.append(line)
        measurementLines.append(startSphere)
        measurementLines.append(endSphere)
        
        rootEntity?.addChild(line)
        rootEntity?.addChild(startSphere)
        rootEntity?.addChild(endSphere)
        
        // 创建中点标记 - 可选
        if distance > 0.5 {
            let midSphere = ModelEntity(mesh: .generateSphere(radius: endpointRadius * 0.7))
            midSphere.position = midpoint
            midSphere.model?.materials = [material]
            measurementLines.append(midSphere)
            rootEntity?.addChild(midSphere)
        }
        
        print("创建测量线，连接原子 \(measurementPoints[0]) 和 \(measurementPoints[1])，距离: \(distance)")
    }
    
    // 原子选择相关函数
    func selectAtom(at index: Int) {
        guard let atomEntity = atomEntityMap[index] else { 
            print("selectAtom: 未找到索引为\(index)的原子实体")
            return 
        }

        print("selectAtom: 处理索引为\(index)的原子选择")

        if selectedAtoms.contains(index) {
            // 取消选中
            selectedAtoms.remove(index)
            print("取消选择原子\(index)")
            
            // 仅在取消选择时恢复原始颜色
            let element = atomsData[index].element
            let color = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
            let originalMaterial = SimpleMaterial(
                color: UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)),
                roughness: 0.3,
                isMetallic: false
            )

            if let modelMesh = atomEntity.model?.mesh {
                atomEntity.model = ModelComponent(mesh: modelMesh, materials: [originalMaterial])
                print("已恢复原子\(index)的原始颜色")
            } else {
                print("错误：无法获取原子\(index)的网格数据")
            }
        } else {
            // 选中原子但不改变颜色
            selectedAtoms.insert(index)
            print("选择原子\(index)，保持当前颜色不变")
            
            // 不再自动将原子变为绿色或橙色
            // 仅添加一个高光效果表示被选中，但保持当前颜色
            if let modelMesh = atomEntity.model?.mesh, let currentMaterial = atomEntity.model?.materials.first as? SimpleMaterial {
                // 创建新材质，但保持当前颜色，只调整光泽和金属感
                var selectedMaterial = currentMaterial
                selectedMaterial.roughness = 0.1  // 更光滑
                selectedMaterial.metallic = 0.8   // 更有金属感，以便区分
                
                atomEntity.model = ModelComponent(mesh: modelMesh, materials: [selectedMaterial])
                print("已为原子\(index)添加选中状态高光效果，保持颜色不变")
            }
        }
        
        // 更新选中状态但不更改颜色
        updateSelectedAtomVisuallyWithoutChangingColor(at: index)

        // 强制更新UI
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    // 新方法：更新选中原子的视觉效果，但不更改颜色
    private func updateSelectedAtomVisuallyWithoutChangingColor(at index: Int) {
        guard let atomEntity = atomEntityMap[index] else { return }
        
        // 确保原子可见
        atomEntity.isEnabled = true
        
        if selectedAtoms.contains(index) {
            // 如果已选中，只提高光泽度和金属感，不改变颜色
            if let modelMesh = atomEntity.model?.mesh, let currentMaterial = atomEntity.model?.materials.first as? SimpleMaterial {
                var material = currentMaterial
                material.roughness = 0.1
                material.metallic = 0.8
                
                atomEntity.model = ModelComponent(mesh: modelMesh, materials: [material])
                print("已更新原子\(index)的选中状态，保持颜色不变")
            }
        } else {
            // 恢复原始材质属性，但保持当前颜色
            if let modelMesh = atomEntity.model?.mesh, let currentMaterial = atomEntity.model?.materials.first as? SimpleMaterial {
                var material = currentMaterial
                material.roughness = 0.3
                material.metallic = 0.0
                
                atomEntity.model = ModelComponent(mesh: modelMesh, materials: [material])
                print("已恢复原子\(index)的原始材质属性，保持颜色不变")
            }
        }
    }
    
    private func updateAtomSelection() {
        for (index, atomData) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] {
                let element = atomData.element
                if let modelComponent = atomEntity.model {
                    var material = modelComponent.materials.first as? SimpleMaterial ?? SimpleMaterial()
                    
                    if selectedAtoms.contains(index) {
                        // 选中的原子显示为黄色
                        material.color = .init(tint: .yellow)
                    } else {
                        // 恢复原来的颜色
                        let colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                        material.color = .init(tint: UIColor(red: CGFloat(colorRGBA.x),
                                                             green: CGFloat(colorRGBA.y),
                                                             blue: CGFloat(colorRGBA.z),
                                                             alpha: CGFloat(colorRGBA.w)))
                    }
                    
                    atomEntity.model?.materials = [material]
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func centerModel() {
        guard !atomsData.isEmpty else { return }
        
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        
        for atom in atomsData {
            let position = atom.position
            minBounds = min(minBounds, position)
            maxBounds = max(maxBounds, position)
        }
        
        let center = (minBounds + maxBounds) * 0.5
        let size = maxBounds - minBounds
        let maxExtent = max(size.x, size.y, size.z)
        
        // ✅ 让模型默认尺寸适应 RealityView 空间
        let idealModelSize: Float = 0.6 // 适应窗口默认大小
        let scaleFactor = idealModelSize / maxExtent
        
        atomsEntity.position = -center * scaleFactor
        atomsEntity.scale = SIMD3<Float>(repeating: scaleFactor)
        
        bondsEntity.position = -center * scaleFactor
        bondsEntity.scale = SIMD3<Float>(repeating: scaleFactor)
    }
    
    private func clearCurrentModel() {
        atomsEntity.children.removeAll()
        bondsEntity.children.removeAll()
        atomsData.removeAll()
        selectedAtoms.removeAll()
        atomEntityMap.removeAll()
        clearMeasurement()
    }
    
    // MARK: - Data Types
    struct PDBAtom {
        let element: String
        let x: Float
        let y: Float
        let z: Float
        let atomName: String     // 原子名称（如CA、N、C、O等）
        let residueName: String  // 残基名称（如ALA、GLY等）
        let residueNumber: Int   // 残基编号
        let chainID: String      // 链ID
    }
    
    // 存储PDB原子信息的数组，与atomsData一一对应
    private var pdbAtomsData: [PDBAtom] = []
    
    // MARK: - File Parsing
    private func parsePDBFile(_ pdbData: String) throws -> [PDBAtom] {
        var atoms: [PDBAtom] = []
        var elementCounts: [String: Int] = [:] // 用于记录每种元素的原子数量
        var oxygenTypes: [String: Int] = [:] // 专门跟踪不同类型的氧原子
        var unknownElementCount = 0 // 跟踪未知元素(X)的数量
        
        
        // 用于检测氧原子坐标重复
        var oxygenCoordinates: [(Float, Float, Float)] = []
        var duplicateOxygenCount = 0
        
        // 用于收集残基信息
        var residueSet = Set<String>() // 存储唯一的残基名称
        var residueCountMap: [String: Int] = [:] // 存储每种残基的数量
        var chainResidues: [String: Set<Int>] = [:] // 存储每个链的残基编号，用于计算每条链的残基数量
        
        let lines = pdbData.components(separatedBy: .newlines)
        print("PDB文件共有\(lines.count)行")
        
        for line in lines {
            if line.hasPrefix("ATOM") || line.hasPrefix("HETATM") {
                if line.count >= 54 {
                    // 严格按照PDB标准格式解析
                    // 元素符号在第77-78列
                    let elementField: String
                    if line.count >= 78 {
                        elementField = String(line[76...77]).trimmingCharacters(in: .whitespaces)
                    } else {
                        elementField = ""
                    }
                    
                    // 原子名称在第13-16列
                    let nameField: String
                    if line.count >= 16 {
                        nameField = String(line[12...15]).trimmingCharacters(in: .whitespaces)
                    } else {
                        nameField = ""
                    }
                    
                    // 残基名称在第18-20列
                    let residueName: String
                    if line.count >= 20 {
                        residueName = String(line[17...19]).trimmingCharacters(in: .whitespaces)
                    } else {
                        residueName = "UNK"
                    }
                    
                    // 链ID在第22列
                    let chainID: String
                    if line.count >= 22 {
                        chainID = String(line[21...21])
                    } else {
                        chainID = "A"
                    }
                    
                    // 残基编号在第23-26列
                    let residueNumber: Int
                    if line.count >= 26 {
                        let residueNumberStr = String(line[22...25]).trimmingCharacters(in: .whitespaces)
                        residueNumber = Int(residueNumberStr) ?? 0
                    } else {
                        residueNumber = 0
                    }
                    
                    // 收集残基信息
                    residueSet.insert(residueName)
                    residueCountMap[residueName, default: 0] += 1
                    
                    // 收集每条链的残基编号
                    if chainResidues[chainID] == nil {
                        chainResidues[chainID] = []
                    }
                    chainResidues[chainID]?.insert(residueNumber)
                    
                    // 确定元素
                    var element = ""
                    
                    // 首先使用元素字段
                    if !elementField.isEmpty {
                        element = elementField
                    }
                    // 如果元素字段为空，从原子名称推断
                    else if !nameField.isEmpty {
                        // 对于标准氨基酸原子，第一个字符通常是元素符号
                        let firstChar = String(nameField.prefix(1))
                        
                        // 跟踪调试氧原子类型
                        if nameField.hasPrefix("O") {
                            oxygenTypes[nameField, default: 0] += 1
                            element = "O" // 只使用O作为氧的元素标识
                        }
                        // 对于氢原子，名称可能以H开头或有特殊格式
                        else if nameField.hasPrefix("H") || nameField.contains("H") {
                            element = "H"
                        }
                        // 对于碳原子
                        else if nameField.hasPrefix("C") {
                            element = "C"
                        }
                        // 对于氮原子
                        else if nameField.hasPrefix("N") {
                            element = "N"
                        }
                        // 对于硫原子
                        else if nameField.hasPrefix("S") {
                            element = "S"
                        }
                        // 对于磷原子
                        else if nameField.hasPrefix("P") {
                            element = "P"
                        }
                        // 对于其它可能的双字母元素（如FE, ZN等）
                        else if nameField.count >= 2 {
                            // 提取前两个字母并检查是否是有效元素
                            let possibleElement = String(nameField.prefix(2))
                            if Constants.atomColors[possibleElement.uppercased()] != nil {
                                element = possibleElement
                            } else {
                                // 如果不是已知元素，使用第一个字符
                                element = firstChar
                            }
                        } else {
                            element = firstChar
                        }
                    }
                    
                    // 确保元素名不为空
                    guard !element.isEmpty else {
                        print("忽略无元素信息的原子: \(nameField)")
                        continue
                    }
                    
                    // 如果是未知元素，标记为X但保留在数据中以供参考
                    if Constants.atomColors[element.uppercased()] == nil {
                        print("检测到未知元素: \(element)，设置为X")
                        element = "X"
                        unknownElementCount += 1
                    }
                    
                    // 标准化元素名（首字母大写）
                    element = element.capitalized
                    
                    // 解析坐标
                    if let x = Float(line[30...38].trimmingCharacters(in: .whitespaces)),
                       let y = Float(line[38...46].trimmingCharacters(in: .whitespaces)),
                       let z = Float(line[46...54].trimmingCharacters(in: .whitespaces)) {
                        
                        // 检查氧原子的坐标是否重复
                        if element == "O" {
                            let coord = (x, y, z)
                            if oxygenCoordinates.contains(where: {
                                abs($0.0 - coord.0) < 0.001 &&
                                abs($0.1 - coord.1) < 0.001 &&
                                abs($0.2 - coord.2) < 0.001
                            }) {
                                duplicateOxygenCount += 1
                                continue // 跳过重复的氧原子
                            } else {
                                oxygenCoordinates.append(coord)
                            }
                        }
                        
                        let atom = PDBAtom(
                            element: element, 
                            x: x / 10, 
                            y: y / 10, 
                            z: z / 10,
                            atomName: nameField,
                            residueName: residueName,
                            residueNumber: residueNumber,
                            chainID: chainID
                        )
                        
                        atoms.append(atom)
                        
                        // 更新元素计数
                        elementCounts[element, default: 0] += 1
                    }
                }
            }
        }
        
        // 打印元素统计信息
        print("PDB元素统计:")
        for (element, count) in elementCounts.sorted(by: { $0.value > $1.value }) {
            print("  \(element): \(count)个原子")
        }
        if unknownElementCount > 0 {
            print("发现\(unknownElementCount)个未知元素原子，已标记为X")
        }
        
        // 打印残基统计信息
        print("\n残基统计:")
        print("总共检测到\(residueSet.count)种残基类型")
        
        // 按字母顺序排序残基并打印数量
        print("每种残基的数量:")
        for (residue, count) in residueCountMap.sorted(by: { $0.key < $1.key }) {
            print("  \(residue): \(count)个")
        }
        
        // 打印每条链的残基数量
        print("\n链统计:")
        for (chain, residues) in chainResidues.sorted(by: { $0.key < $1.key }) {
            print("  链\(chain): 包含\(residues.count)个残基")
        }
        
        // 按照残基类型进行分类统计
        let hydrophobicResidues = ["ALA", "LEU", "VAL", "ILE", "MET", "PRO", "GLY"]
        let polarResidues = ["SER", "THR", "ASN", "GLN", "CYS"]
        let acidicResidues = ["ASP", "GLU"]
        let basicResidues = ["LYS", "ARG", "HIS"]
        let aromaticResidues = ["PHE", "TYR", "TRP"]
        
        var hydrophobicCount = 0
        var polarCount = 0
        var acidicCount = 0
        var basicCount = 0
        var aromaticCount = 0
        var otherCount = 0
        
        for (residue, count) in residueCountMap {
            if hydrophobicResidues.contains(residue) {
                hydrophobicCount += count
            } else if polarResidues.contains(residue) {
                polarCount += count
            } else if acidicResidues.contains(residue) {
                acidicCount += count
            } else if basicResidues.contains(residue) {
                basicCount += count
            } else if aromaticResidues.contains(residue) {
                aromaticCount += count
            } else {
                otherCount += count
            }
        }
        
        print("\n残基类型分布:")
        print("  疏水性残基: \(hydrophobicCount)个")
        print("  极性不带电残基: \(polarCount)个")
        print("  带负电(酸性)残基: \(acidicCount)个")
        print("  带正电(碱性)残基: \(basicCount)个")
        print("  芳香族残基: \(aromaticCount)个")
        print("  其他残基: \(otherCount)个")
        
        // 保存PDB原子信息
        pdbAtomsData = atoms
        
        return atoms
    }
    
    private func createSimplifiedAtomSphere(radius: Float, color: UIColor) -> ModelEntity {
        let sphere = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [SimpleMaterial(color: color, isMetallic: false)]
        )
        return sphere
    }
    
    private func createBond(from atom1: ModelEntity, to atom2: ModelEntity, radius: Float) -> ModelEntity? {
        guard atom1 != atom2 else { return nil }
        
        let start = atom1.position
        let end = atom2.position
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let bondLength = length(end - start)
        
        // 创建一个圆柱体表示化学键，增加细分度
        let bondEntity = ModelEntity(
            mesh: .generateCylinder(height: bondLength, radius: radius * 0.8), // 使用更小的半径
            materials: [SimpleMaterial(color: Constants.bondColor, roughness: 0.2, isMetallic: true)]
        )
        bondEntity.position = midpoint
        
        // 设置旋转
        if abs(direction.y) > 0.99 {
            bondEntity.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
        } else {
            let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
            let rotationAngle = acos(direction.y)
            bondEntity.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
        }
        
        return bondEntity
    }
    
    // MARK: - Metal渲染
    
    /// 使用Metal进行渲染的方法
    func renderWithMetal(drawable: CAMetalDrawable, renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let commandQueue = metalCommandQueue,
              let pipelineState = pipelineState else {
            print("渲染错误: Metal渲染资源未初始化")
            return
        }
        
        // 创建命令缓冲区
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        // 创建渲染命令编码器
        guard let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("无法创建渲染命令编码器")
            return
        }
        
        // 设置渲染管线状态
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // TODO: 在这里设置顶点和片段着色器所需的缓冲区、纹理和其他资源
        // 例如: renderEncoder.setVertexBuffer(vertices, offset: 0, index: ShaderTypes.BufferIndex.meshPositions.rawValue)
        
        // 使用UniformsArray结构体来设置变换矩阵等数据
        var uniformsArray = ShaderTypes.UniformsArray()
        let projectionMatrix = simd_float4x4(1.0) // 示例值，需根据实际情况设置
        let viewMatrix = simd_float4x4(1.0) // 示例值，需根据实际情况设置
        let modelMatrix = simd_float4x4(1.0) // 示例值，需根据实际情况设置
        
        uniformsArray.uniforms[0].projectionMatrix = projectionMatrix
        uniformsArray.uniforms[0].modelViewMatrix = viewMatrix * modelMatrix
        
        // 为着色器设置统一变量
        renderEncoder.setVertexBytes(&uniformsArray, length: MemoryLayout<ShaderTypes.UniformsArray>.size, index: ShaderTypes.BufferIndex.uniforms.rawValue)
        
        // TODO: 绘制几何体
        // 例如: renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        
        // 完成渲染命令编码
        renderEncoder.endEncoding()
        
        // 提交绘制命令到当前可绘制对象
        commandBuffer?.present(drawable)
        
        // 提交命令缓冲区
        commandBuffer?.commit()
    }
    
    // MARK: - RealityView相关
    func setupRealityView(content: RealityViewContent) {
        print("设置RealityView内容")
        
        // 清理之前的内容
        content.entities.removeAll()
        
        // 确保rootEntity存在
        if rootEntity == nil {
            setupScene()
        }
        
        if let rootEntity = rootEntity {
            // 为蛋白质模型添加手势交互能力
            // 在visionOS中使用正确的组件
            rootEntity.components[InputTargetComponent.self] = InputTargetComponent()
            rootEntity.components[CollisionComponent.self] = CollisionComponent(
                shapes: [.generateBox(size: [1, 1, 1])],
                mode: .trigger,
                filter: .sensor
            )
            
            // 将模型初始位置调整到可见的距离
            rootEntity.position = [0, 0, -1.0]
            
            // 如果模型已加载，则应用自适应调整
            if !atomsData.isEmpty {
                adjustModelForVisibility()
                print("已应用自适应屏幕调整")
            }
            
            // 添加到RealityView内容
            content.add(rootEntity)
            print("已将rootEntity添加到RealityView内容")
        }
    }
    
    // 根据实体获取对应的原子索引
    func getEntityAtomIndex(_ entity: ModelEntity) -> Int? {
        print("尝试识别点击的原子实体")
        
        // 首先检查直接引用匹配
        for (index, modelEntity) in atomEntityMap {
            if entity === modelEntity {
                print("找到精确匹配的原子索引: \(index)")
                return index
            }
        }
        
        // 如果没有直接匹配，尝试通过位置进行匹配
        let clickedPosition = entity.position
        
        // 找出最接近的原子
        var closestIndex: Int? = nil
        var closestDistance: Float = Float.greatestFiniteMagnitude
        
        for (index, modelEntity) in atomEntityMap {
            let distance = length(modelEntity.position - clickedPosition)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        // 如果最近距离小于阈值，认为是同一原子
        let distanceThreshold: Float = 0.1
        if let foundIndex = closestIndex, closestDistance < distanceThreshold {
            print("通过位置找到最接近的原子索引: \(foundIndex), 距离: \(closestDistance)")
            return foundIndex
        }
        
        // 如果找不到匹配的原子，查看点击实体的父级
        if let parent = entity.parent {
            if let parentEntity = parent as? ModelEntity {
                print("尝试查找父实体的原子索引")
                return getEntityAtomIndex(parentEntity)
            }
        }
        
        print("无法识别点击的原子实体")
        return nil
    }
    
    // MARK: - 公共访问方法 - 供BillboardRenderer使用
    func getAtomsData() -> [AtomData] {
        return atomsData
    }
    
    func getAtomEntity(at index: Int) -> ModelEntity? {
        return atomEntityMap[index]
    }
    
    func getDisplayMode() -> DisplayMode {
        return displayMode
    }
    
    // 根据元素获取原子半径
    private func getAtomRadius(for element: String) -> Float {
        // 使用ProteinViewer内部的Constants
        let uppercaseElement = element.uppercased()
        return Constants.vanDerWaalsRadii[uppercaseElement] ?? 0.04  // 默认半径为0.04
    }
    
    func getAtomColor(for element: String) -> SIMD4<Float> {
        return Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
    }
    
    // MARK: - Billboard渲染相关
    
    // 增强空间填充模型的颜色
    private func enhanceSpaceFillingColors() {
        for (index, atomData) in atomsData.enumerated() {
            if let atomEntity = atomEntityMap[index] {
                let element = atomData.element
                var material = SimpleMaterial()
                
                // 获取基础颜色
                var baseColor = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.2, 0.8, 1.0)
                
                // 增强颜色
                var enhancedColor = baseColor
                
                // 根据元素应用特定增强
                switch element {
                case "C":
                    enhancedColor = SIMD4<Float>(0.75, 0.75, 0.75, 1.0) // 碳原子灰色
                case "H":
                    enhancedColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0) // 氢原子亮白色
                case "O":
                    enhancedColor = SIMD4<Float>(1.0, 0.1, 0.1, 1.0) // 氧原子鲜红色
                case "N":
                    enhancedColor = SIMD4<Float>(0.1, 0.1, 1.0, 1.0) // 氮原子鲜蓝色
                case "S":
                    enhancedColor = SIMD4<Float>(1.0, 0.9, 0.0, 1.0) // 硫原子鲜黄色
                case "P":
                    enhancedColor = SIMD4<Float>(1.0, 0.4, 0.0, 1.0) // 磷原子橙色
                default:
                    // 对其他元素增强饱和度和亮度
                    let brightnessBoost: Float = 1.3
                    enhancedColor.x = min(1.0, enhancedColor.x * brightnessBoost)
                    enhancedColor.y = min(1.0, enhancedColor.y * brightnessBoost)
                    enhancedColor.z = min(1.0, enhancedColor.z * brightnessBoost)
                }
                
                // 应用增强的颜色
                material.color = .init(tint: UIColor(
                    red: CGFloat(enhancedColor.x),
                    green: CGFloat(enhancedColor.y),
                    blue: CGFloat(enhancedColor.z),
                    alpha: CGFloat(enhancedColor.w)))
                
                // 设置材质属性
                material.roughness = .init(floatLiteral: 0.3) // 更光滑
                material.metallic = .init(floatLiteral: 0.15) // 适度金属感
                
                atomEntity.model?.materials = [material]
            }
        }
    }
    
    // MARK: - 蛋白质飘带模型相关
    // 用于存储蛋白质飘带模型的数据结构
    struct RibbonChain {
        var alphaCarbon: [SIMD3<Float>] // Cα原子的坐标
        var residueNumbers: [Int]       // 残基编号
        var residueNames: [String]      // 残基名称
        var chainID: String             // 链ID
        var secondaryStructures: [SecondaryStructure] // 每个残基的二级结构类型
    }
    
    // 用于分段处理飘带的数据结构
    private struct RibbonSegment {
        var points: [SIMD3<Float>]       // 曲线点
        var normals: [SIMD3<Float>]      // 法线
        var structure: SecondaryStructure // 二级结构类型
    }
    
    // 创建蛋白质飘带模型
    private func createProteinRibbon() async {
        print("开始创建蛋白质飘带模型")
        
        // 提取每条链的Cα原子
        let chains = extractChains()
        
        if chains.isEmpty {
            print("未找到有效的蛋白质链，尝试创建基于所有碳原子的简单飘带模型")
            
            // 创建一个基于所有碳原子的简单飘带模型
            await createSimpleRibbonFromCarbonAtoms()
            return
        }
        
        print("找到\(chains.count)条蛋白质链")
        
        // 隐藏所有原子
        for (_, atomEntity) in atomEntityMap {
            atomEntity.isEnabled = false
        }
        
        // 为每条链创建飘带
        for (chainIndex, chain) in chains.enumerated() {
            if chain.alphaCarbon.count >= 2 {
                // 计算平滑曲线
                let (curvePoints, normals, secondaryStructures) = generateSmoothCurve(chain.alphaCarbon, chain.secondaryStructures)
                
                // 创建飘带几何体
                if let ribbonEntity = createRibbonGeometry(
                    curvePoints: curvePoints,
                    normals: normals,
                    secondaryStructures: secondaryStructures,
                    chainIndex: chainIndex
                ) {
                    // 添加到场景
                    atomsEntity.addChild(ribbonEntity)
                    
                    print("创建了链\(chain.chainID)的飘带，包含\(chain.alphaCarbon.count)个Cα原子")
                    
                    // 每条链处理后暂停一下
                    try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                }
            }
        }
        
        print("蛋白质飘带模型创建完成")
    }
    
    // 创建基于所有碳原子的简单飘带模型
    private func createSimpleRibbonFromCarbonAtoms() async {
        // 收集所有碳原子
        var carbonAtoms: [SIMD3<Float>] = []
        var carbonIndices: [Int] = []
        
        for (index, atom) in atomsData.enumerated() {
            if atom.element.uppercased() == "C" {
                carbonAtoms.append(atom.position)
                carbonIndices.append(index)
            }
        }
        
        // 如果碳原子太少，无法创建飘带
        if carbonAtoms.count < 2 {
            print("碳原子数量不足，无法创建飘带模型")
            return
        }
        
        print("找到\(carbonAtoms.count)个碳原子，创建简单飘带模型")
        
        // 隐藏所有原子
        for (_, atomEntity) in atomEntityMap {
            atomEntity.isEnabled = false
        }
        
        // 对碳原子进行排序，使相邻原子在空间上尽可能靠近
        // 使用贪心算法构建路径
        var sortedAtoms: [SIMD3<Float>] = [carbonAtoms[0]]
        var sortedIndices: [Int] = [carbonIndices[0]]
        var remainingIndices = Set(carbonIndices[1...])
        
        while !remainingIndices.isEmpty {
            let lastPos = sortedAtoms.last!
            var minDist = Float.greatestFiniteMagnitude
            var nextIdx = -1
            
            for idx in remainingIndices {
                let pos = atomsData[idx].position
                let dist = length(pos - lastPos)
                if dist < minDist {
                    minDist = dist
                    nextIdx = idx
                }
            }
            
            if nextIdx != -1 && minDist < 3.0 { // 只连接距离合理的原子
                sortedAtoms.append(atomsData[nextIdx].position)
                sortedIndices.append(nextIdx)
                remainingIndices.remove(nextIdx)
            } else {
                // 如果没有找到合适的下一个原子，开始一个新的路径段
                if remainingIndices.isEmpty { break }
                let newStart = remainingIndices.first!
                sortedAtoms.append(atomsData[newStart].position)
                sortedIndices.append(newStart)
                remainingIndices.remove(newStart)
            }
        }
        
        // 为这些碳原子创建一个默认的二级结构数组（全部设为loop）
        let defaultStructures = Array(repeating: SecondaryStructure.loop, count: sortedAtoms.count)
        
        // 计算平滑曲线
        let (curvePoints, normals, _) = generateSmoothCurve(sortedAtoms, defaultStructures)
        
        // 创建飘带几何体
        if let ribbonEntity = createRibbonGeometry(
            curvePoints: curvePoints,
            normals: normals,
            secondaryStructures: defaultStructures,
            chainIndex: 0
        ) {
            // 添加到场景
            atomsEntity.addChild(ribbonEntity)
            print("创建了基于\(sortedAtoms.count)个碳原子的简单飘带模型")
        }
    }
    
    // 提取每条链的Cα原子和二级结构信息
    private func extractChains() -> [RibbonChain] {
        // 按链ID和残基编号对原子进行分组
        var atomsByChainAndResidue: [String: [Int: [PDBAtom]]] = [:]
        // 存储二级结构信息
        var secondaryStructureByChainAndResidue: [String: [Int: SecondaryStructure]] = [:]
        
        // 解析HELIX和SHEET记录，设置相应残基的二级结构
        // 注意：这里假设PDB解析器已经提取了二级结构信息
        // 在实际应用中，您需要确保这些信息已经正确解析并存储
        
        // 预先填充所有残基为loop结构（默认）
        for (i, atomData) in atomsData.enumerated() {
            if let pdbAtom = getPDBAtom(at: i) {
                let chainID = pdbAtom.chainID
                let residueNumber = pdbAtom.residueNumber
                
                if secondaryStructureByChainAndResidue[chainID] == nil {
                    secondaryStructureByChainAndResidue[chainID] = [:]
                }
                
                // 默认设为loop
                if secondaryStructureByChainAndResidue[chainID]?[residueNumber] == nil {
                    secondaryStructureByChainAndResidue[chainID]?[residueNumber] = .loop
                }
            }
        }
        
        // 模拟设置一些二级结构（实际应用中应从PDB文件中解析）
        // 这里为了演示，随机设置一些二级结构
        for (chainID, residues) in secondaryStructureByChainAndResidue {
            var i = 0
            for residueNumber in residues.keys.sorted() {
                // 简单模式：每10个残基作为一组，轮流设置为helix、sheet、loop
                let pattern = i / 10 % 3
                if pattern == 0 {
                    secondaryStructureByChainAndResidue[chainID]?[residueNumber] = .helix
                } else if pattern == 1 {
                    secondaryStructureByChainAndResidue[chainID]?[residueNumber] = .sheet
                } // 保持其他为loop
                i += 1
            }
        }
        
        // 正常收集原子信息
        for (i, atomData) in atomsData.enumerated() {
            if let pdbAtom = getPDBAtom(at: i) {
                let chainID = pdbAtom.chainID
                let residueNumber = pdbAtom.residueNumber
                
                if atomsByChainAndResidue[chainID] == nil {
                    atomsByChainAndResidue[chainID] = [:]
                }
                
                if atomsByChainAndResidue[chainID]?[residueNumber] == nil {
                    atomsByChainAndResidue[chainID]?[residueNumber] = []
                }
                
                atomsByChainAndResidue[chainID]?[residueNumber]?.append(pdbAtom)
            }
        }
        
        // 为每条链提取Cα原子
        var chains: [RibbonChain] = []
        
        for (chainID, residues) in atomsByChainAndResidue {
            var alphaCarbon: [SIMD3<Float>] = []
            var residueNumbers: [Int] = []
            var residueNames: [String] = []
            var secondaryStructures: [SecondaryStructure] = []
            
            // 按残基编号排序
            let sortedResidues = residues.sorted { $0.key < $1.key }
            
            for (residueNumber, atoms) in sortedResidues {
                // 查找Cα原子
                if let caAtom = atoms.first(where: { $0.atomName == "CA" }) {
                    let position = SIMD3<Float>(caAtom.x, caAtom.y, caAtom.z)
                    alphaCarbon.append(position)
                    residueNumbers.append(residueNumber)
                    residueNames.append(caAtom.residueName)
                    
                    // 添加该残基的二级结构
                    let structure = secondaryStructureByChainAndResidue[chainID]?[residueNumber] ?? .loop
                    secondaryStructures.append(structure)
                }
            }
            
            // 如果链中有足够多的Cα原子，则添加该链
            if alphaCarbon.count >= 2 {  // 从3降低到2，允许更短的链
                let chain = RibbonChain(
                    alphaCarbon: alphaCarbon,
                    residueNumbers: residueNumbers,
                    residueNames: residueNames,
                    chainID: chainID,
                    secondaryStructures: secondaryStructures
                )
                chains.append(chain)
            }
        }
        
        return chains
    }
    
    // 获取指定索引处的PDB原子
    private func getPDBAtom(at index: Int) -> PDBAtom? {
        guard index < atomsData.count else { return nil }
        
        // 首先检查是否有保存的PDB原子数据
        if index < pdbAtomsData.count {
            return pdbAtomsData[index]
        }
        
        // 如果没有保存的PDB原子数据，则使用atomsData中的信息构造一个基本的PDB原子
        // 这种情况下我们无法获得准确的残基信息，只能返回默认值
        let atomData = atomsData[index]
        
        // 为保证飘带模型的正常工作，需要特殊处理alpha碳原子
        // 判断是否可能是alpha碳原子 - 使用位置相关的启发式方法
        let isLikelyAlphaCarbon = isPossibleAlphaCarbon(atomData)
        let atomName = isLikelyAlphaCarbon ? "CA" : atomData.element
        
        return PDBAtom(
            element: atomData.element,
            x: atomData.position.x,
            y: atomData.position.y,
            z: atomData.position.z,
            atomName: atomName, // 根据启发式判断可能的原子名称
            residueName: "UNK", // 未知残基
            residueNumber: index, // 使用索引作为残基编号
            chainID: "A" // 默认所有原子都在A链
        )
    }
    
    // 判断原子是否可能是alpha碳原子的辅助方法
    private func isPossibleAlphaCarbon(_ atom: AtomData) -> Bool {
        // 首先检查元素类型，只有碳原子才可能是alpha碳
        guard atom.element.uppercased() == "C" else {
            return false
        }
        
        // 尝试查找相邻的原子，判断是否符合alpha碳的拓扑特征
        // alpha碳通常连接有N原子、C原子和侧链
        var hasConnectionToN = false
        var hasConnectionToC = false
        var hasConnectionToO = false
        
        // 检查与当前原子距离在合理范围内的其他原子
        let alphaC_N_BondLength: Float = 1.5 // CA-N键的典型长度约为1.5埃
        let alphaC_C_BondLength: Float = 1.5 // CA-C键的典型长度约为1.5埃
        let alphaC_O_BondLength: Float = 2.4 // CA-O的距离通常较远，但在肽键中有一定关系
        
        // 放宽距离容差
        let distanceTolerance: Float = 0.5 // 增加容差，从0.3增加到0.5
        
        // 计算与其他原子的距离，寻找可能的连接
        for otherAtom in atomsData {
            if otherAtom.index == atom.index { continue } // 跳过自身
            
            let distance = length(atom.position - otherAtom.position)
            
            // 检查是否存在与N原子的合理距离
            if otherAtom.element.uppercased() == "N" && abs(distance - alphaC_N_BondLength) < distanceTolerance {
                hasConnectionToN = true
            }
            
            // 检查是否存在与C原子的合理距离
            if otherAtom.element.uppercased() == "C" && abs(distance - alphaC_C_BondLength) < distanceTolerance {
                hasConnectionToC = true
            }
            
            // 检查是否存在与O原子的合理距离（肽键中的羰基氧）
            if otherAtom.element.uppercased() == "O" && distance < alphaC_O_BondLength {
                hasConnectionToO = true
            }
            
            // 如果找到足够的证据，提前返回
            if (hasConnectionToN && hasConnectionToC) || 
               (hasConnectionToN && hasConnectionToO) || 
               (hasConnectionToC && hasConnectionToO) {
                return true
            }
        }
        
        // 对于只有部分信息的结构，我们放宽条件
        // 只要连接有N、C或O中的任意一个就认为可能是alpha碳
        return hasConnectionToN || hasConnectionToC || hasConnectionToO
    }
    
    // 从Cα原子坐标生成平滑曲线
    private func generateSmoothCurve(_ points: [SIMD3<Float>], _ structures: [SecondaryStructure]) -> (points: [SIMD3<Float>], normals: [SIMD3<Float>], structures: [SecondaryStructure]) {
        guard points.count >= 2 else {
            return (
                points: points,
                normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: points.count),
                structures: structures
            )
        }
        
        // 使用Cardinal样条曲线实现平滑的曲线
        let resolution = 8 // 增加分辨率，从6增加到8，使曲线更加平滑
        let tension: Float = 0.2 // 降低曲线张力，从0.3降低到0.2，使曲线更加平滑
        
        var curvePoints: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var curveStructures: [SecondaryStructure] = []
        
        // 首先对原始路径进行平滑处理
        var smoothedPoints = points
        
        // 多次应用拉普拉斯平滑
        let smoothingIterations = 3 // 增加平滑迭代次数，从2增加到3
        for _ in 0..<smoothingIterations {
            var newPoints = smoothedPoints
            
            // 保持端点不变
            for i in 1..<(smoothedPoints.count - 1) {
                // 拉普拉斯平滑 - 使用加权平均，中间点权重更高
                newPoints[i] = (smoothedPoints[i-1] * 0.25 + smoothedPoints[i] * 0.5 + smoothedPoints[i+1] * 0.25)
            }
            
            smoothedPoints = newPoints
        }
        
        // 增加点之间的间距，避免飘带太拥挤
        var spacedPoints = [SIMD3<Float>]()
        var spacedStructures = [SecondaryStructure]()
        
        // 第一个点保持不变
        spacedPoints.append(smoothedPoints[0])
        spacedStructures.append(structures[0])
        
        for i in 1..<smoothedPoints.count {
            // 获取当前点和前一个点
            let prevPoint = smoothedPoints[i-1]
            let currPoint = smoothedPoints[i]
            
            // 计算方向向量
            let direction = normalize(currPoint - prevPoint)
            
            // 根据二级结构调整间距系数
            let spacingFactor: Float
            if structures[i] == .helix {
                spacingFactor = 1.2 // α-螺旋间距适中，从1.3降低到1.2
            } else if structures[i] == .sheet {
                spacingFactor = 1.1 // β-折叠间距较小，从1.2降低到1.1
            } else {
                spacingFactor = 1.05 // Loop间距最小，从1.1降低到1.05
            }
            
            // 计算距离并增加间距
            let originalDistance = distance(prevPoint, currPoint)
            let newDistance = originalDistance * spacingFactor
            
            // 设置新位置
            let newPoint = prevPoint + direction * newDistance
            spacedPoints.append(newPoint)
            spacedStructures.append(structures[i])
        }
        
        // 然后为平滑后的路径生成曲线点
        for i in 0..<(spacedPoints.count - 1) {
            let p0 = i > 0 ? spacedPoints[i - 1] : spacedPoints[i]
            let p1 = spacedPoints[i]
            let p2 = spacedPoints[i + 1]
            let p3 = i < spacedPoints.count - 2 ? spacedPoints[i + 2] : p2 + (p2 - p1)
            
            // 当前残基的二级结构
            let currentStructure = spacedStructures[i]
            
            // 二级结构的连续性检查
            let isStructureStart = i == 0 || spacedStructures[i-1] != currentStructure
            let isStructureEnd = i == spacedStructures.count - 1 || spacedStructures[i+1] != currentStructure
            
            // 调整α-螺旋和β-折叠的分辨率
            let segmentResolution = resolution
            
            for step in 0..<segmentResolution {
                let t = Float(step) / Float(segmentResolution)
                
                // 使用CardinalSpline插值计算曲线点
                let t2 = t * t
                let t3 = t2 * t
                
                let s1 = -tension * t3 + 2 * tension * t2 - tension * t
                let s2 = (2 - tension) * t3 + (tension - 3) * t2 + 1
                let s3 = (tension - 2) * t3 + (3 - 2 * tension) * t2 + tension * t
                let s4 = tension * t3 - tension * t2
                
                let point = p0 * s1 + p1 * s2 + p2 * s3 + p3 * s4
                curvePoints.append(point)
                
                // 计算法线向量 - 使用曲线切线和全局上方向计算
                var tangent = SIMD3<Float>(0, 0, 0)
                if step < segmentResolution - 1 {
                    let nextT = Float(step + 1) / Float(segmentResolution)
                    let nextT2 = nextT * nextT
                    let nextT3 = nextT2 * nextT
                    
                    let nextS1 = -tension * nextT3 + 2 * tension * nextT2 - tension * nextT
                    let nextS2 = (2 - tension) * nextT3 + (tension - 3) * nextT2 + 1
                    let nextS3 = (tension - 2) * nextT3 + (3 - 2 * tension) * nextT2 + tension * nextT
                    let nextS4 = tension * nextT3 - tension * nextT2
                    
                    let nextPoint = p0 * nextS1 + p1 * nextS2 + p2 * nextS3 + p3 * nextS4
                    tangent = normalize(nextPoint - point)
                } else if i < smoothedPoints.count - 2 {
                    tangent = normalize(p2 - point)
                } else {
                    tangent = normalize(point - p1)
                }
                
                // 使用全局上方向和切线计算法线
                let globalUp = SIMD3<Float>(0, 1, 0)
                let right = normalize(cross(tangent, globalUp))
                let correctedNormal = normalize(cross(right, tangent))
                
                normals.append(correctedNormal)
                
                // 保持该点具有与原始残基相同的二级结构
                curveStructures.append(currentStructure)
            }
        }
        
        // 添加最后一个点
        curvePoints.append(spacedPoints.last!)
        
        // 计算最后一点的法线 - 使用倒数第二点到最后一点的方向
        let lastTangent = normalize(spacedPoints.last! - spacedPoints[spacedPoints.count - 2])
        let globalUp = SIMD3<Float>(0, 1, 0)
        let lastRight = normalize(cross(lastTangent, globalUp))
        let lastNormal = normalize(cross(lastRight, lastTangent))
        
        normals.append(lastNormal)
        curveStructures.append(structures.last!)
        
        return (curvePoints, normals, curveStructures)
    }
    
    // 将曲线按二级结构分段 - 添加平滑过渡
    private func segmentBySecondaryStructure(
        curvePoints: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        secondaryStructures: [SecondaryStructure]
    ) -> [RibbonSegment] {
        guard !curvePoints.isEmpty else { return [] }
        
        var segments: [RibbonSegment] = []
        var currentPoints: [SIMD3<Float>] = []
        var currentNormals: [SIMD3<Float>] = []
        var currentStructure = secondaryStructures[0]
        var transitionPoints: Int = 0 // 用于跟踪过渡区域
        
        // 合并相同类型的短段
        var mergedStructures = secondaryStructures
        let minSegmentLength = 5 // 最小段长度
        
        // 第一步：标记极短段
        var segmentStarts: [Int] = [0]
        var currentType = secondaryStructures[0]
        
        for i in 1..<secondaryStructures.count {
            if secondaryStructures[i] != currentType {
                segmentStarts.append(i)
                currentType = secondaryStructures[i]
            }
        }
        
        // 第二步：合并短段
        for i in 0..<(segmentStarts.count - 1) {
            let start = segmentStarts[i]
            let end = (i < segmentStarts.count - 1) ? segmentStarts[i+1] - 1 : secondaryStructures.count - 1
            let length = end - start + 1
            
            // 如果段太短，尝试合并
            if length < minSegmentLength {
                let segmentType = secondaryStructures[start]
                
                // 取前后段的类型，选择不是loop的类型(优先保留二级结构)
                var newType = segmentType
                
                if segmentType == .loop {
                    // 如果当前是loop，检查前后段
                    if i > 0 && secondaryStructures[segmentStarts[i-1]] != .loop {
                        newType = secondaryStructures[segmentStarts[i-1]]
                    } else if i < segmentStarts.count - 1 && secondaryStructures[segmentStarts[i+1]] != .loop {
                        newType = secondaryStructures[segmentStarts[i+1]]
                    }
                }
                
                // 应用新类型
                for j in start...end {
                    mergedStructures[j] = newType
                }
            }
        }
        
        // 使用合并后的结构创建段
        for i in 0..<curvePoints.count {
            let structure = mergedStructures[i]
            
            if i == 0 {
                // 开始新段
                currentPoints = [curvePoints[i]]
                currentNormals = [normals[i]]
                currentStructure = structure
                continue
            }
            
            // 检查结构变化
            if structure != currentStructure {
                // 结构转变 - 添加过渡区
                let transitionLength = 3 // 过渡点数量
                
                if transitionPoints == 0 {
                    // 开始过渡
                    transitionPoints = 1
                    
                    // 继续当前段
                    currentPoints.append(curvePoints[i])
                    currentNormals.append(normals[i])
                } else {
                    // 在过渡中
                    transitionPoints += 1
                    
                    // 添加到当前段
                    currentPoints.append(curvePoints[i])
                    currentNormals.append(normals[i])
                    
                    // 检查是否完成过渡
                    if transitionPoints >= transitionLength {
                        // 保存当前段
                        if !currentPoints.isEmpty {
                            segments.append(RibbonSegment(
                                points: currentPoints,
                                normals: currentNormals,
                                structure: currentStructure
                            ))
                        }
                        
                        // 开始新段
                        currentPoints = [curvePoints[max(0, i-1)], curvePoints[i]] // 包含一个重叠点确保连续性
                        currentNormals = [normals[max(0, i-1)], normals[i]]
                        currentStructure = structure
                        transitionPoints = 0
                    }
                }
            } else {
                // 相同结构 - 重置过渡计数
                transitionPoints = 0
                
                // 继续当前段
                currentPoints.append(curvePoints[i])
                currentNormals.append(normals[i])
            }
        }
        
        // 添加最后一段
        if !currentPoints.isEmpty {
            segments.append(RibbonSegment(
                points: currentPoints,
                normals: currentNormals,
                structure: currentStructure
            ))
        }
        
        return segments
    }
    
    // 为特定二级结构创建几何体
    private func createSegmentGeometry(
        curvePoints: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        secondaryStructure: SecondaryStructure
    ) -> ModelEntity? {
        guard curvePoints.count > 2 else { return nil }
        
        // 根据二级结构设置颜色和宽度
        var color: UIColor
        var ribbonWidth: Float
        
        switch secondaryStructure {
        case .helix:
            color = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // 红色
            ribbonWidth = 0.12  // 增加α螺旋的基础宽度，从0.09增加到0.12
        case .sheet:
            color = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0) // 黄色
            ribbonWidth = 0.08  // 增加β折叠宽度，从0.06增加到0.08
        case .loop:
            color = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0) // 蓝色
            ribbonWidth = 0.04  // 增加loop宽度，从0.03增加到0.04
        }
        
        // 检查曲线是否足够长
        if secondaryStructure == .helix && curvePoints.count < 8 {
            // 对于太短的α-螺旋，使用普通飘带表示
            return createRibbonGeometryEnhanced(
                curvePoints: curvePoints,
                normals: normals,
                color: color,
                width: ribbonWidth,
                isSheet: false
            )
        } else if secondaryStructure == .helix {
            // 为α-螺旋创建特殊的螺旋状几何体
            return createHelixGeometry(curvePoints: curvePoints, normals: normals, color: color, width: ribbonWidth)
        } else {
            // 为β-折叠和Loop创建改进的飘带几何体
            return createRibbonGeometryEnhanced(
                curvePoints: curvePoints,
                normals: normals,
                color: color,
                width: ribbonWidth,
                isSheet: secondaryStructure == .sheet
            )
        }
    }
    
    // 创建α-螺旋专用的螺旋状几何体
    private func createHelixGeometry(
        curvePoints: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        color: UIColor,
        width: Float
    ) -> ModelEntity? {
        guard curvePoints.count > 3 else { return nil }
        
        // 首先平滑主轴曲线，减少锯齿状
        var smoothedPoints = [SIMD3<Float>]()
        var smoothedNormals = [SIMD3<Float>]()
        
        // 对曲线进行平滑
        for i in 0..<curvePoints.count {
            if i == 0 || i == curvePoints.count - 1 {
                // 保持端点不变
                smoothedPoints.append(curvePoints[i])
                smoothedNormals.append(normals[i])
            } else {
                // 平滑中间点 - 加权平均
                let prev = curvePoints[i-1]
                let curr = curvePoints[i]
                let next = curvePoints[i+1]
                
                // 加权平均，当前点权重较高
                let smoothed = prev * 0.2 + curr * 0.6 + next * 0.2
                smoothedPoints.append(smoothed)
                
                // 平滑法线
                let smoothedNormal = normalize(normals[i-1] * 0.2 + normals[i] * 0.6 + normals[i+1] * 0.2)
                smoothedNormals.append(smoothedNormal)
            }
        }
        
        // 为α-螺旋创建特殊的螺旋状几何体
        var helixVertices: [SIMD3<Float>] = []
        var helixIndices: [UInt32] = []
        var helixNormals: [SIMD3<Float>] = []
        
        // 设置螺旋参数
        let radius = width * 1.0        // 增大螺旋半径，从0.9增加到1.0
        let pitch = width * 1.2         // 保持螺旋间距不变
        let circleSegments = 16         // 增加横截面分段数，从12增加到16，使螺旋更圆滑
        let tubeRadius = width * 0.4   // 增加管径，从0.35增加到0.4
        
        // 确保有足够的点来创建平滑的螺旋
        let minPointsNeeded = max(12, smoothedPoints.count)  // 增加最小点数，从10增加到12
        var interpolatedPoints = [SIMD3<Float>]()
        var interpolatedNormals = [SIMD3<Float>]()
        
        // 线性插值创建更多点
        if smoothedPoints.count < minPointsNeeded {
            let step = 1.0 / Float(minPointsNeeded - 1)
            
            for i in 0..<minPointsNeeded {
                let t = min(1.0, Float(i) * step)
                let index = Float(smoothedPoints.count - 1) * t
                let lowerIndex = min(smoothedPoints.count - 1, Int(floor(index)))
                let upperIndex = min(smoothedPoints.count - 1, lowerIndex + 1)
                let fraction = index - Float(lowerIndex)
                
                // 插值位置
                let point = mix(
                    smoothedPoints[lowerIndex], 
                    upperIndex < smoothedPoints.count ? smoothedPoints[upperIndex] : smoothedPoints[lowerIndex], 
                    t: fraction
                )
                
                // 插值法线
                let normal = normalize(mix(
                    smoothedNormals[lowerIndex], 
                    upperIndex < smoothedNormals.count ? smoothedNormals[upperIndex] : smoothedNormals[lowerIndex], 
                    t: fraction
                ))
                
                interpolatedPoints.append(point)
                interpolatedNormals.append(normal)
            }
        } else {
            interpolatedPoints = smoothedPoints
            interpolatedNormals = smoothedNormals
        }
        
        // 计算每个原始曲线点之间应该有多少个螺旋点
        let totalHelixPoints = interpolatedPoints.count
        
        // 先计算全局切线以确保螺旋方向一致
        var pathTangents = [SIMD3<Float>]()
        for i in 0..<interpolatedPoints.count {
            var tangent = SIMD3<Float>(0, 0, 0)
            if i == 0 {
                // 第一点，使用前向差分
                tangent = normalize(interpolatedPoints[1] - interpolatedPoints[0])
            } else if i == interpolatedPoints.count - 1 {
                // 最后一点，使用后向差分
                tangent = normalize(interpolatedPoints[i] - interpolatedPoints[i-1])
            } else {
                // 中间点，使用中心差分
                tangent = normalize(interpolatedPoints[i+1] - interpolatedPoints[i-1])
            }
            pathTangents.append(tangent)
        }
        
        // 创建螺旋点
        for i in 0..<totalHelixPoints {
            // 获取当前点和切线
            let centerPoint = interpolatedPoints[i]
            let tangent = pathTangents[i]
            
            // 使用当前法线和切线创建稳定的坐标系
            let normal = interpolatedNormals[i]
            let correctedNormal = normalize(normal - dot(normal, tangent) * tangent)
            let binormal = normalize(cross(tangent, correctedNormal))
            
            // 计算螺旋角度 - 使其更加均匀
            let helixAngle = Float(i) * 0.8 // 控制螺旋密度
            
            // 创建螺旋偏移
            let offsetX = radius * cos(helixAngle)
            let offsetY = radius * sin(helixAngle)
            
            // 计算偏移的中心点
            let helixCenter = centerPoint + correctedNormal * offsetX + binormal * offsetY
            
            // 创建环形截面
            for j in 0..<circleSegments {
                let angle = Float(j) * 2 * Float.pi / Float(circleSegments)
                
                // 计算环形截面上的点
                let circleOffsetX = tubeRadius * cos(angle)
                let circleOffsetY = tubeRadius * sin(angle)
                
                // 计算最终顶点位置
                let vertex = helixCenter + correctedNormal * circleOffsetX + binormal * circleOffsetY
                helixVertices.append(vertex)
                
                // 计算顶点法线 - 从中心点指向顶点
                let vertexNormal = normalize(vertex - helixCenter)
                helixNormals.append(vertexNormal)
            }
            
            // 创建索引 - 连接相邻环
            if i < totalHelixPoints - 1 {
                for j in 0..<circleSegments {
                    let nextJ = (j + 1) % circleSegments
                    let baseIndex = UInt32(i * circleSegments)
                    
                    // 第一个三角形
                    helixIndices.append(baseIndex + UInt32(j))
                    helixIndices.append(baseIndex + UInt32(nextJ))
                    helixIndices.append(baseIndex + UInt32(circleSegments) + UInt32(j))
                    
                    // 第二个三角形
                    helixIndices.append(baseIndex + UInt32(nextJ))
                    helixIndices.append(baseIndex + UInt32(circleSegments) + UInt32(nextJ))
                    helixIndices.append(baseIndex + UInt32(circleSegments) + UInt32(j))
                }
            }
        }
        
        // 确保网格有效
        guard !helixVertices.isEmpty && !helixIndices.isEmpty else { return nil }
        
        // 创建网格描述符
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(helixVertices)
        meshDescriptor.primitives = .triangles(helixIndices)
        meshDescriptor.normals = MeshBuffer(helixNormals)
        
        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])
            let helixEntity = ModelEntity(mesh: meshResource)
            
            // 创建材质
            var material = PhysicallyBasedMaterial()
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
            material.roughness = 0.05  // 更光滑，从0.1降低到0.05
            material.metallic = 0.3   // 更有金属感，从0.2增加到0.3
            
            helixEntity.model?.materials = [material]
            return helixEntity
        } catch {
            print("创建α-螺旋几何体失败: \(error)")
            return nil
        }
    }
    
    // 创建增强版的飘带几何体，适用于β-折叠和Loop
    private func createRibbonGeometryEnhanced(
        curvePoints: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        color: UIColor,
        width: Float,
        isSheet: Bool
    ) -> ModelEntity? {
        guard curvePoints.count > 2 else { return nil }
        
        let halfWidth = width / 2
        
        // 创建顶点和索引
        var vertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        var vertexNormals: [SIMD3<Float>] = [] // 用于光照计算
        
        // 生成飘带的顶点 - 为每个曲线点创建横截面
        for i in 0..<curvePoints.count {
            let point = curvePoints[i]
            let normal = normals[i]
            
            // 计算切线
            var tangent = SIMD3<Float>(0, 0, 0)
            if i < curvePoints.count - 1 {
                tangent = normalize(curvePoints[i + 1] - point)
            } else if i > 0 {
                tangent = normalize(point - curvePoints[i - 1])
            }
            
            // 确保法线和切线是垂直的
            let correctedNormal = normalize(normal - dot(normal, tangent) * tangent)
            
            // 计算横向向量
            let crossVec = normalize(cross(tangent, correctedNormal))
            
            // β-折叠特殊处理 - 为末端创建箭头效果
            var localWidth = halfWidth
            if isSheet {
                // 检测是否处于β-折叠的末端区域
                let progress = Float(i) / Float(max(1, curvePoints.count - 1))
                if progress > 0.8 {
                    // 在β-折叠末端创建渐进式扩展，模拟箭头效果
                    let factor = 1.0 + (progress - 0.8) * 5.0 * 1.5 // 最大扩展到1.5倍
                    localWidth = halfWidth * factor
                }
            }
            
            // 创建更平滑的横截面 - 添加中间点使飘带更加圆润
            let sidePointCount = 4 // 每侧的点数
            
            for j in 0...sidePointCount {
                // 计算偏转角度 - 从上到下
                let angle = Float.pi * Float(j) / Float(sidePointCount)
                
                // 计算偏移向量 (结合normal和crossVec)
                let offsetVec = correctedNormal * cos(angle) + crossVec * sin(angle)
                
                // 添加顶点
                let vertexPosition = point + offsetVec * localWidth
                vertices.append(vertexPosition)
                
                // 添加法线 - 用于正确的光照计算
                vertexNormals.append(offsetVec)
            }
            
            // 生成三角形索引
            if i < curvePoints.count - 1 {
                let baseIndex = UInt32(i * (sidePointCount + 1))
                
                for j in 0..<sidePointCount {
                    // 每个截面之间连接两个三角形
                    // 第一个三角形
                    triangleIndices.append(baseIndex + UInt32(j))
                    triangleIndices.append(baseIndex + UInt32(j + 1))
                    triangleIndices.append(baseIndex + UInt32(sidePointCount + 1) + UInt32(j))
                    
                    // 第二个三角形
                    triangleIndices.append(baseIndex + UInt32(j + 1))
                    triangleIndices.append(baseIndex + UInt32(sidePointCount + 1) + UInt32(j + 1))
                    triangleIndices.append(baseIndex + UInt32(sidePointCount + 1) + UInt32(j))
                }
            }
        }
        
        // 确保顶点数组不为空且索引有效
        guard !vertices.isEmpty && vertices.count >= 3 else { return nil }
        guard !triangleIndices.isEmpty && triangleIndices.count % 3 == 0 else { return nil }
        
        // 创建网格描述符和资源
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(vertices)
        meshDescriptor.primitives = .triangles(triangleIndices)
        meshDescriptor.normals = MeshBuffer(vertexNormals)
        
        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])
            let segmentEntity = ModelEntity(mesh: meshResource)
            
            // 设置材质 - 使用更高质量的材质设置
            var material = PhysicallyBasedMaterial()
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
            material.roughness = 0.2  // 更光滑
            material.metallic = 0.1   // 轻微金属感
            
            // β-折叠特殊处理
            if isSheet {
                material.roughness = 0.3
            }
            
            segmentEntity.model?.materials = [material]
            return segmentEntity
        } catch {
            print("创建增强飘带几何体失败: \(error)")
            return nil
        }
    }
    
    // 创建飘带几何体
    private func createRibbonGeometry(
        curvePoints: [SIMD3<Float>], 
        normals: [SIMD3<Float>], 
        secondaryStructures: [SecondaryStructure],
        chainIndex: Int
    ) -> ModelEntity? {
        guard curvePoints.count > 3, curvePoints.count == normals.count, curvePoints.count == secondaryStructures.count else { return nil }
        
        // 创建顶点和索引
        var vertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []
        var vertexColors: [SIMD4<Float>] = [] // 用于存储每个顶点的颜色
        
        // 为每种二级结构定义颜色
        let helixColor = SIMD4<Float>(1.0, 0.2, 0.2, 1.0)   // 红色 - α螺旋
        let sheetColor = SIMD4<Float>(1.0, 0.8, 0.0, 1.0)   // 黄色 - β折叠
        let loopColor = SIMD4<Float>(0.2, 0.4, 0.8, 1.0)    // 蓝色 - loop
        
        // 生成飘带的顶点和颜色
        for i in 0..<curvePoints.count {
            let point = curvePoints[i]
            let normal = normals[i]
            let structure = secondaryStructures[i]
            
            // 根据二级结构调整飘带宽度
            let ribbonWidth: Float
            switch structure {
            case .helix:
                ribbonWidth = 0.07 // α螺旋更宽
            case .sheet:
                ribbonWidth = 0.06 // β折叠较宽
            case .loop:
                ribbonWidth = 0.03 // loop较窄
            }
            let ribbonHalfWidth = ribbonWidth / 2
            
            // 计算垂直于曲线和法线的向量
            var tangent = SIMD3<Float>(0, 0, 0)
            if i < curvePoints.count - 1 {
                tangent = normalize(curvePoints[i + 1] - point)
            } else if i > 0 {
                tangent = normalize(point - curvePoints[i - 1])
            }
            
            // 确保法线和切线是垂直的
            let correctedNormal = normalize(normal - dot(normal, tangent) * tangent)
            
            // 计算飘带的两侧顶点
            let crossVec = normalize(cross(tangent, correctedNormal))
            let leftPoint = point - crossVec * ribbonHalfWidth
            let rightPoint = point + crossVec * ribbonHalfWidth
            
            // 添加顶点
            vertices.append(leftPoint)
            vertices.append(rightPoint)
            
            // 根据二级结构设置颜色
            var color: SIMD4<Float>
            switch structure {
            case .helix:
                color = helixColor
            case .sheet:
                color = sheetColor
                
                // 对于β折叠，我们添加额外处理来创建箭头状效果
                if i > 0 && i < curvePoints.count - 1 {
                    // 检查是否处于β折叠末端附近
                    let isNearEnd = i % 10 == 9
                    if isNearEnd && structure == .sheet {
                        // 在β折叠末端创建箭头效果，略微加宽
                        let arrowWidth = ribbonHalfWidth * 1.5
                        vertices[vertices.count - 2] = leftPoint - crossVec * arrowWidth
                        vertices[vertices.count - 1] = rightPoint + crossVec * arrowWidth
                    }
                }
            case .loop:
                color = loopColor
            }
            
            // 添加顶点颜色
            vertexColors.append(color)
            vertexColors.append(color)
            
            // 生成三角形索引
            if i < curvePoints.count - 1 {
                let baseIndex = UInt32(i * 2)
                // 第一个三角形
                triangleIndices.append(baseIndex)
                triangleIndices.append(baseIndex + 1)
                triangleIndices.append(baseIndex + 2)
                // 第二个三角形
                triangleIndices.append(baseIndex + 1)
                triangleIndices.append(baseIndex + 3)
                triangleIndices.append(baseIndex + 2)
            }
        }
        
        // 确保顶点数组不为空且索引有效
        guard !vertices.isEmpty && vertices.count >= 3 else {
            print("飘带几何体顶点不足")
            return nil
        }
        
        guard !triangleIndices.isEmpty && triangleIndices.count % 3 == 0 else {
            print("飘带几何体三角形索引无效")
            return nil
        }
        
        // 创建网格描述符
        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffer(vertices)
        meshDescriptor.primitives = .triangles(triangleIndices)
        
        // 添加颜色信息
        // MeshDescriptor没有直接的colors属性，需要使用其他方法处理顶点颜色
        // 创建网格资源
        do {
            let meshResource = try MeshResource.generate(from: [meshDescriptor])
            let ribbonEntity = ModelEntity(mesh: meshResource)
            
            // 创建自定义材质
            var material = PhysicallyBasedMaterial()
            
            // 根据二级结构使用平均颜色
            // 统计各种二级结构的数量
            let helixCount = secondaryStructures.filter { $0 == .helix }.count
            let sheetCount = secondaryStructures.filter { $0 == .sheet }.count
            let loopCount = secondaryStructures.filter { $0 == .loop }.count
            
            // 选择主要的二级结构类型
            var primaryColor: UIColor
            if helixCount >= sheetCount && helixCount >= loopCount {
                // 如果主要是α-螺旋，使用红色
                primaryColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
            } else if sheetCount >= helixCount && sheetCount >= loopCount {
                // 如果主要是β-折叠，使用黄色
                primaryColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
            } else {
                // 如果主要是loop，使用蓝色
                primaryColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
            }
            
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: primaryColor)
            material.roughness = 0.5
            material.metallic = 0.0
            
            // 设置材质
            ribbonEntity.model?.materials = [material]
            
            // 为不同二级结构创建单独的实体
            let segments = segmentBySecondaryStructure(
                curvePoints: curvePoints,
                normals: normals,
                secondaryStructures: secondaryStructures
            )
            
            for segment in segments {
                if let segmentEntity = createSegmentGeometry(
                    curvePoints: segment.points,
                    normals: segment.normals,
                    secondaryStructure: segment.structure
                ) {
                    ribbonEntity.addChild(segmentEntity)
                }
            }
            
            return ribbonEntity
        } catch {
            print("创建飘带几何体失败: \(error)")
            return nil
        }
    }
    
    // 清除特定于显示模式的实体
    private func clearDisplayModeSpecificEntities() {
        // 清除表面模型实体
        let surfaceEntities = atomsEntity.children.filter { $0.name == "protein_surface" }
        for entity in surfaceEntities {
            entity.removeFromParent()
        }
        
        // 清除atomsEntity中的非原子实体，但保留选中的原子实体
        let nonAtomEntities = atomsEntity.children.filter { entity in
            // 检查该实体是否为原子实体（在atomEntityMap中）
            let isAtomEntity = atomEntityMap.values.contains { $0 === entity }
            // 如果不是原子实体并且不是表面实体（已在前面处理），则需要移除
            return !isAtomEntity && entity.name != "protein_surface"
        }
        
        for entity in nonAtomEntities {
            entity.removeFromParent()
        }
    }
    
    // 添加自动调整模型大小和位置的方法(怀疑这里有问题）
    private func adjustModelForVisibility() {
        print("自动调整模型大小和位置以适应屏幕")
        
        guard !atomsData.isEmpty else {
            print("没有原子数据，无法调整视图")
            return
        }
        
        guard let rootEntity = rootEntity else { return }
        
        // 计算边界
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        
        for atomData in atomsData {
            let position = atomData.position
            let element = atomData.element
            let radius = (Constants.atomRadii[element] ?? 0.04) * 1.2
            
            let atomMin = position - SIMD3<Float>(radius, radius, radius)
            let atomMax = position + SIMD3<Float>(radius, radius, radius)
            
            minBounds = min(minBounds, atomMin)
            maxBounds = max(maxBounds, atomMax)
        }
        
        let center = (minBounds + maxBounds) * 0.5
        let size = maxBounds - minBounds
        let maxDimension = max(max(size.x, size.y), size.z)
        
        var scaleFactor: Float = 1.0
        if maxDimension > 0.001 {
            scaleFactor = 1.0 / maxDimension
            scaleFactor = min(max(scaleFactor, 0.001), 5.0)
        }
        
        // ⚡⚡⚡ 关键补充
        atomsEntity.position = -center
        atomsEntity.scale = [1.0, 1.0, 1.0] // 重置atomsEntity的scale，防止连续叠加
        
        bondsEntity.position = -center
        bondsEntity.scale = [1.0, 1.0, 1.0] // bondsEntity也重置
        
        // 最后统一调整rootEntity的缩放
        rootEntity.scale = [scaleFactor, scaleFactor, scaleFactor]
        //这里是有关蛋白质分子位置的，如果分子后面没有显示全就调整这个值，改这里
        rootEntity.position.z = 0 // 保证模型处在合适z轴
        
        print("调整完成: center=\(center), scale=\(scaleFactor)")
    }


    // MARK: - 视口管理方法
    @MainActor
    func ensureModelInViewport() {
        guard let rootEntity = rootEntity, !atomsData.isEmpty else { return }
        
        // 获取当前缩放
        let currentScale = rootEntity.scale.x
        
        // 限制最小和最大缩放值，防止模型过小或过大
        let minScale: Float = 0.01
        let maxScale: Float = 10.0
        
        if currentScale < minScale || currentScale > maxScale {
            // 如果缩放超出范围，重置为有效范围内
            let newScale = max(minScale, min(maxScale, currentScale))
            rootEntity.scale = [newScale, newScale, newScale]
        }
        
        // 确保模型Z轴位置在合理范围内（不要太远或太近）
        let minZ: Float = -5.0
        let maxZ: Float = -0.1
        
        if rootEntity.position.z < minZ || rootEntity.position.z > maxZ {
            rootEntity.position.z = max(minZ, min(maxZ, rootEntity.position.z))
        }
        
        // 限制XY位置，防止模型完全离开视野
        let boundaryLimit: Float = 3.0 * currentScale
        rootEntity.position.x = max(-boundaryLimit, min(boundaryLimit, rootEntity.position.x))
        rootEntity.position.y = max(-boundaryLimit, min(boundaryLimit, rootEntity.position.y))
    }
    
    @MainActor
    func scale(by factor: Float) {
        guard let rootEntity = rootEntity else { return }

        let minScale: Float = 0.1
        let maxScale: Float = 5.0

        // 获取当前缩放值
        let currentScale = rootEntity.scale.x
        var newScale = currentScale * factor

        // 限制缩放范围
        newScale = min(max(newScale, minScale), maxScale)

        // 更新所有子实体的缩放
        atomsEntity.scale = SIMD3<Float>(repeating: newScale)
        bondsEntity.scale = SIMD3<Float>(repeating: newScale)

        // 保持居中位置不偏移
        atomsEntity.position = -getModelCenter() * newScale
        bondsEntity.position = -getModelCenter() * newScale
    }
    
    private func getModelCenter() -> SIMD3<Float> {
        var minBounds = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

        for atom in atomsData {
            let position = atom.position
            minBounds = min(minBounds, position)
            maxBounds = max(maxBounds, position)
        }

        return (minBounds + maxBounds) / 2
    }
    
    // 帮助函数 - 线性插值
    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        return a * (1 - t) + b * t
    }

    // 获取选中原子列表
    func getSelectedAtoms() -> Set<Int> {
        return selectedAtoms
    }
    
    private func createProteinSurface() async {
        print("【调试】开始创建表面模型 - 按残基分组创建连续表面")
        
        // 添加异常处理
        do {
        // 创建表面实体
        let surfaceEntity = ModelEntity()
        surfaceEntity.name = "protein_surface"
            print("【调试】创建了表面根实体: \(surfaceEntity.name)")
        
        // 设置通用透明度
            let transparencyLevel: Float = 0.85  // 降低透明度，使模型更可见
            print("【调试】设置材质透明度: \(transparencyLevel)")
        
            // 使用更鲜明的颜色和更好的材质效果
            // 疏水性残基 - 白色
        var hydrophobicMaterial = PhysicallyBasedMaterial()
            hydrophobicMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor(white: 0.9, alpha: 0.8))
            hydrophobicMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.3)
            hydrophobicMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.2)
        hydrophobicMaterial.blending = .transparent(opacity: .init(floatLiteral: transparencyLevel))
        
            // 极性不带电残基 - 更鲜艳的绿色
        var polarMaterial = PhysicallyBasedMaterial()
            polarMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 0.8))
            polarMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.3)
            polarMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.2)
        polarMaterial.blending = .transparent(opacity: .init(floatLiteral: transparencyLevel))
        
            // 带负电（酸性）残基 - 鲜红色
        var acidicMaterial = PhysicallyBasedMaterial()
            acidicMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 0.8))
            acidicMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.3)
            acidicMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.2)
        acidicMaterial.blending = .transparent(opacity: .init(floatLiteral: transparencyLevel))
        
            // 带正电（碱性）残基 - 鲜蓝色
        var basicMaterial = PhysicallyBasedMaterial()
            basicMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor(red: 0.1, green: 0.3, blue: 1.0, alpha: 0.8))
            basicMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.3)
            basicMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.2)
        basicMaterial.blending = .transparent(opacity: .init(floatLiteral: transparencyLevel))
        
            // 默认材质 - 淡紫色
        var defaultMaterial = PhysicallyBasedMaterial()
            defaultMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor(red: 0.8, green: 0.7, blue: 0.9, alpha: 0.75))
            defaultMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.25)
            defaultMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.2)
        defaultMaterial.blending = .transparent(opacity: .init(floatLiteral: transparencyLevel))
        
            print("【调试】创建了5种材质：疏水性、极性、酸性、碱性和默认材质")
            
            // 将材质添加到字典
            var residueMaterials: [String: PhysicallyBasedMaterial] = [:]
        residueMaterials["ALA"] = hydrophobicMaterial
        residueMaterials["VAL"] = hydrophobicMaterial
        residueMaterials["ILE"] = hydrophobicMaterial
            residueMaterials["LEU"] = hydrophobicMaterial
        residueMaterials["MET"] = hydrophobicMaterial
            residueMaterials["PHE"] = hydrophobicMaterial
            residueMaterials["TRP"] = hydrophobicMaterial
        residueMaterials["PRO"] = hydrophobicMaterial
        residueMaterials["GLY"] = hydrophobicMaterial
        
        residueMaterials["SER"] = polarMaterial
        residueMaterials["THR"] = polarMaterial
        residueMaterials["ASN"] = polarMaterial
        residueMaterials["GLN"] = polarMaterial
            residueMaterials["TYR"] = polarMaterial
        residueMaterials["CYS"] = polarMaterial
        
        residueMaterials["ASP"] = acidicMaterial
        residueMaterials["GLU"] = acidicMaterial
        
        residueMaterials["LYS"] = basicMaterial
        residueMaterials["ARG"] = basicMaterial
        residueMaterials["HIS"] = basicMaterial
        
            // 为元素类型也添加对应材质
            residueMaterials["C"] = hydrophobicMaterial
            residueMaterials["H"] = hydrophobicMaterial
            residueMaterials["N"] = polarMaterial
            residueMaterials["O"] = acidicMaterial
            residueMaterials["S"] = polarMaterial
            residueMaterials["P"] = acidicMaterial
            
            print("【调试】配置了所有残基类型和元素的材质映射关系")
            
            // ======= 新增：按残基或链ID组织原子 =======
            
            // 1. 尝试按残基组织原子（优先使用PDB原子信息）
            var atomsByResidue: [String: [AtomData]] = [:]
            var residueNames: [String] = []
            var residueCount = 0
            
            if !pdbAtomsData.isEmpty {
                print("【调试】使用PDB数据按残基组织原子")
                
                // 创建一个映射来找到原子的PDB信息
                var atomToPDBMapping: [Int: Int] = [:]
                
                // 建立atom索引到PDB索引的映射
                for (i, atomData) in atomsData.enumerated() {
                    var bestMatchIndex = -1
                    var bestMatchDistance: Float = 0.05 // 匹配阈值
                    
                    for (j, pdbAtom) in pdbAtomsData.enumerated() {
                        if pdbAtom.element.uppercased() == atomData.element.uppercased() {
                            let dist = length(atomData.position - SIMD3<Float>(pdbAtom.x, pdbAtom.y, pdbAtom.z))
                            if dist < bestMatchDistance {
                                bestMatchDistance = dist
                                bestMatchIndex = j
                            }
                        }
                    }
                    
                    if bestMatchIndex >= 0 {
                        atomToPDBMapping[i] = bestMatchIndex
                    }
                }
                
                // 使用映射按残基组织原子
                for (atomIndex, pdbIndex) in atomToPDBMapping {
                    let pdbAtom = pdbAtomsData[pdbIndex]
                    // 创建一个包含链ID和残基编号的唯一标识符
                    let residueKey = "\(pdbAtom.chainID)_\(pdbAtom.residueName)_\(pdbAtom.residueNumber)"
                    
                    if atomsByResidue[residueKey] == nil {
                        atomsByResidue[residueKey] = []
                        residueNames.append(residueKey)
                        residueCount += 1
                    }
                    
                    atomsByResidue[residueKey]?.append(atomsData[atomIndex])
                }
                
                print("【调试】按残基分组：找到\(residueCount)个残基组")
            }
            
            // 2. 如果未能按残基组织，退回到按元素分组
            if residueCount == 0 {
                print("【调试】无法使用残基信息，按元素类型分组")
                
                for (i, atom) in atomsData.enumerated() {
                    let elementKey = "ELEM_\(atom.element.uppercased())"
                    
                    if atomsByResidue[elementKey] == nil {
                        atomsByResidue[elementKey] = []
                        residueNames.append(elementKey)
                    }
                    
                    atomsByResidue[elementKey]?.append(atom)
                }
                
                print("【调试】按元素分组：找到\(atomsByResidue.count)种元素组")
            }
            
            // 3. 创建每个残基/元素组的表面
            var surfacesCreated = 0
            
            for residueKey in residueNames {
                guard let atoms = atomsByResidue[residueKey], !atoms.isEmpty else { continue }
                
                // 暂停一下避免UI冻结
                if surfacesCreated % 5 == 0 && surfacesCreated > 0 {
                    try await Task.sleep(nanoseconds: 1_000_000) // 1毫秒
                }
                
                print("【调试】处理残基/元素组: \(residueKey), 原子数: \(atoms.count)")
                
                // 确定材质
                var material: PhysicallyBasedMaterial
                if residueKey.starts(with: "ELEM_") {
                    // 元素组使用元素材质
                    let elemType = String(residueKey.dropFirst(5))
                    material = residueMaterials[elemType] ?? defaultMaterial
                } else {
                    // 残基组使用残基类型材质
                    let parts = residueKey.split(separator: "_")
                    if parts.count >= 2 {
                        let residueType = String(parts[1])
                        material = residueMaterials[residueType] ?? defaultMaterial
                    } else {
                        material = defaultMaterial
                    }
                }
                
                // 为该残基/元素组创建表面
                // 放宽条件：只要有2个以上的原子就尝试创建表面
                if atoms.count >= 2 {
                    print("【调试】为\(residueKey)创建连续表面")
                    
                    // 调用优化的连续表面创建函数，放宽条件
                    if let residueSurface = createResidueSimplifiedSurface(atoms: atoms, material: material, residueName: residueKey) {
                        surfaceEntity.addChild(residueSurface)
                        surfacesCreated += 1
                        print("【调试】成功为\(residueKey)创建了表面")
                    } else {
                        print("【调试】为\(residueKey)创建连续表面失败，回退到简单表示")
                        // 创建简单球体表示作为后备
                        let fallbackSurface = createFallbackResidueBlob(atoms: atoms, material: material)
                        surfaceEntity.addChild(fallbackSurface)
                        surfacesCreated += 1
                    }
                } else if atoms.count == 1 {
                    // 对于单个原子，创建一个较大的球体
                    let atom = atoms[0]
                    let radius = getAtomRadius(for: atom.element) * 2.0 // 使用较大半径
                    let sphere = ModelEntity(mesh: .generateSphere(radius: radius))
                    sphere.position = atom.position
                    sphere.model?.materials = [material]
                    surfaceEntity.addChild(sphere)
                    surfacesCreated += 1
                    print("【调试】为单原子\(residueKey)创建了球体表示")
                }
            }
            
            print("【调试】总结：创建了\(surfacesCreated)个残基/元素表面")
            
            // 整体缩放表面模型
            surfaceEntity.scale = [0.92, 0.92, 0.92]
            print("【调试】表面模型整体缩放为0.92")
            
            // 检查表面实体是否包含任何子实体
            if surfaceEntity.children.isEmpty {
                print("【调试】警告：表面实体没有任何子实体！创建表面模型失败。")
                // 添加一个默认的球体
                let defaultSphere = ModelEntity(mesh: .generateSphere(radius: 0.05))
                defaultSphere.model?.materials = [defaultMaterial]
                surfaceEntity.addChild(defaultSphere)
                print("【调试】添加了一个默认球体作为占位符")
                        } else {
                print("【调试】表面实体包含\(surfaceEntity.children.count)个子实体")
            }
            
            // 添加到场景
            atomsEntity.addChild(surfaceEntity)
            print("【调试】将表面实体添加到atomsEntity")
            
            // 确保表面模型可见
            surfaceEntity.isEnabled = true
            print("【调试】已启用表面模型可见性")
            
        } catch {
            print("【调试】表面模型创建过程中出现异常: \(error.localizedDescription)")
            // 异常情况下创建一个简单的表面模型
            createFallbackSurface()
        }
    }
    
    // 为单个残基创建优化的连续表面 - 放宽条件，更适合残基
    private func createResidueSimplifiedSurface(atoms: [AtomData], material: PhysicallyBasedMaterial, residueName: String) -> ModelEntity? {
        print("【调试-残基表面】为\(residueName)创建连续表面，含\(atoms.count)个原子")
        
        // 放宽条件：只要有2个以上原子就创建
        if atoms.count < 2 {
            print("【调试-残基表面】\(residueName)原子数不足")
            return nil
        }
        
        // 创建残基表面实体
        let residueSurface = ModelEntity()
        residueSurface.name = "residue_surface_\(residueName)"
        
        // 步骤1: 创建基础表面 - 每个原子创建较大的球体
        var atomSpheres: [ModelEntity] = []
        let sphereScale: Float = 1.6 // 增大球体半径使其重叠
        
        for atom in atoms {
            let element = atom.element
            let radius = getAtomRadius(for: element) * sphereScale
            
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius))
            sphere.position = atom.position
            sphere.model?.materials = [material]
            atomSpheres.append(sphere)
            residueSurface.addChild(sphere)
        }
        
        // 步骤2: 添加原子间连接，使表面更连续
        if atoms.count >= 2 {
            // 查找应该连接的原子对
            var connectionsMade = 0
            for i in 0..<atoms.count {
                for j in (i+1)..<atoms.count {
                    let atom1 = atoms[i]
                    let atom2 = atoms[j]
                    let distance = length(atom1.position - atom2.position)
                    
                    // 放宽连接条件，允许更远的连接
                    if distance < 0.25 { // 从0.15增加到0.25
                        // 创建连接
                        let midPoint = (atom1.position + atom2.position) / 2
                        let direction = normalize(atom2.position - atom1.position)
                        
                        // 使用更粗的连接体
                        let connectionRadius: Float = 0.045 // 增加半径，确保使用Float类型
                        let connection = ModelEntity(mesh: .generateCylinder(height: distance * 0.95, radius: connectionRadius))
                        connection.position = midPoint
                        
                        // 设置旋转
                        if abs(direction.y) > 0.999 {
                            connection.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
                        } else {
                            let rotationAxis = normalize(cross([0, 1, 0], direction))
                            let rotationAngle = acos(dot([0, 1, 0], direction))
                            connection.orientation = simd_quatf(angle: rotationAngle, axis: rotationAxis)
                        }
                        
                        connection.model?.materials = [material]
                        residueSurface.addChild(connection)
                        connectionsMade += 1
                    }
                }
            }
            
            print("【调试-残基表面】\(residueName)创建了\(connectionsMade)个原子连接")
        }
        
        return residueSurface
    }
    
    // 创建残基的备选表示 - 当无法创建连续表面时使用
    private func createFallbackResidueBlob(atoms: [AtomData], material: PhysicallyBasedMaterial) -> ModelEntity {
        let blob = ModelEntity()
        blob.name = "fallback_blob"
        
        // 使用更大的重叠球体
        for atom in atoms {
            let element = atom.element
            let radius = getAtomRadius(for: element) * 2.5 // 使用非常大的半径
            
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius))
            sphere.position = atom.position
            sphere.model?.materials = [material]
            blob.addChild(sphere)
        }
        
        return blob
    }
    
    // 添加失败时的备选表面
    private func createFallbackSurface() {
        print("【调试】创建备选表面模型")
        
        let surfaceEntity = ModelEntity()
        surfaceEntity.name = "fallback_surface"
        
        // 创建一个简单的材质
        var defaultMaterial = PhysicallyBasedMaterial()
        defaultMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: UIColor.gray.withAlphaComponent(0.7))
        defaultMaterial.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.2)
        defaultMaterial.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)
        defaultMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        
        // 创建一个简单的球体
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.1))
        sphere.model?.materials = [defaultMaterial]
        surfaceEntity.addChild(sphere)
        
        // 添加到场景
        atomsEntity.addChild(surfaceEntity)
        surfaceEntity.isEnabled = true
        
        print("【调试】创建了备选表面模型")
    }
    
    // 重写合并球体表面创建方法，超简化版
    private func createMergedSpheresSurface(atoms: [AtomData], material: PhysicallyBasedMaterial) -> ModelEntity {
        print("【调试-合并球体】使用超简化版合并球体方法")
        
        let parentEntity = ModelEntity()
        parentEntity.name = "simplified_merged_spheres"
        
        // 计时开始
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 使用较小的球体
        let scaleFactor: Float = 0.6
        
        // 预先创建网格资源以复用
        let defaultRadius: Float = 0.03 * scaleFactor
        let sphereMesh = MeshResource.generateSphere(radius: defaultRadius)
        
        // 限制处理的原子数量
        let maxAtoms = min(300, atoms.count)
        let atomsToProcess = Array(atoms.prefix(maxAtoms))
        
        print("【调试-合并球体】处理\(atomsToProcess.count)/\(atoms.count)个原子")
        
        // 创建基本原子球体
        for atom in atomsToProcess {
            let sphere = ModelEntity(mesh: sphereMesh)
            sphere.position = atom.position
            sphere.model?.materials = [material]
            parentEntity.addChild(sphere)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        print("【调试-合并球体】创建了\(atomsToProcess.count)个球体，用时\(endTime - startTime)秒")
        
        return parentEntity
    }
    
    // 辅助函数 - 获取元素的颜色作为UIColor
    private func getElementColor(_ element: String) -> UIColor {
        // 根据元素类型返回合适的颜色
        let uppercaseElement = element.uppercased()
        switch uppercaseElement {
        case "C": return UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)  // 碳 - 灰色
        case "N": return UIColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1.0)  // 氮 - 蓝色
        case "O": return UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0)  // 氧 - 红色
        case "H": return UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)  // 氢 - 白色
        case "S": return UIColor(red: 0.9, green: 0.9, blue: 0.0, alpha: 1.0)  // 硫 - 黄色
        case "P": return UIColor(red: 0.9, green: 0.5, blue: 0.0, alpha: 1.0)  // 磷 - 橙色
        default: return UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)   // 默认 - 浅灰色
        }
    }
    
    // 辅助函数 - 混合两种颜色
    private func blendColors(_ color1: UIColor, _ color2: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        return UIColor(red: (r1 + r2) / 2, 
                      green: (g1 + g2) / 2, 
                      blue: (b1 + b2) / 2, 
                      alpha: (a1 + a2) / 2)
    }
    
    // 分子信息
    @Published var pdbInfo: PDBInfo? = nil
    
    // MARK: - 原子颜色修改
    
    // 存储已修改颜色的原子信息
    private var modifiedAtomColors: [Int: UIColor] = [:]
    
    // 改变原子颜色的方法
    func changeAtomColor(at index: Int, to color: UIColor) async {
        print("ProteinViewer: 改变原子颜色，索引: \(index)")
        
        // 检查索引有效性
        guard index >= 0 && index < atomsData.count else {
            print("ProteinViewer: 错误 - 原子索引超出范围: \(index)")
            return
        }
        
        // 获取原子实体
        guard let atomEntity = atomEntityMap[index] as? ModelEntity else {
            print("ProteinViewer: 错误 - 找不到原子实体，索引: \(index)")
            return
        }
        
        // 如果是第一次修改这个原子的颜色，保存原始颜色信息
        if modifiedAtomColors[index] == nil {
            // 保存修改记录，但这里我们只记录被修改的事实，而不需要保存原色（因为重置时会用元素默认色）
            modifiedAtomColors[index] = color
        } else {
            // 已经修改过，更新记录
            modifiedAtomColors[index] = color
        }
        
        // 创建新材质，使用与createRealityKitModel方法相同的设置
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .init(floatLiteral: 0.5)  // 增加粗糙度
        material.metallic = .init(floatLiteral: 0.05)  // 大幅降低金属感
        
        // 应用新材质
        atomEntity.model?.materials = [material]
        
        print("ProteinViewer: 成功更改原子颜色，索引: \(index)")
    }
    
    // 重置指定原子到其元素默认颜色
    private func resetAtomToDefaultColor(at index: Int) {
        print("重置原子颜色，索引: \(index)")
        
        guard index >= 0 && index < atomsData.count,
              let atomEntity = atomEntityMap[index] as? ModelEntity else {
            print("无法重置原子颜色，索引无效或实体不存在: \(index)")
            return
        }
        
        // 获取原子元素
        let element = atomsData[index].element.uppercased()
        
        // 从Constants中获取元素默认颜色
        let colorRGBA = Constants.atomColors[element] ?? SIMD4<Float>(0.8, 0.8, 0.8, 1.0) // 默认灰色
        
        // 创建UIColor
        let defaultColor = UIColor(
            red: CGFloat(colorRGBA.x),
            green: CGFloat(colorRGBA.y),
            blue: CGFloat(colorRGBA.z),
            alpha: CGFloat(colorRGBA.w)
        )
        
        // 创建新材质，使用与createRealityKitModel方法相同的设置
        var material = SimpleMaterial()
        material.color = .init(tint: defaultColor)
        material.roughness = .init(floatLiteral: 0.5)  // 增加粗糙度
        material.metallic = .init(floatLiteral: 0.05)  // 大幅降低金属感
        
        // 应用默认材质
        atomEntity.model?.materials = [material]
        
        print("成功重置原子颜色，索引: \(index)")
    }
    
    // 恢复所有修改过颜色的原子到默认颜色
    private func resetAllModifiedAtomColors() {
        print("开始重置所有修改过的原子颜色，总共\(modifiedAtomColors.count)个原子需要重置")
        
        if modifiedAtomColors.isEmpty {
            print("没有需要重置的原子颜色")
            return
        }
        
        for index in modifiedAtomColors.keys {
            print("重置原子颜色: \(index)")
            resetAtomToDefaultColor(at: index)
        }
        
        // 清空修改记录
        modifiedAtomColors.removeAll()
        print("所有原子颜色已重置完成")
        
        // 强制刷新视图
        objectWillChange.send()
    }
    
    // 将所有原子的颜色修改为指定颜色
    @MainActor
    func changeAllAtomsColor(to color: UIColor) async {
        print("将所有原子的颜色修改为: \(color)")
        
        for index in 0..<atomsData.count {
            if let atomEntity = atomEntityMap[index] as? ModelEntity {
                // 创建新材质
                var material = SimpleMaterial()
                material.color = .init(tint: color)
                material.roughness = .init(floatLiteral: 0.5)
                material.metallic = .init(floatLiteral: 0.05)
                
                // 应用材质
                atomEntity.model?.materials = [material]
            }
        }
        
        // 发送变更通知
        objectWillChange.send()
        
        print("已将所有原子颜色修改为新颜色")
    }

    // 为测量功能添加一个新的可视化方法
    private func addVisualMeasurementLine() {
        guard measurementPoints.count == 2,
              let atom1 = atomEntityMap[measurementPoints[0]],
              let atom2 = atomEntityMap[measurementPoints[1]] else {
            print("测量点不足或无法找到对应原子")
            return
        }
        
        let start = atom1.position
        let end = atom2.position
        let midpoint = (start + end) / 2
        let direction = normalize(end - start)
        let distance = length(end - start)
        
        print("创建测量线: 起点=\(start), 终点=\(end), 距离=\(distance)")
        
        // 创建更高级的测量线效果 - 显著增大尺寸
        
        // 1. 创建主线 - 使用更大半径和更亮颜色
        let lineRadius = Constants.measurementLineRadius * 3.0  // 显著增大线条半径
        let line = ModelEntity(mesh: .generateCylinder(height: distance, radius: lineRadius))
        line.position = midpoint
        
        // 设置旋转
        if abs(direction.y) > 0.99 {
            line.orientation = simd_quatf(angle: direction.y > 0 ? 0 : .pi, axis: [1, 0, 0])
        } else {
            let rotationAxis = cross(SIMD3<Float>(0, 1, 0), direction)
            let rotationAngle = acos(direction.y)
            line.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
        }
        
        // 创建更亮的发光材质 - 使用标准材质而非物理材质
        let material = SimpleMaterial(
            color: .red,
            roughness: 0.1,
            isMetallic: true
        )
        line.model?.materials = [material]
        
        // 2. 创建端点球体 - 增大尺寸
        let endpointRadius = lineRadius * 2.5  // 显著增大端点球体
        
        let startSphere = ModelEntity(mesh: .generateSphere(radius: endpointRadius))
        startSphere.position = start
        startSphere.model?.materials = [material]
        
        let endSphere = ModelEntity(mesh: .generateSphere(radius: endpointRadius))
        endSphere.position = end
        endSphere.model?.materials = [material]
        
        // 3. 简化动画效果，使用稳定的高亮显示
        // 创建一个稳定的增强视觉效果，而非动画
        
        // 4. 创建更大的距离标签
        let distanceText = "\(String(format: "%.2f", distance))Å"
        createEnhancedDistanceLabel(at: midpoint, text: distanceText, direction: direction)
        
        // 将所有实体添加到场景 - 先清除现有的测量线
        for existingLine in measurementLines {
            existingLine.removeFromParent()
        }
        measurementLines.removeAll()
        
        // 添加新的测量线元素
        measurementLines.append(line)
        measurementLines.append(startSphere)
        measurementLines.append(endSphere)
        
        rootEntity?.addChild(line)
        rootEntity?.addChild(startSphere)
        rootEntity?.addChild(endSphere)
        
        print("创建高级测量线完成，连接原子 \(measurementPoints[0]) 和 \(measurementPoints[1])，距离: \(distance)Å")
        
        // 发送更新通知
        objectWillChange.send()
    }

    // 增强版距离标签创建方法
    private func createEnhancedDistanceLabel(at position: SIMD3<Float>, text: String, direction: SIMD3<Float>) {
        // 在距离标签位置的显著偏移，确保标签不会被线挡住
        let labelOffset = SIMD3<Float>(0, 0.1, 0)  // 增大偏移
        let labelPos = position + labelOffset
        
        // 创建一个更大的文本实体
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.003,  // 增加厚度
            font: .systemFont(ofSize: 0.15),  // 增大字体尺寸
            containerFrame: CGRect(x: -0.2, y: -0.1, width: 0.4, height: 0.2),  // 增大容器
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        let textEntity = ModelEntity(mesh: mesh)
        
        // 设置高亮材质 - 使用鲜艳颜色
        let material = SimpleMaterial(
            color: .yellow,  // 改为黄色，更容易看到
            roughness: 0.1,
            isMetallic: true
        )
        textEntity.model?.materials = [material]
        
        // 设置位置和比例 - 适当放大
        textEntity.position = labelPos
        textEntity.scale = [1.5, 1.5, 1.5]  // 整体放大1.5倍
        
        // 确保文本始终朝向观察者
        let upVector = SIMD3<Float>(0, 1, 0)
        let rightVector = normalize(cross(direction, upVector))
        
        // 仅当我们有一个有效的右向量时才设置方向
        if length(rightVector) > 0.001 {
            let billboardRotation = simd_quatf(from: [0, 0, 1], to: rightVector)
            textEntity.orientation = billboardRotation
        }
        
        // 添加到场景
        measurementLines.append(textEntity)
        rootEntity?.addChild(textEntity)
    }
}

// MARK: - String Extensions
extension String {
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }
}

