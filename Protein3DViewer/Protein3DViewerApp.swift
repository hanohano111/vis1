//
//  Protein3DViewerApp.swift
//  Protein3DViewer
//
//  Created by 123 on 2025/4/16.
//

import SwiftUI
import CompositorServices

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

    var body: some Scene {
        // 主控制面板窗口
        WindowGroup(id: "controlPanel") {
            ControlPanelView()
                .environmentObject(appModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1000, height: 800)// 设置窗口默认大小。
        

        // 3D蛋白质模型窗口 用于展示 3D 蛋白质模型。
        WindowGroup(id: "proteinModel") {
            // 若有值，显示ProteinModelView并传递对应的模型 ID 和appModel环境对象，展示具体的 3D 蛋白质模型。
            if let activeModelID = appModel.activeProteinModelID {
                ProteinModelView(modelID: activeModelID)
                    .environmentObject(appModel)
            } else {
                // 显示一个占位视图，提示用户先打开模型
                Text("请先在控制面板中打开一个PDB文件")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .windowStyle(.volumetric)
        //窗口大小，改下面三个数(改这里！！！）
        .defaultSize(width: 2200, height: 2200, depth: 2000)
        

        // 支持全空间沉浸
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            CompositorLayer(configuration: ContentStageConfiguration()) { @MainActor layerRenderer in
                Renderer.startRenderLoop(layerRenderer, appModel: appModel)
            }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}


