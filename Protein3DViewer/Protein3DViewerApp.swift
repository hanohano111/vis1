//
//  Protein3DViewerApp.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import CompositorServices
import UIKit

// 使用条件编译处理RealityKitContent模块导入
#if canImport(RealityKitContent)
import RealityKitContent
#endif

struct ContentStageConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
        configuration.depthFormat = .depth32Float
        configuration.colorFormat = .bgra8Unorm_srgb

        let foveationEnabled = capabilities.supportsFoveation
        configuration.isFoveationEnabled = foveationEnabled

        let options: LayerRenderer.Capabilities.SupportedLayoutsOptions = foveationEnabled ? [.foveationEnabled] : []
        let supportedLayouts = capabilities.supportedLayouts(options: options)

        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
    }
}

@main
struct Protein3DViewerApp: App {
    @StateObject private var appModel = AppModel()
    
    init() {
        // 配置全局窗口行为
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.isOpaque = true
                window.backgroundColor = .clear
                // 禁用窗口虚化效果
                window.alpha = 1.0
            }
        }
    }

    var body: some Scene {
        // 主控制面板窗口
        WindowGroup(id: "controlPanel") {
            ControlPanelView()
                .environmentObject(appModel)
                .frame(width: 600, height: 450)
        }
        .windowStyle(.plain)
        .defaultSize(width: 600, height: 450)
        .windowResizability(.contentSize)

        // 3D蛋白质模型窗口
        WindowGroup(id: "proteinModel") {
            if let activeModelID = appModel.activeProteinModelID {
                ProteinModelView(modelID: activeModelID)
                    .environmentObject(appModel)
            } else {
                Text("请先在控制面板中打开一个PDB文件")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2400, height: 2400, depth: 2200)

        // 支持全空间沉浸
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            CompositorLayer(configuration: ContentStageConfiguration()) { @MainActor layerRenderer in
                Renderer.startRenderLoop(layerRenderer, appModel: appModel)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}


