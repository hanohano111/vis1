//
//  ShaderTypes.swift
//  Protein3DViewer
//

import simd
import Foundation

// 共享的类型定义，避免冲突
enum ShaderTypes {
    // 从ShaderTypes.h导入的枚举
    enum BufferIndex: Int {
        case meshPositions = 0
        case meshGenerics = 1
        case uniforms = 2
    }
    
    enum VertexAttribute: Int {
        case position = 0
        case texcoord = 1
    }
    
    enum TextureIndex: Int {
        case color = 0
    }
    
    // 从ShaderTypes.h导入的Uniforms结构体
    struct Uniforms {
        var projectionMatrix: simd_float4x4
        var modelViewMatrix: simd_float4x4
        
        init(projectionMatrix: simd_float4x4, modelViewMatrix: simd_float4x4) {
            self.projectionMatrix = projectionMatrix
            self.modelViewMatrix = modelViewMatrix
        }
    }
    
    // 从ShaderTypes.h导入的UniformsArray结构体
    struct UniformsArray {
        var uniforms: [Uniforms] // 包含两个Uniforms的数组
        
        init() {
            let identityMatrix = simd_float4x4(1.0)
            uniforms = [Uniforms(projectionMatrix: identityMatrix, modelViewMatrix: identityMatrix),
                        Uniforms(projectionMatrix: identityMatrix, modelViewMatrix: identityMatrix)]
        }
    }
} 