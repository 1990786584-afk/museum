import SafariServices
import SwiftUI
import WebKit

/// Native SwiftUI museum entrance. The two *exhibitions* use their
/// original web renderers inside WKWebView, never in external Safari.
/// This is an iPhone app, not a PWA shortcut or a website home screen.
private enum MuseumExhibit: Equatable {
    case sky
    case datesDemo

    var url: URL {
        switch self {
        case .sky:
            return URL(string: "https://1990786584-afk.github.io/museum/gallery/")!
        case .datesDemo:
            return URL(string: "https://1990786584-afk.github.io/museum/dates/")!
        }
    }
}

struct MuseumHomeView: View {
    @EnvironmentObject private var host: HostState
    @StateObject private var browser = MuseumBrowserHolder()
    @State private var exhibit: MuseumExhibit?
    @State private var showConnection = false
    @State private var showLocation = false
    @State private var galleryNotice = ""
    @State private var isInsideExhibit = false

    var body: some View {
        ZStack {
            if let exhibit {
                // A real native header occupies its own vertical space; the
                // web renderer never starts underneath our back button.
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            self.exhibit = nil
                        } label: {
                            Label("纪念馆", systemImage: "chevron.left")
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 13)
                                .frame(height: 40)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("museum-native-back")
                        .buttonStyle(.plain)

                        Spacer(minLength: 8)

                        if exhibit == .datesDemo {
                            // Keep Ephemera's demo fast-forward working, but
                            // place its control in our dedicated native bar.
                            Button {
                                browser.advanceDemo()
                            } label: {
                                Label("试玩 · 快进", systemImage: "forward.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .accessibilityLabel("试玩：推进到下一个约会阶段")
                            .accessibilityIdentifier("museum-demo-next")
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.23))
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Color(red: 0.985, green: 0.965, blue: 0.937))

                    MuseumBrowser(holder: browser, insideExhibit: $isInsideExhibit,
                                  config: host.config, startURL: exhibit.url,
                                  onOpenLiveDates: {
                        guard host.config.isConfigured else { return false }
                        host.open(route: nil)
                        return true
                    }, onOpenBox: { id in
                        guard host.config.isConfigured else { return false }
                        host.open(route: ["page": "box", "planId": id])
                        return true
                    }, onGalleryError: { reason in
                        galleryNotice = reason
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // The exhibit's own tab bar must reach the home-indicator
                // edge, not stop above a white system-safe-area strip.
                .ignoresSafeArea(edges: .bottom)
            } else {
                NativeMuseumEntrance(
                    openSky: { exhibit = .sky },
                    openDates: {
                        if host.config.isConfigured {
                            host.open(route: nil)
                        } else {
                            exhibit = .datesDemo
                        }
                    },
                    openLocation: { showLocation = true },
                    openSettings: { showConnection = true }
                )
            }
        }
        .background {
            // The painted sky fills the entire screen, including the bottom
            // home-indicator inset. The Ephemera demo uses its paper colour.
            if exhibit == .datesDemo {
                Color(red: 0.985, green: 0.965, blue: 0.937)
                    .ignoresSafeArea()
            } else {
                GeometryReader { size in
                    Image("MuseumSky")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.size.width, height: size.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            }
        }
        .alert("纪念馆", isPresented: Binding(
            get: { !galleryNotice.isEmpty },
            set: { if !$0 { galleryNotice = "" } }
        )) {
            Button("知道了") { galleryNotice = "" }
        } message: {
            Text(galleryNotice)
        }
        .onChange(of: host.pageOpen) { _, isOpen in
            if !isOpen { browser.refreshPrivateGallery?() }
        }
        .onChange(of: host.config.isConfigured) { _, connected in
            guard !connected else { return }
            exhibit = nil
            browser.webView?.configuration.websiteDataStore.httpCookieStore
                .getAllCookies { cookies in
                    guard let webView = browser.webView else { return }
                    let store = webView.configuration.websiteDataStore.httpCookieStore
                    for cookie in cookies where cookie.name == "museum_sid" {
                        store.delete(cookie)
                    }
                }
        }
        .sheet(isPresented: $showConnection) {
            PrivateDatesSettings().environmentObject(host)
        }
        .sheet(isPresented: $showLocation) {
            MuseumLocationView()
        }
        .fullScreenCover(isPresented: $host.pageOpen) {
            // Original Ephemera invitation, wax seal, and ticket renderer.
            EphemeraPage(config: host.config, route: host.pendingRoute)
                .ignoresSafeArea()
        }
    }
}

/// The original Shelf & Ephemera images and paper texture are native app
/// resources. Their fonts, layout and animations inside the exhibitions are
/// never overwritten. No web address is opened by the home buttons.
private struct NativeMuseumEntrance: View {
    let openSky: () -> Void
    let openDates: () -> Void
    let openLocation: () -> Void
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
                    VStack(spacing: 23) {
                        HStack {
                            Button(action: openLocation) {
                                Label("附近的信", systemImage: "location")
                                    .font(.system(size: 13))
                            }
                            .accessibilityIdentifier("native-location")
                            Spacer()
                            Button(action: openSettings) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 18))
                                    .frame(width: 35, height: 34)
                            }
                            .accessibilityLabel("私人纪念馆设置")
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 7) {
                            Text("ZFxF · since December 14, 2024")
                                .font(.custom("Georgia-Italic", size: 14))
                                .tracking(1)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                            Text("The Museum of Us")
                                .font(.custom("Georgia-Italic", size: 36))
                                .minimumScaleFactor(0.68)
                                .lineLimit(1)
                                .padding(.vertical, 6)
                            Text("我们的私人纪念馆")
                                .font(.system(size: 14, design: .serif))
                                .tracking(4)
                        }
                        .padding(.bottom, 5)

                        HStack(alignment: .top, spacing: 12) {
                            ExhibitCard(
                                image: "MuseumPortrait",
                                title: "Shelf in the Sky",
                                caption: "云里的照片 · 拿起、翻面、漫游",
                                action: openSky
                            )
                            ExhibitCard(
                                image: "MuseumEnvelope",
                                title: "Ephemera",
                                caption: "约会的纸品 · 信封、票根、纪念盒",
                                action: openDates
                            )
                        }

                        Text("Zoey & Finnian · our little museum")
                            .font(.custom("Georgia-Italic", size: 16))
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                            .padding(.top, 8)
                    }
                    .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.23))
                    .padding(.horizontal, 19)
                    .padding(.top, 17)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 720)
                    .background {
                        Image("MuseumPaper")
                            .resizable(resizingMode: .tile)
                            .overlay {
                                Rectangle()
                                    .strokeBorder(Color(red: 0.67, green: 0.60, blue: 0.48),
                                                  lineWidth: 0.8)
                            }
                    }
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                    .padding(.bottom, 35)
                    .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ExhibitCard: View {
    let image: String
    let title: String
    let caption: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                GeometryReader { geo in
                    Image(image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay {
                            Rectangle().strokeBorder(.black.opacity(0.12), lineWidth: 0.6)
                        }
                }
                .aspectRatio(0.81, contentMode: .fit)

                Text(title)
                    .font(.custom("Georgia-Italic", size: 24))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    // Reserve exactly two title lines on both cards, even
                    // when Ephemera needs only one. Captions then align.
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)

                Text(caption)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            }
            .padding(8)
            .background(Color(red: 0.99, green: 0.97, blue: 0.91).opacity(0.63))
            .overlay {
                Rectangle().strokeBorder(Color(red: 0.68, green: 0.62, blue: 0.54), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + "，" + caption)
        .accessibilityIdentifier(image == "MuseumPortrait" ? "native-sky" : "native-dates")
    }
}

/// The museum is a public *sample* until private services are configured.
/// No location, photo-library or tracking permissions are requested.
final class MuseumBrowserHolder: ObservableObject {
    static let home = URL(string: "https://1990786584-afk.github.io/museum/")!
    weak var webView: WKWebView?
    var refreshPrivateGallery: (() -> Void)?

    func goHome() {
        webView?.load(URLRequest(url: Self.home, cachePolicy: .useProtocolCachePolicy))
    }

    /// Ephemera's upstream demo still owns all state and advance logic.
    /// The iOS button simply invokes its existing testID press handler.
    func advanceDemo() {
        guard let webView,
              webView.url?.path.hasPrefix("/museum/dates/") == true else { return }
        webView.evaluateJavaScript("""
          (() => {
            const button = document.querySelector('[data-testid="demo-step"]');
            if (!button) return false;
            button.click();
            return true;
          })()
          """) { _, _ in }
    }
}

private struct MuseumBrowser: UIViewRepresentable {
    let holder: MuseumBrowserHolder
    @Binding var insideExhibit: Bool
    let config: HostConfig
    let startURL: URL
    let onOpenLiveDates: () -> Bool
    let onOpenBox: (Int) -> Bool
    let onGalleryError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if startURL.path == "/museum/dates/" {
            // The demo's own floating pill overlaps page headings on iPhone.
            // Hide only that test control, without changing the upstream
            // design or its JS fast-forward handler (see advanceDemo()).
            let script = WKUserScript(source: """
                (() => {
                  const style = document.createElement('style');
                  style.textContent = '[data-testid="demo-step"] { visibility: hidden !important; }';
                  (document.head || document.documentElement).appendChild(style);
                })();
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
        }
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
        holder.refreshPrivateGallery = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator, let current = view.url,
                  coordinator.isPrivateGallery(current) else { return }
            coordinator.preparePrivateGallery(in: view)
        }
        if startURL.path == "/museum/gallery/" && config.isConfigured {
            context.coordinator.preparePrivateGallery(in: view)
        } else {
            view.load(URLRequest(url: startURL))
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MuseumBrowser
        init(parent: MuseumBrowser) { self.parent = parent }

        func isPrivateGallery(_ url: URL) -> Bool {
            guard let target = parent.config.galleryURL,
                  url.scheme == "https",
                  url.host?.lowercased() == target.host?.lowercased(),
                  url.port == target.port else { return false }
            return url.path.hasPrefix(target.path)
        }

        private func isMuseumPage(_ url: URL) -> Bool {
            url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == MuseumBrowserHolder.home.host
            && (url.path == "/museum" || url.path.hasPrefix("/museum/"))
        }

        private func updateLocation(_ webView: WKWebView) {
            guard let url = webView.url else { return }
            let within = (isMuseumPage(url) && url.path != "/museum/") || isPrivateGallery(url)
            DispatchQueue.main.async { self.parent.insideExhibit = within }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow) // third-party image/font subresources, no native bridge here
                return
            }
            if url.scheme == "zfxf-box" {
                decisionHandler(.cancel)
                // Only a link from our authenticated gallery may navigate
                // to a private box; never trust a public page's deep link.
                if let source = webView.url, isPrivateGallery(source),
                   url.host == "open",
                   let id = Int(url.path.dropFirst()), id > 0 {
                    _ = parent.onOpenBox(id)
                }
                return
            }
            if isMuseumPage(url) {
                if url.path == "/museum/dates/" && parent.onOpenLiveDates() {
                    decisionHandler(.cancel)
                } else if url.path == "/museum/gallery/" && parent.config.isConfigured {
                    decisionHandler(.cancel)
                    preparePrivateGallery(in: webView)
                } else {
                    decisionHandler(.allow)
                }
                return
            }
            if isPrivateGallery(url) {
                decisionHandler(.allow)
                return
            }
            if ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            // External links are never opened automatically in Safari.
            // The museum stays inside its native iOS window.
        }

        /// The private server's JSON sync and cookie handshake are intentionally
        /// separate. WKWebView never receives the her bearer token or its
        /// Authorization header; it only receives a one-hour HttpOnly cookie.
        func preparePrivateGallery(in webView: WKWebView) {
            let cfg = parent.config
            guard let sync = cfg.syncURL, let session = cfg.sessionURL,
                  let gallery = cfg.galleryURL else { return }
            Task { @MainActor [weak webView] in
                guard let webView else { return }
                do {
                    var syncReq = URLRequest(url: sync, timeoutInterval: 120)
                    syncReq.httpMethod = "POST"
                    syncReq.httpBody = Data()
                    syncReq.setValue("Bearer " + cfg.credential, forHTTPHeaderField: "Authorization")
                    let (syncData, syncRes) = try await URLSession.shared.data(for: syncReq)
                    guard (syncRes as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    // Until the first actual date is finished, retain the
                    // original full sample gallery instead of a blank cloud.
                    if let summary = (try? JSONSerialization.jsonObject(with: syncData)) as? [String: Any],
                       (summary["dates"] as? Int) == 0 {
                        if !UserDefaults.standard.bool(forKey: "museum.emptyGalleryExplained") {
                            UserDefaults.standard.set(true, forKey: "museum.emptyGalleryExplained")
                            parent.onGalleryError(
                                "私人纪念馆已经连接，但还没有结束的约会。这里先展示原作者的示例照片；以后约会完成、上传照片，就会自动同步进云里。"
                            )
                        }
                        webView.load(URLRequest(url: URL(string:
                            "https://1990786584-afk.github.io/museum/gallery/")!))
                        return
                    }

                    var sessionReq = URLRequest(url: session, timeoutInterval: 20)
                    sessionReq.httpMethod = "POST"
                    sessionReq.httpBody = Data()
                    sessionReq.setValue("Bearer " + cfg.credential, forHTTPHeaderField: "Authorization")
                    let (_, sessionRes) = try await URLSession.shared.data(for: sessionReq)
                    guard let http = sessionRes as? HTTPURLResponse, http.statusCode == 204 else {
                        throw URLError(.userAuthenticationRequired)
                    }
                    let fields = http.allHeaderFields.reduce(into: [String: String]()) { dict, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            dict[key] = value
                        }
                    }
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: session)
                    guard let cookie = cookies.first(where: { $0.name == "museum_sid" }) else {
                        throw URLError(.badServerResponse)
                    }
                    await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                            resume.resume()
                        }
                    }
                    webView.load(URLRequest(url: gallery, cachePolicy: .reloadIgnoringLocalCacheData))
                } catch {
                    parent.onGalleryError(
                        "私人照片尚未连接成功，先展示原作样本。请检查服务地址及网络；原有照片和约会数据没有被修改。"
                    )
                    webView.load(URLRequest(url: URL(string:
                        "https://1990786584-afk.github.io/museum/gallery/")!))
                }
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
                    if url.path == "/museum/gallery/" && parent.config.isConfigured {
                        preparePrivateGallery(in: webView)
                    } else {
                        webView.load(URLRequest(url: url))
                    }
                } else if isPrivateGallery(url) {
                    webView.load(URLRequest(url: url))
                } else {
                    // Do not launch an external Safari window from the app.
                }
            }
            return nil
        }
    }
}

private struct PrivateDatesSettings: View {
    @EnvironmentObject private var host: HostState
    @Environment(\.dismiss) private var dismiss
    @State private var origin = HostConfig.load().apiBase.isEmpty
        ? "https://memory.ryanecho.xyz/date" : HostConfig.load().apiBase
    @State private var token = HostConfig.load().credential
    @State private var status = ""
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("私人 Ephemera 后端和云端相册同步服务共用一个 HTTPS 地址。配置后，在 Ephemera 存照片，结束的约会会在下次打开云端相册时自动出现；未配置时仍是原作演示数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("私人 Ephemera 服务") {
                    TextField("https://你的域名/date", text: $origin)
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
                            status = "已保存。约会纪念盒与私人云端相册将使用同一份约会数据。"
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
