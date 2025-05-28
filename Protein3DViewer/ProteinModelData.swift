//
//  ProteinModelData.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit

// 模型数据结构
class ProteinModelData: ObservableObject {
    let id: UUID
    let proteinViewer: ProteinViewer
    
    // 蛋白质分子信息
    @Published var name: String = "未知蛋白质"
    @Published var atomCount: Int = 0
    @Published var molecularWeight: Double = 0.0
    @Published var sequence: String = "未获取序列"
    
    init(id: UUID, proteinViewer: ProteinViewer) {
        self.id = id
        self.proteinViewer = proteinViewer
    }
    
    // 更新蛋白质信息
    func updateProteinInfo(name: String? = nil, atomCount: Int? = nil, molecularWeight: Double? = nil, sequence: String? = nil) {
        if let name = name {
            self.name = name
        }
        
        if let atomCount = atomCount {
            self.atomCount = atomCount
        }
        
        if let molecularWeight = molecularWeight {
            self.molecularWeight = molecularWeight
        }
        
        if let sequence = sequence {
            self.sequence = sequence
        }
    }
} 