import UIKit
import WebKit
import StoreKit
import LocalAuthentication

var webView: WKWebView! = nil

class ViewController: UIViewController, WKNavigationDelegate, UIDocumentInteractionControllerDelegate {
    enum LoadingMode {
        case defaultCachePolicy
        case forceCache
    }

    var documentController: UIDocumentInteractionController?
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var connectionProblemView: UIImageView!
    @IBOutlet weak var webviewView: UIView!
    var toolbarView: UIToolbar!
    
    var htmlIsLoaded = false;
    private var loadingMode = LoadingMode.defaultCachePolicy
    
    private var themeObservation: NSKeyValueObservation?
    var currentWebViewTheme: UIUserInterfaceStyle = .unspecified
    override var preferredStatusBarStyle : UIStatusBarStyle {
        if #available(iOS 13, *), overrideStatusBar{
            if #available(iOS 15, *) {
                return .default
            } else {
                return statusBarTheme == "dark" ? .lightContent : .darkContent
            }
        }
        return .default
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initWebView()
        initToolbarView()
        loadRootUrl()
    
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification , object: nil)
        if #available(iOS 15.0, *) { GenixIAP.shared.startObserving() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        OtelPMS.webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: nil)
    }
    
    @objc func keyboardWillHide(_ notification: NSNotification) {
        OtelPMS.webView.setNeedsLayout()
    }
    
    func initWebView() {
        OtelPMS.webView = createWebView(container: webviewView, WKSMH: self, WKND: self, NSO: self, VC: self)
        webviewView.addSubview(OtelPMS.webView);
        
        OtelPMS.webView.uiDelegate = self;
        
        OtelPMS.webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)

        if(pullToRefresh){
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(refreshWebView(_:)), for: UIControl.Event.valueChanged)
            OtelPMS.webView.scrollView.addSubview(refreshControl)
            OtelPMS.webView.scrollView.bounces = true
        }

        if #available(iOS 15.0, *), adaptiveUIStyle {
            themeObservation = OtelPMS.webView.observe(\.themeColor) { [unowned self] webView, _ in
                let backgroundColor = OtelPMS.webView.underPageBackgroundColor;
                let themeColor = OtelPMS.webView.themeColor;
                currentWebViewTheme = themeColor?.isLight() ?? backgroundColor?.isLight() ?? true ? .light : .dark
                self.overrideUIStyle()
                view.backgroundColor = themeColor ?? backgroundColor;
            }
        }
    }

    @objc func refreshWebView(_ sender: UIRefreshControl) {
        OtelPMS.webView?.reload()
        sender.endRefreshing()
    }

    func createToolbarView() -> UIToolbar{
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 60
        
        #if targetEnvironment(macCatalyst)
        if (statusBarHeight == 0){
            statusBarHeight = 30
        }
        #endif
        
        let toolbarView = UIToolbar(frame: CGRect(x: 0, y: 0, width: webviewView.frame.width, height: 0))
        toolbarView.sizeToFit()
        toolbarView.frame = CGRect(x: 0, y: 0, width: webviewView.frame.width, height: toolbarView.frame.height + statusBarHeight)
//        toolbarView.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin, .flexibleWidth]
        
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let close = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(loadRootUrl))
        toolbarView.setItems([close,flex], animated: true)
        
        toolbarView.isHidden = true
        
        return toolbarView
    }
    
    func overrideUIStyle(toDefault: Bool = false) {
        if #available(iOS 15.0, *), adaptiveUIStyle {
            if (((htmlIsLoaded && !OtelPMS.webView.isHidden) || toDefault) && self.currentWebViewTheme != .unspecified) {
                UIApplication
                    .shared
                    .connectedScenes
                    .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
                    .first { $0.isKeyWindow }?.overrideUserInterfaceStyle = toDefault ? .unspecified : self.currentWebViewTheme;
            }
        }
    }
    
    func initToolbarView() {
        toolbarView =  createToolbarView()
        
        webviewView.addSubview(toolbarView)
    }
    
    @objc func loadRootUrl(cachePolicy: NSURLRequest.CachePolicy = .useProtocolCachePolicy) {
        OtelPMS.webView.load(URLRequest(url: SceneDelegate.universalLinkToLaunch ?? SceneDelegate.shortcutLinkToLaunch ?? rootUrl, cachePolicy: cachePolicy))
    }
    
    func reloadWebview(
        loadingMode: LoadingMode = LoadingMode.defaultCachePolicy
    ) {
        switch loadingMode {
        case LoadingMode.defaultCachePolicy:
            loadRootUrl(cachePolicy: .useProtocolCachePolicy);

        case LoadingMode.forceCache:
            loadRootUrl(cachePolicy: .useProtocolCachePolicy);
        }

        self.loadingMode = loadingMode
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!){
        htmlIsLoaded = true
        
        self.setProgress(1.0, true)
        self.animateConnectionProblem(false)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            OtelPMS.webView.isHidden = false
            self.loadingView.isHidden = true
           
            self.setProgress(0.0, false)
            
            self.overrideUIStyle()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        htmlIsLoaded = false;
        
        if (error as NSError)._code == (-999) { return }
        if (error as NSError)._code == 102 { return }
        
        self.overrideUIStyle(toDefault: true);
        webView.isHidden = true;
        loadingView.isHidden = false;

        if loadingMode == LoadingMode.defaultCachePolicy {
            DispatchQueue.main.async {
                self.reloadWebview(loadingMode: LoadingMode.forceCache)
            }
        } else {
            animateConnectionProblem(true);
            setProgress(0.05, true);
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.setProgress(0.1, true);
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.reloadWebview()
                }
            }
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        if (keyPath == #keyPath(WKWebView.estimatedProgress) &&
                OtelPMS.webView.isLoading &&
                !self.loadingView.isHidden &&
                !self.htmlIsLoaded) {
                    var progress = Float(OtelPMS.webView.estimatedProgress);
                    
                    if (progress >= 0.8) { progress = 1.0; };
                    if (progress >= 0.3) { self.animateConnectionProblem(false); }
                    
                    self.setProgress(progress, true);
        }
    }
    
    func setProgress(_ progress: Float, _ animated: Bool) {
        self.progressView.setProgress(progress, animated: animated);
    }
    
    
    func animateConnectionProblem(_ show: Bool) {
        if (show) {
            self.connectionProblemView.isHidden = false;
            self.connectionProblemView.alpha = 0
            UIView.animate(withDuration: 0.7, delay: 0, options: [.repeat, .autoreverse], animations: {
                self.connectionProblemView.alpha = 1
            })
        }
        else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [], animations: {
                self.connectionProblemView.alpha = 0 // Here you will get the animation you want
            }, completion: { _ in
                self.connectionProblemView.isHidden = true;
                self.connectionProblemView.layer.removeAllAnimations();
            })
        }
    }
        
    deinit {
        OtelPMS.webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}

extension UIColor {
    // Check if the color is light or dark, as defined by the injected lightness threshold.
    // Some people report that 0.7 is best. I suggest to find out for yourself.
    // A nil value is returned if the lightness couldn't be determined.
    func isLight(threshold: Float = 0.5) -> Bool? {
        let originalCGColor = self.cgColor

        // Now we need to convert it to the RGB colorspace. UIColor.white / UIColor.black are greyscale and not RGB.
        // If you don't do this then you will crash when accessing components index 2 below when evaluating greyscale colors.
        let RGBCGColor = originalCGColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        guard let components = RGBCGColor?.components else {
            return nil
        }
        guard components.count >= 3 else {
            return nil
        }

        let brightness = Float(((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000)
        return (brightness > threshold)
    }
}

extension ViewController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "print" {
            printView(webView: OtelPMS.webView)
        }
        if message.name == "push-subscribe" {
            handleSubscribeTouch(message: message)
        }
        if message.name == "push-permission-request" {
            handlePushPermission()
        }
        if message.name == "push-permission-state" {
            handlePushState()
        }
        if message.name == "push-token" {
            handleFCMToken()
        }
        if message.name == "iap" {
            handleIAP(message)
        }
        if message.name == "faceid" {
            handleFaceId(message)
        }
  }
}

// ===== Face ID / Touch ID ile uygulama kilidi =====
// Web (Ayarlar) -> window.webkit.messageHandlers.faceid.postMessage({action:"enable|disable|status"})
extension ViewController {
    func handleFaceId(_ message: WKScriptMessage) {
        let action = ((message.body as? [String: Any])?["action"] as? String)
            ?? (message.body as? String) ?? ""
        switch action {
        case "enable":
            BiometricLock.shared.enableWithPrompt { ok in
                OtelPMS.webView?.evaluateJavaScript("window.gxFaceIdResult && window.gxFaceIdResult(\(ok ? "true" : "false"))", completionHandler: nil)
            }
        case "disable":
            BiometricLock.shared.disable()
            OtelPMS.webView?.evaluateJavaScript("window.gxFaceIdResult && window.gxFaceIdResult(false)", completionHandler: nil)
        default: // status
            let on = BiometricLock.shared.isEnabled
            OtelPMS.webView?.evaluateJavaScript("window.gxFaceIdResult && window.gxFaceIdResult(\(on ? "true" : "false"))", completionHandler: nil)
        }
    }
}

// ===== Biometric lock manager =====
final class BiometricLock {
    static let shared = BiometricLock()
    private let key = "gx_faceid_enabled"
    private var lockWindow: UIWindow?
    private var authenticating = false
    private var unlocked = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// When the web toggles it on, authenticate once; persist on success.
    func enableWithPrompt(completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            completion(false); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Genix Hotel") { ok, _ in
            DispatchQueue.main.async {
                if ok { self.isEnabled = true; self.unlocked = true }
                completion(ok)
            }
        }
    }

    func disable() {
        isEnabled = false
        unlocked = true
        removeCover()
    }

    // Scene lifecycle hooks
    func willResignActive() { if isEnabled { showCover() } }
    func didEnterBackground() { if isEnabled { unlocked = false; showCover() } }
    func didBecomeActive() {
        guard isEnabled else { removeCover(); return }
        if unlocked { removeCover(); return }
        showCover()
        authenticate()
    }

    private func authenticate() {
        guard !authenticating else { return }
        authenticating = true
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No biometrics/passcode -> do not lock the user out
            authenticating = false; unlocked = true; removeCover(); return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Genix Hotel") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok { self.unlocked = true; self.removeCover() }
                // failed: the cover stays; the user can retry with "Unlock with Face ID"
            }
        }
    }

    private func showCover() {
        if lockWindow != nil { return }
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState != .unattached }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let vc = LockViewController()
        vc.onRetry = { [weak self] in self?.authenticate() }
        w.rootViewController = vc
        w.makeKeyAndVisible()
        lockWindow = w
    }

    private func removeCover() {
        lockWindow?.isHidden = true
        lockWindow = nil
    }
}

final class LockViewController: UIViewController {
    var onRetry: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.043, green: 0.067, blue: 0.125, alpha: 1) // #0b1120

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        let icon = UILabel()
        icon.text = "🔒"
        icon.font = .systemFont(ofSize: 52)

        let title = UILabel()
        title.text = "Genix Otel Takip"
        title.textColor = .white
        title.font = .boldSystemFont(ofSize: 20)

        let sub = UILabel()
        sub.text = "Authenticate to continue"
        sub.textColor = UIColor(white: 1, alpha: 0.7)
        sub.font = .systemFont(ofSize: 14)
        sub.numberOfLines = 0
        sub.textAlignment = .center

        let btn = UIButton(type: .system)
        btn.setTitle("Unlock with Face ID", for: .normal)
        btn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(red: 0.176, green: 0.357, blue: 1, alpha: 1) // #2D5BFF
        btn.layer.cornerRadius = 12
        btn.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        btn.widthAnchor.constraint(equalToConstant: 200).isActive = true

        [icon, title, sub, btn].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(26, after: sub)
    }

    @objc private func retryTapped() { onRetry?() }
}


// ===== In-App Purchase (StoreKit 2) =====
// Web JS  ->  window.webkit.messageHandlers.iap.postMessage({action, productId})
// Native  ->  window.genixIAPResult({event, ok, ...})
// Apple IAP is the only payment path on iOS; external checkout is never shown.
extension ViewController {
    func handleIAP(_ message: WKScriptMessage) {
        guard #available(iOS 15.0, *) else {
            OtelPMS.webView?.evaluateJavaScript(
                "window.genixIAPResult && window.genixIAPResult({event:'error',ok:false,error:'ios15-required'});",
                completionHandler: nil)
            return
        }
        let body = message.body as? [String: Any] ?? [:]
        let action = (body["action"] as? String) ?? ""
        let productId = (body["productId"] as? String) ?? "com.genixsoft.hotel.pro.yearly"
        switch action {
        case "products": GenixIAP.shared.products([productId])
        case "purchase": GenixIAP.shared.purchase(productId)
        case "restore":  GenixIAP.shared.restore()
        case "status":   GenixIAP.shared.status()
        default: break
        }
    }
}

@available(iOS 15.0, *)
final class GenixIAP {
    static let shared = GenixIAP()
    private var updatesTask: Task<Void, Never>? = nil
    private let iso = ISO8601DateFormatter()

    private func emit(_ event: String, _ payload: [String: Any]) {
        var data = payload
        data["event"] = event
        let json = (try? JSONSerialization.data(withJSONObject: data))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.genixIAPResult && window.genixIAPResult(\(json));"
        DispatchQueue.main.async {
            OtelPMS.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func startObserving() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await self?.handleVerified(transaction, source: "update")
                    await transaction.finish()
                }
            }
        }
    }

    private func handleVerified(_ t: Transaction, source: String) async {
        emit("purchase", [
            "ok": true,
            "productId": t.productID,
            "transactionId": String(t.id),
            "originalTransactionId": String(t.originalID),
            "purchaseDate": iso.string(from: t.purchaseDate),
            "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? "",
            "source": source
        ])
    }

    func products(_ ids: [String]) {
        Task {
            do {
                let products = try await Product.products(for: ids)
                let list = products.map { p -> [String: Any] in
                    [
                        "productId": p.id,
                        "displayName": p.displayName,
                        "description": p.description,
                        "displayPrice": p.displayPrice
                    ]
                }
                emit("products", ["ok": true, "products": list])
            } catch {
                emit("products", ["ok": false, "error": "\(error)"])
            }
        }
    }

    func purchase(_ productId: String) {
        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    emit("purchase", ["ok": false, "error": "urun-bulunamadi", "productId": productId]); return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await handleVerified(transaction, source: "purchase")
                        await transaction.finish()
                    case .unverified(_, let err):
                        emit("purchase", ["ok": false, "error": "dogrulanamadi: \(err)", "productId": productId])
                    }
                case .userCancelled:
                    emit("purchase", ["ok": false, "cancelled": true, "productId": productId])
                case .pending:
                    emit("purchase", ["ok": false, "pending": true, "productId": productId])
                @unknown default:
                    emit("purchase", ["ok": false, "error": "bilinmeyen", "productId": productId])
                }
            } catch {
                emit("purchase", ["ok": false, "error": "\(error)", "productId": productId])
            }
        }
    }

    func restore() {
        Task {
            try? await AppStore.sync()
            var found: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result {
                    found.append([
                        "productId": t.productID,
                        "transactionId": String(t.id),
                        "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? ""
                    ])
                }
            }
            emit("restore", ["ok": true, "entitlements": found])
        }
    }

    func status() {
        Task {
            var active: [[String: Any]] = []
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result {
                    active.append([
                        "productId": t.productID,
                        "expirationDate": t.expirationDate.map { iso.string(from: $0) } ?? ""
                    ])
                }
            }
            emit("status", ["ok": true, "active": active, "isActive": !active.isEmpty])
        }
    }
}