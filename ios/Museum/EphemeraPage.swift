import SwiftUI

/// The date pages as a SwiftUI view: a full-screen web view plus the host's half of the embedding protocol.
/// scenePhase is forwarded as `lifecycle`.
struct EphemeraPage: View {
    let config: HostConfig
    let route: [String: Any]?
    @EnvironmentObject private var host: HostState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var holder = ControllerHolder()

    var body: some View {
        EphemeraPageRepresentable(config: config, route: route, holder: holder, host: host)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: holder.controller?.sendLifecycle("active")
                case .background: holder.controller?.sendLifecycle("background")
                default: break        // .inactive (control center, app switcher peek): nothing to tell
                }
            }
    }
}

final class ControllerHolder: ObservableObject {
    weak var controller: EphemeraViewController?
}

private struct EphemeraPageRepresentable: UIViewControllerRepresentable {
    let config: HostConfig
    let route: [String: Any]?
    let holder: ControllerHolder
    let host: HostState

    func makeUIViewController(context: Context) -> EphemeraViewController {
        let vc = EphemeraViewController(config: config, route: route, host: host)
        holder.controller = vc
        host.pendingRoute = nil
        host.navigateOpenPage = { [weak vc] r in vc?.navigate(r) }
        vc.onClose = { [weak host] in
            host?.navigateOpenPage = nil
            host?.pageOpen = false
        }
        return vc
    }

    func updateUIViewController(_ vc: EphemeraViewController, context: Context) {}
}

// MARK: - Museum companion: free-timing tickets

// The upstream Ephemera renderer intentionally remains untouched. This
// native companion records the REAL tap time for opted-in live dates. A tap
// means the stop was FINISHED, not that a timer should begin.
private struct MuseumFlexibleDateList: Decodable {
    let ok: Bool
    let plans: [MuseumFlexibleDate]
}

private struct MuseumFlexibleDate: Decodable, Identifiable {
    let id: Int
    let title: String
    let stops: [MuseumFlexibleStop]
}

private struct MuseumFlexibleStop: Decodable, Identifiable {
    let id: Int
    let title: String
    let order: Int
    let completedAt: Double?
    let skipped: Bool
}

private enum MuseumFlexibleDateClient {
    static func request(_ config: HostConfig, path: String,
                        body: [String: Int]? = nil) async throws -> Data {
        guard config.isConfigured,
              let url = URL(string: config.apiBase + "/museum-gallery/" + path),
              url.scheme == "https" else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("Bearer " + config.credential, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

struct MuseumFlexibleDateSheet: View {
    let config: HostConfig
    @Environment(\.dismiss) private var dismiss
    @State private var plans: [MuseumFlexibleDate] = []
    @State private var busyStop: Int?
    @State private var loading = true
    @State private var error: String?

    private let ink = Color(red: 0.30, green: 0.28, blue: 0.23)
    private let paper = Color(red: 0.985, green: 0.965, blue: 0.937)

    private func displayTime(_ timestamp: Double) -> String {
        let format = DateFormatter()
        format.timeZone = TimeZone(identifier: "Asia/Shanghai")
        format.dateFormat = "M月d日 HH:mm"
        return format.string(from: Date(timeIntervalSince1970: timestamp))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text("不用赶路，也不必按预定时刻检票。哪一步真正做完了，就点哪一张；时间由服务器按你点下的时刻记录。")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(ink.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)

                    if loading {
                        HStack {
                            Spacer()
                            ProgressView("正在取回我们的约会…")
                            Spacer()
                        }
                        .padding(.top, 25)
                    } else if plans.isEmpty {
                        Text("目前没有启用「随心记录」的进行中约会。")
                            .font(.system(size: 14, design: .serif))
                            .padding(.vertical, 25)
                    }

                    ForEach(plans) { plan in
                        VStack(alignment: .leading, spacing: 15) {
                            Text(plan.title)
                                .font(.custom("Georgia-Italic", size: 23))
                                .foregroundStyle(ink)

                            ForEach(plan.stops) { stop in
                                HStack(alignment: .center, spacing: 12) {
                                    Text(String(format: "%02d", stop.order))
                                        .font(.custom("Georgia", size: 17))
                                        .foregroundStyle(ink.opacity(0.65))
                                        .frame(width: 29)

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(stop.title)
                                            .font(.system(size: 15, design: .serif))
                                            .foregroundStyle(ink)
                                        if let at = stop.completedAt {
                                            Text("已完成 · " + displayTime(at))
                                                .font(.system(size: 12))
                                                .foregroundStyle(ink.opacity(0.6))
                                        } else if stop.skipped {
                                            Text("这一站已跳过")
                                                .font(.system(size: 12))
                                                .foregroundStyle(ink.opacity(0.6))
                                        } else {
                                            Text("还没到也没关系，随时可以完成")
                                                .font(.system(size: 11))
                                                .foregroundStyle(ink.opacity(0.6))
                                        }
                                    }

                                    Spacer(minLength: 4)

                                    if stop.completedAt != nil {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green.opacity(0.75))
                                            .accessibilityLabel("已完成")
                                    } else if !stop.skipped {
                                        Button {
                                            Task { await complete(plan: plan.id, stop: stop.id) }
                                        } label: {
                                            if busyStop == stop.id {
                                                ProgressView().tint(ink)
                                            } else {
                                                Text("我完成了")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(ink)
                                        .disabled(busyStop != nil)
                                        .accessibilityIdentifier("museum-free-checkin-\(stop.id)")
                                    }
                                }
                                Divider().overlay(ink.opacity(0.13))
                            }
                        }
                        .padding(18)
                        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("museum-free-error")
                    }

                    Text("可以晚一点、改行程，甚至隔天再完成。没点的站点会一直留着。这里不会替你完成 FinnianOS 里的独立 DDL。")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(ink.opacity(0.68))
                }
                .padding(20)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle("随心记录 · P 人约会")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("返回约会") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
        .presentationDragIndicator(.visible)
    }

    @MainActor private func load() async {
        loading = true
        error = nil
        do {
            let data = try await MuseumFlexibleDateClient.request(config, path: "free-dates")
            let response = try JSONDecoder().decode(MuseumFlexibleDateList.self, from: data)
            plans = response.plans
        } catch {
            self.error = "这次还没同步成功。请检查私人约会服务的连接，再试一次。"
        }
        loading = false
    }

    @MainActor private func complete(plan: Int, stop: Int) async {
        busyStop = stop
        error = nil
        do {
            _ = try await MuseumFlexibleDateClient.request(
                config, path: "free-dates/check-in", body: ["planId": plan, "stopId": stop])
            // Read canonical server marks back; never claim completion on a
            // mere successful button animation or an unverified local time.
            await load()
        } catch {
            self.error = "暂时没有记进去，请重试。原来的票根不会被误标为完成。"
        }
        busyStop = nil
    }
}
