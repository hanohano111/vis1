import SwiftUI
import UniformTypeIdentifiers

struct ControlPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            // 背景，适配深浅色模式
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // 顶部标题区域
                HStack {
                    Text("蛋白质 3D 查看器")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    if appModel.isLoadingModel {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 20) {
                        // 文件操作按钮区
                        VStack(spacing: 16) {
                            HStack {
                                Button("打开 PDB 文件") {
                                    appModel.showFileImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(appModel.isLoadingModel)

                                Spacer()

                                if appModel.activeProteinModelID != nil {
                                    Button("显示模型窗口") {
                                        openWindow(id: "proteinModel")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            if appModel.activeProteinModelID == nil && !appModel.isLoadingModel {
                                Text("请加载 PDB 文件以显示蛋白质模型")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 10)
                            } else if appModel.activeProteinModelID != nil {
                                Text("✅ 模型已加载，请在模型窗口中查看详细信息")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                    .padding(.top, 10)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                        )
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.vertical)
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
        .alert("错误", isPresented: $appModel.showError) {
            Button("确定") {
                appModel.showError = false
            }
        } message: {
            Text(appModel.errorMessage ?? "未知错误")
        }
        // 自动弹出3D窗口
        .onChange(of: appModel.shouldOpenModelWindow) { _, shouldOpen in
            if shouldOpen && appModel.activeProteinModelID != nil {
                openWindow(id: "proteinModel")
                appModel.shouldOpenModelWindow = false
            }
        }
    }
}

#Preview {
    ControlPanelView()
        .environmentObject(AppModel())
}
