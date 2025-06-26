//
//  ProteinModelData.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import RealityKit
import Foundation

// 模型数据结构
@MainActor
class ProteinModelData: ObservableObject, Identifiable, Codable {
    let id: UUID
    let proteinViewer: ProteinViewer
    
    // 蛋白质分子信息
    @Published var name: String = "未知蛋白质"
    @Published var atomCount: Int = 0
    @Published var molecularWeight: Double = 0.0
    @Published var sequence: String = "未获取序列"
    @Published var pdbData: Data? = nil
    
    init(proteinViewer: ProteinViewer) {
        self.id = UUID()
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
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case atomCount
        case molecularWeight
        case sequence
        case pdbData
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        atomCount = try container.decode(Int.self, forKey: .atomCount)
        molecularWeight = try container.decode(Double.self, forKey: .molecularWeight)
        sequence = try container.decode(String.self, forKey: .sequence)
        pdbData = try container.decodeIfPresent(Data.self, forKey: .pdbData)
        
        // 由于类现在是 @MainActor 隔离的，我们可以直接初始化 ProteinViewer
        proteinViewer = ProteinViewer()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(atomCount, forKey: .atomCount)
        try container.encode(molecularWeight, forKey: .molecularWeight)
        try container.encode(sequence, forKey: .sequence)
        try container.encodeIfPresent(pdbData, forKey: .pdbData)
    }
} 