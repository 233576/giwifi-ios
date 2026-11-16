import SwiftUI
import WebKit

/// 应用内 Portal 网页容器。
///
/// 用它的唯一理由：Safari 会带自己的 UA 出去，服务端按 UA 判设备，
/// 而 GiWiFi 的设备绑定额度有限 —— 网页里认证必须复用 App 的终端档案 UA，
/// 这样服务端看到的还是同一台「Android 平板 / 手机」，不会额外消耗绑定。
struct PortalWebView: View {
    let url: URL
    let userAgent: String
    var onClose: () -> Void = {}

    @StateObject private var model = PortalWebModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PortalWebContainer(webView: model.webView)
                    .ignoresSafeArea(edges: .bottom)
                if model.progress > 0 && model.progress < 1 {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                }
            }
            .navigationTitle(model.title.isEmpty ? "Portal 网页" : model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                        onClose()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            model.webView.goBack()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .disabled(!model.canGoBack)

                        Button {
                            model.webView.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("UA 已固定为当前设备档案，与服务端绑定保持一致")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
        .onAppear {
            model.load(url, userAgent: userAgent)
        }
    }
}

final class PortalWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView

    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var title: String = ""

    private var observations: [NSKeyValueObservation] = []
    private var loaded = false

    override init() {
        let configuration = WKWebViewConfiguration()
        // 持久化 cookie：补完资料 / 网页登录后的会话要留到下次打开
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                let value = view.estimatedProgress
                DispatchQueue.main.async { self?.progress = value }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                let value = view.canGoBack
                DispatchQueue.main.async { self?.canGoBack = value }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                let value = view.title ?? ""
                DispatchQueue.main.async { self?.title = value }
            },
        ]
    }

    func load(_ url: URL, userAgent: String) {
        guard !loaded else { return }
        loaded = true
        webView.customUserAgent = userAgent
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress = 1
        canGoBack = webView.canGoBack
        title = webView.title ?? ""
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        progress = 1
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        progress = 1
    }
}

struct PortalWebContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
