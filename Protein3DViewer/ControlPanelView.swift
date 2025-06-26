import SwiftUI
import UniformTypeIdentifiers

struct ControlPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            // 背景，适配深浅色模式
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {  // 增加整体间距
                // 顶部标题区域
                HStack {
                    Text("Protein 3D Viewer")
                        .font(.system(size: 40, weight: .bold))  // 增大标题字号
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // 添加显示/隐藏 UI 按钮
                    ZStack {
                        Button(action: {
                            appModel.showUI.toggle()
                        }) {
                            Image(systemName: appModel.showUI ? "eye.fill" : "eye.slash.fill")
                                .font(.system(size: 28))  // 增大图标
                                .foregroundStyle(.primary)
                                .padding(12)  // 增加点击区域
                                .background(
                                    Circle()
                                        .fill(Color(.secondarySystemBackground))
                                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 52, height: 52) // 固定按钮区域大小，防止布局跳动
                    
                    if appModel.isLoadingModel {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.2)  // 增大加载指示器
                            .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 24)  // 增加水平内边距
                .padding(.vertical, 20)  // 增加垂直内边距
                .background(
                    RoundedRectangle(cornerRadius: 24)  // 增大圆角
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
                )
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 24) {  // 增加间距
                        // 文件操作按钮区
                        VStack(spacing: 12) {
                            HStack {
                                Button(action: {
                                    appModel.showCollaborationView = true
                                }) {
                                    Label("Collaboration", systemImage: "person.2.fill")
                                        .font(.system(size: 24))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.bordered)
                               
                                
                                Spacer()
                                
                                if appModel.collaborationManager?.isConnected == true {
                                    Button(action: {
                                        appModel.collaborationManager?.leaveSession()
                                    }) {
                                        Label("Leave Collaboration", systemImage: "xmark.circle.fill")
                                            .font(.system(size: 24))
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                            HStack {
                                Button("Open PDB File") {
                                    appModel.showFileImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                                .font(.system(size: 24))  // 减小字号
                                .padding(.vertical, 8)  // 减小垂直内边距
                                .padding(.horizontal, 16)  // 减小水平内边距
                                .disabled(appModel.isLoadingModel)

                                Spacer()

                                if appModel.activeProteinModelID != nil {
                                    Button("Refresh Window") {
                                        // 关闭已存在的窗口
                                        dismissWindow(id: "proteinModel")
                                        // 打开新的窗口
                                        openWindow(id: "proteinModel")
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 24))  // 减小字号
                                    .padding(.vertical, 8)  // 减小垂直内边距
                                    .padding(.horizontal, 16)  // 减小水平内边距
                                }
                            }
                        }
                        .padding()
                        .padding(.top, 32)  // 保持顶部间距
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        )
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                
                Spacer()
            }
            .padding(.vertical, 16)

            // 悬浮底部的提示区
            VStack {
                if appModel.activeProteinModelID == nil && !appModel.isLoadingModel {
                    Text("Please load a PDB file to display the protein model")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if appModel.showSuccessMessage {
                    Text("✅ Model loaded. Please check details in the model window.")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .opacity(appModel.showSuccessMessage ? 1 : 0)
                        .animation(.easeOut(duration: 1.5), value: appModel.showSuccessMessage)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 5)
            )
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxHeight: .infinity, alignment: .bottom) // 关键：始终在底部
        }
        .glassBackgroundEffect() // 应用玻璃效果到整个 ZStack
        // 文件导入器
        .fileImporter(
            isPresented: $appModel.showFileImporter,
            allowedContentTypes: [.init(filenameExtension: "pdb")!],
            allowsMultipleSelection: false
        ) { result in
            Task {
                do {
                    let urls = try result.get()
                    if let url = urls.first {
                        print("选择了文件: \(url.lastPathComponent)")
                        await appModel.openPDBFile(url: url)
                    }
                } catch {
                    appModel.errorMessage = error.localizedDescription
                    appModel.showError = true
                    print("加载文件错误: \(error.localizedDescription)")
                }
            }
        }
        .alert("Error", isPresented: $appModel.showError) {
            Button("OK") {
                appModel.showError = false
            }
        } message: {
            Text(appModel.errorMessage ?? "Unknown error")
        }
        // Automatically open 3D window
        .onChange(of: appModel.shouldOpenModelWindow) { _, shouldOpen in
            if shouldOpen && appModel.activeProteinModelID != nil {
                openWindow(id: "proteinModel")
                appModel.shouldOpenModelWindow = false
            }
        }
        // Collaboration view
        .sheet(isPresented: $appModel.showCollaborationView) {
            CollaborationView()
        }
    }
}

#Preview {
    ControlPanelView()
        .environmentObject(AppModel())
}

