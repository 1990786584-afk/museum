import SafariServices
import SwiftUI
import WebKit

/// The original website draws the museum and the two exhibits.
/// SwiftUI only owns native navigation and the optional private date connection.
struct MuseumHomeView: View {
    @EnvironmentObject private var host: HostState
    @StateObject private var browser = MuseumBrowserHolder()
    @State private var isInsideExhibit = false
    @State private var showConnection = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.91, green: 0.90, blue: 0.86).ignoresSafeArea()
            MuseumBrowser(holder: browser, insideExhibit: $isInsideExhibit,
                          onOpenLiveDates: {
                guard host.config.isConfigured else { return false }
                host.open(route: nil)
                return true
            })
            .ignoresSafeArea(edges: .bottom)

            // Host-only controls. We do not inject CSS, nav bars or custom drawing
            // into the original Shelf in the Sky or Ephemera pages.
            HStack {
                if isInsideExhibit {
                    Button {
                        browser.goHome()
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("返回纪念馆")
                }
                Spacer()
                if !isInsideExhibit {
                    Button {
                        showConnection = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("私人约会服务设置")
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 5)
        }
        .sheet(isPresented: $showConnection) {
            PrivateDatesSettings()
                .environmentObject(host)
        }
        .fullScreenCover(isPresented: $host.pageOpen) {
            // Original upstream native embed: HTML, animations and paper UI are untouched.
            EphemeraPage(config: host.config, route: host.pendingRoute)
                .ignoresSafeArea()
        }
    }
}

/// The museum is a public *sample* until private services are configured.
/// No location, photo-library or tracking permissions are requested.
final class MuseumBrowserHolder: ObservableObject {
    static let home = URL(string: "https://1990786584-afk.github.io/museum/")!
    weak var webView: WKWebView?

    func goHome() {
        webView?.load(URLRequest(url: Self.home, cachePolicy: .useProtocolCachePolicy))
    }
}

private struct MuseumBrowser: UIViewRepresentable {
    let holder: MuseumBrowserHolder
    @Binding var insideExhibit: Bool
    let onOpenLiveDates: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.91, green: 0.90, blue: 0.86, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { view.isInspectable = true }
        #endif
        holder.webView = view
        view.load(URLRequest(url: MuseumBrowserHolder.home))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MuseumBrowser
        init(parent: MuseumBrowser) { self.parent = parent }

        private func isMuseumPage(_ url: URL) -> Bool {
            url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == MuseumBrowserHolder.home.host
            && url.path.hasPrefix("/museum/")
        }

        private func updateLocation(_ webView: WKWebView) {
            guard let url = webView.url else { return }
            let within = isMuseumPage(url) && url.path != "/museum/"
            DispatchQueue.main.async { self.parent.insideExhibit = within }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow) // third-party image/font subresources, no native bridge here
                return
            }
            if isMuseumPage(url) {
                if url.path == "/museum/dates/" && parent.onOpenLiveDates() {
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            if ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            if url.scheme?.lowercased() == "https" {
                UIApplication.shared.open(url)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateLocation(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            // Navigation failure is non-destructive; a home gesture or reload can recover.
            updateLocation(webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if isMuseumPage(url) {
                    webView.load(URLRequest(url: url))
                } else if url.scheme?.lowercased() == "https" {
                    UIApplication.shared.open(url)
                }
            }
            return nil
        }
    }
}

private struct PrivateDatesSettings: View {
    @EnvironmentObject private var host: HostState
    @Environment(\.dismiss) private var dismiss
    @State private var origin = HostConfig.load().apiBase
    @State private var token = HostConfig.load().credential
    @State private var status = ""
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("云端相册与约会纸品目前保留原作者的界面。私人约会服务是可选的，未配置时会打开 Ephemera 原作的互动演示。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("私人 Ephemera 服务") {
                    TextField("https://你的私人服务器域名", text: $origin)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("engine-origin")
                    SecureField("她这一侧的访问口令", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("her-token")
                    Button("保存连接") {
                        if host.saveConnection(origin: origin, credential: token) {
                            status = "已保存到本机。再次点击约会纸品，将打开私人纪念盒。"
                        } else {
                            status = "需要 HTTPS 服务地址和有效口令，检查后再保存。"
                        }
                    }
                    Button(isChecking ? "检查中…" : "测试连接") { checkConnection() }
                        .disabled(isChecking || HostConfig.validateOrigin(origin) == nil || token.isEmpty)
                    if host.config.isConfigured {
                        Button("断开私人连接", role: .destructive) {
                            host.removeConnection()
                            origin = ""
                            token = ""
                            status = "已断开连接并删除设备钥匙串中的访问口令。"
                        }
                    }
                    if !status.isEmpty {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("隐私和通知") {
                    Text("口令只保存在这台 iPhone 的钥匙串；不会写进 GitHub、网页地址、系统日志或普通设置。私人约会仅连接你指定的 HTTPS 服务器。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("允许约会事件通知") {
                        host.requestNotificationPermission()
                        status = "已向系统申请通知权限。"
                    }
                }
            }
            .navigationTitle("纪念馆设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func checkConnection() {
        guard let validated = HostConfig.validateOrigin(origin), !token.isEmpty,
              let url = URL(string: validated + "/api/config") else {
            status = "请检查 HTTPS 地址。"
            return
        }
        isChecking = true
        status = ""
        let bearer = token
        Task {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    status = code == 200 ? "连接成功，可以保存。"
                        : code == 401 || code == 403 ? "口令未通过服务器验证。"
                        : "服务器暂未通过检查（HTTP \(code)）。"
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    status = "暂时无法连接到这台服务器，检查地址或网络。"
                    isChecking = false
                }
            }
        }
    }
}
