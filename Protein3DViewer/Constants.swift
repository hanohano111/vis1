import Foundation
import SwiftUI
import RealityKit

/// 存储应用程序常量的结构体
struct Constants {
    /// 元素 => 半径 映射
    static let vanDerWaalsRadii: [String: Float] = [
        "H": 0.12, // 氢
        "C": 0.17, // 碳
        "N": 0.155, // 氮
        "O": 0.152, // 氧
        "S": 0.18,  // 硫
        "P": 0.18,  // 磷
        "F": 0.147, // 氟
        "CL": 0.175, // 氯
        "BR": 0.185, // 溴
        "I": 0.198,  // 碘
        "NA": 0.227, // 钠
        "MG": 0.173, // 镁
        "K": 0.275,  // 钾
        "CA": 0.231, // 钙
        "FE": 0.126, // 铁
        "ZN": 0.139, // 锌
        "SE": 0.19,  // 硒
        "MN": 0.13,  // 锰
        "NI": 0.124, // 镍
        "CO": 0.125, // 钴
        "CU": 0.128  // 铜
    ]
    
    /// 残基 => 颜色 映射 (RGBA)
    static let residueColors: [String: SIMD4<Float>] = [
        // 疏水性残基 - 白色系列
        "ALA": SIMD4<Float>(0.94, 0.94, 0.94, 1.0), // 丙氨酸
        "VAL": SIMD4<Float>(0.92, 0.92, 0.92, 1.0), // 缬氨酸
        "LEU": SIMD4<Float>(0.90, 0.90, 0.90, 1.0), // 亮氨酸
        "ILE": SIMD4<Float>(0.88, 0.88, 0.88, 1.0), // 异亮氨酸
        "PRO": SIMD4<Float>(0.86, 0.86, 0.86, 1.0), // 脯氨酸
        "PHE": SIMD4<Float>(0.84, 0.84, 0.84, 1.0), // 苯丙氨酸
        "MET": SIMD4<Float>(0.82, 0.82, 0.82, 1.0), // 甲硫氨酸
        "TRP": SIMD4<Float>(0.80, 0.80, 0.80, 1.0), // 色氨酸
        "GLY": SIMD4<Float>(0.96, 0.96, 0.96, 1.0), // 甘氨酸
        
        // 极性残基 - 绿色系列
        "SER": SIMD4<Float>(0.1, 0.9, 0.3, 1.0),  // 丝氨酸
        "THR": SIMD4<Float>(0.1, 0.8, 0.3, 1.0),  // 苏氨酸
        "CYS": SIMD4<Float>(0.1, 0.9, 0.5, 1.0),  // 半胱氨酸
        "ASN": SIMD4<Float>(0.1, 0.8, 0.5, 1.0),  // 天冬酰胺
        "GLN": SIMD4<Float>(0.1, 0.7, 0.4, 1.0),  // 谷氨酰胺
        "TYR": SIMD4<Float>(0.1, 0.7, 0.6, 1.0),  // 酪氨酸
        
        // 酸性残基 - 红色系列
        "ASP": SIMD4<Float>(1.0, 0.1, 0.1, 1.0),  // 天冬氨酸
        "GLU": SIMD4<Float>(1.0, 0.2, 0.2, 1.0),  // 谷氨酸
        
        // 碱性残基 - 蓝色系列
        "LYS": SIMD4<Float>(0.1, 0.4, 1.0, 1.0),  // 赖氨酸
        "ARG": SIMD4<Float>(0.2, 0.5, 1.0, 1.0),  // 精氨酸
        "HIS": SIMD4<Float>(0.3, 0.6, 1.0, 1.0)   // 组氨酸
    ]

    /// 元素 => 颜色 映射 (RGBA)
    static let atomColors: [String: SIMD4<Float>] = [
        "H": SIMD4<Float>(0.9, 0.9, 0.9, 1.0),   // 氢 - 白色
        "C": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),   // 碳 - 灰色
        "N": SIMD4<Float>(0.2, 0.2, 0.8, 1.0),   // 氮 - 蓝色
        "O": SIMD4<Float>(0.9, 0.2, 0.2, 1.0),   // 氧 - 红色
        "S": SIMD4<Float>(0.9, 0.9, 0.0, 1.0),   // 硫 - 黄色
        "P": SIMD4<Float>(0.9, 0.5, 0.0, 1.0),   // 磷 - 橙色
        "F": SIMD4<Float>(0.2, 0.9, 0.2, 1.0),   // 氟 - 绿色
        "CL": SIMD4<Float>(0.1, 0.9, 0.1, 1.0),  // 氯 - 绿色
        "BR": SIMD4<Float>(0.6, 0.1, 0.1, 1.0),  // 溴 - 褐色
        "I": SIMD4<Float>(0.5, 0.0, 0.5, 1.0),   // 碘 - 紫色
        "NA": SIMD4<Float>(0.6, 0.6, 0.9, 1.0),  // 钠 - 淡蓝色
        "MG": SIMD4<Float>(0.5, 0.9, 0.5, 1.0),  // 镁 - 淡绿色
        "K": SIMD4<Float>(0.5, 0.5, 1.0, 1.0),   // 钾 - 淡紫色
        "CA": SIMD4<Float>(0.7, 0.7, 0.7, 1.0),  // 钙 - 浅灰色
        "FE": SIMD4<Float>(0.7, 0.0, 0.0, 1.0),  // 铁 - 深红色
        "ZN": SIMD4<Float>(0.5, 0.5, 0.8, 1.0),  // 锌 - 紫罗兰色
        "SE": SIMD4<Float>(0.6, 0.6, 0.0, 1.0),  // 硒 - 深黄色
        "MN": SIMD4<Float>(0.6, 0.0, 0.6, 1.0),  // 锰 - 紫色
        "NI": SIMD4<Float>(0.0, 0.6, 0.6, 1.0),  // 镍 - 青色
        "CO": SIMD4<Float>(0.0, 0.4, 0.7, 1.0),  // 钴 - 蓝绿色
        "CU": SIMD4<Float>(0.8, 0.4, 0.0, 1.0),  // 铜 - 橙棕色
        "HE": SIMD4<Float>(0.9, 0.9, 0.9, 1.0),  // 氦 - 白色
        "LI": SIMD4<Float>(0.6, 0.0, 0.0, 1.0),  // 锂 - 红色
        "BE": SIMD4<Float>(0.0, 0.6, 0.0, 1.0),  // 铍 - 绿色
        "B": SIMD4<Float>(0.8, 0.6, 0.6, 1.0),   // 硼 - 棕色
        "NE": SIMD4<Float>(0.7, 0.9, 0.9, 1.0),  // 氖 - 青白色
        "AL": SIMD4<Float>(0.8, 0.6, 0.8, 1.0),  // 铝 - 紫红色
        "SI": SIMD4<Float>(0.5, 0.6, 0.8, 1.0),  // 硅 - 蓝灰色
        "AR": SIMD4<Float>(0.8, 0.8, 0.9, 1.0),  // 氩 - 淡蓝色
        "SC": SIMD4<Float>(0.6, 0.6, 0.6, 1.0),  // 钪 - 灰色
        "TI": SIMD4<Float>(0.6, 0.6, 0.7, 1.0),  // 钛 - 灰色
        "V": SIMD4<Float>(0.6, 0.6, 0.7, 1.0),   // 钒 - 灰色
        "CR": SIMD4<Float>(0.5, 0.5, 0.6, 1.0),  // 铬 - 灰色
        "GA": SIMD4<Float>(0.5, 0.5, 0.7, 1.0),  // 镓 - 蓝灰色
        "GE": SIMD4<Float>(0.5, 0.5, 0.6, 1.0),  // 锗 - 灰色
        "AS": SIMD4<Float>(0.6, 0.3, 0.6, 1.0),  // 砷 - 紫色
        "RB": SIMD4<Float>(0.5, 0.5, 1.0, 1.0),  // 铷 - 淡紫色
        "SR": SIMD4<Float>(0.5, 1.0, 0.0, 1.0),  // 锶 - 浅绿色
        "Y": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),   // 钇 - 灰色
        "ZR": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),  // 锆 - 灰色
        "MO": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),  // 钼 - 灰色
        "AG": SIMD4<Float>(0.7, 0.7, 0.7, 1.0),  // 银 - 银色
        "CD": SIMD4<Float>(0.5, 0.5, 0.8, 1.0),  // 镉 - 蓝灰色
        "SN": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),  // 锡 - 灰色
        "SB": SIMD4<Float>(0.6, 0.6, 0.6, 1.0),  // 锑 - 灰色
        "BA": SIMD4<Float>(0.1, 0.7, 0.1, 1.0),  // 钡 - 淡绿色
        "W": SIMD4<Float>(0.5, 0.5, 0.5, 1.0),   // 钨 - 灰色
        "AU": SIMD4<Float>(0.8, 0.8, 0.0, 1.0),  // 金 - 金色
        "HG": SIMD4<Float>(0.6, 0.6, 0.6, 1.0),  // 汞 - 灰色
        "PB": SIMD4<Float>(0.5, 0.5, 0.5, 1.0)   // 铅 - 灰色
    ]
    
    static let defaultScale: Float = 1.0
    static let defaultPosition = SIMD3<Float>(0, 0, 0)
    static let defaultBondThickness: Float = 0.03
    
    /// 测量线的半径，用于绘制原子间的测量连线
    static let measurementLineRadius: Float = 0.03
    
    /// 获取带有阴影效果的3D球体材质
    static func get3DMaterial(color: UIColor, metallic: Float = 0.1, roughness: Float = 0.3, opacity: Float = 1.0) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: metallic)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        if opacity < 0.99 {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        return material
    }
    
    /// 获取原子范德华半径
    static func getVanDerWaalsRadius(for element: String) -> Float {
        let uppercaseElement = element.uppercased()
        return vanDerWaalsRadii[uppercaseElement] ?? 0.15  // 默认半径为0.15
    }
    
    /// 获取更生动的表面模型颜色
    static func getEnhancedSurfaceColor(for element: String) -> UIColor {
        let colorSIMD = atomColors[element.uppercased()] ?? SIMD4<Float>(0.8, 0.8, 0.8, 1.0)
        
        // 增强色彩饱和度和亮度
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        
        let color = UIColor(red: CGFloat(colorSIMD.x), 
                            green: CGFloat(colorSIMD.y), 
                            blue: CGFloat(colorSIMD.z), 
                            alpha: CGFloat(colorSIMD.w))
        
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        // 提高饱和度和亮度以增强视觉效果
        saturation = min(saturation * 1.2, 1.0)
        brightness = min(brightness * 1.15, 1.0)
        
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
} 