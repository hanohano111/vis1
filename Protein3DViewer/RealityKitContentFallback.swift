//
//  RealityKitContentFallback.swift
//  Protein3DViewer
//
//  Created on 2025/6/18.
//

import Foundation
import RealityKit

// 当无法导入RealityKitContent模块时的备用实现
#if !canImport(RealityKitContent)

public enum RealityKitContent {
    // 提供必要的类型和函数
    public static let realityKitContentBundle = Bundle.main
}

#endif