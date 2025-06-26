import SwiftUI
import RealityKit

struct CollaborationView: View {
    @EnvironmentObject var appModel: AppModel
    
    @State private var showJoinAlert = false
    @State private var showHostAlert = false
    @State private var showExitConfirmation = false
    @State private var isConnecting = false
    @State private var showSyncRequest = false
    @State private var syncRequestFrom = ""
    
    var body: some View {
        VStack {
            // 返回按钮
            HStack {
                Button(action: {
                    if appModel.collaborationManager?.isConnected == true {
                        showExitConfirmation = true
                    } else {
                        appModel.showCollaborationView = false
                    }
                }) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                }
                .buttonStyle(.bordered)
                .padding(.leading)
                Spacer()
            }
            // 状态显示
            statusView
            // 控制按钮
            controlButtons
            // 用户列表
            userListView
        }
        .padding()
        .onAppear {
            // 确保协作管理器被初始化
            if appModel.collaborationManager == nil {
                appModel.initializeCollaboration()
            }
        }
        .onDisappear {
            // 如果用户完全退出协作视图，清理协作组件
            if !appModel.collaborationManager!.isConnected {
                appModel.cleanupCollaboration()
            }
        }
        .alert("加入会话", isPresented: $showJoinAlert) {
            Button("确定") {
                isConnecting = true
                appModel.collaborationManager?.joinSession()
            }
            Button("取消", role: .cancel) {
                isConnecting = false
            }
        } message: {
            Text("正在搜索可用的协作会话...")
        }
        .alert("创建会话", isPresented: $showHostAlert) {
            Button("确定") {
                isConnecting = true
                appModel.collaborationManager?.startHosting()
            }
            Button("取消", role: .cancel) {
                isConnecting = false
            }
        } message: {
            Text("将创建一个新的协作会话")
        }
        .alert("退出协作", isPresented: $showExitConfirmation) {
            Button("仅退出界面") {
                appModel.showCollaborationView = false
            }
            Button("离开会话", role: .destructive) {
                appModel.collaborationManager?.leaveSession()
                appModel.showCollaborationView = false
            }
            Button("取消", role: .cancel) {}
        }
        // 同步请求确认对话框
        .alert("同步请求", isPresented: $showSyncRequest) {
            Button("接受") {
                if let peer = appModel.collaborationManager?.connectedPeers.first {
                    appModel.collaborationManager?.handleSyncRequest(from: peer, accept: true)
                }
            }
            Button("拒绝", role: .cancel) {
                if let peer = appModel.collaborationManager?.connectedPeers.first {
                    appModel.collaborationManager?.handleSyncRequest(from: peer, accept: false)
                }
            }
        } message: {
            Text("\(syncRequestFrom) 请求同步当前模型")
        }
        .onChange(of: appModel.collaborationManager?.showSyncRequest) { _, newValue in
            if let newValue = newValue {
                showSyncRequest = newValue
            }
        }
        .onChange(of: appModel.collaborationManager?.syncRequestFrom) { _, newValue in
            if let newValue = newValue {
                syncRequestFrom = newValue
            }
        }
    }
    
    // MARK: - Subviews
    private var statusView: some View {
        HStack {
            Image(systemName: appModel.collaborationManager?.isConnected == true ? "circle.fill" : "circle")
                .foregroundColor(appModel.collaborationManager?.isConnected == true ? .green : .red)
            Text(appModel.collaborationManager?.isConnected == true ? "已连接" : "未连接")
                .foregroundColor(appModel.collaborationManager?.isConnected == true ? .green : .red)
            if let error = appModel.collaborationManager?.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var controlButtons: some View {
        HStack {
            Button(action: {
                showHostAlert = true
            }) {
                Label("创建会话", systemImage: "plus.circle")
            }
            .disabled(appModel.collaborationManager?.isHosting == true || isConnecting)
            Button(action: {
                showJoinAlert = true
            }) {
                Label("加入会话", systemImage: "person.2.circle")
            }
            .disabled(appModel.collaborationManager?.isConnected == true || isConnecting)
            Button(action: {
                appModel.collaborationManager?.leaveSession()
                isConnecting = false
            }) {
                Label("离开会话", systemImage: "xmark.circle")
            }
            .disabled(!(appModel.collaborationManager?.isConnected == true))
            if appModel.collaborationManager?.isConnected == true && appModel.collaborationManager?.isHost == false {
                Button(action: {
                    appModel.collaborationManager?.requestModelSync()
                }) {
                    Label("同步模型", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }
    
    private var userListView: some View {
        List {
            ForEach(appModel.userRepresentation?.connectedUsers.values.map { $0 } ?? [], id: \.id) { user in
                HStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                    Text(user.name)
                    Spacer()
                    Text("在线")
                        .foregroundColor(.green)
                }
            }
        }
    }
} 
