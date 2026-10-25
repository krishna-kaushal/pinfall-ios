import SwiftUI
import WebKit
import AVFoundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Pinfall", category: "GameWebView")

/// The whole game is the bundled web game (game.html) running in a WKWebView.
/// It is fully offline: no network, no tracking, progress in localStorage.
struct GameWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        // Asynchronously configure audio session off main thread to prevent UI hang warnings
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                logger.error("Failed to configure AVAudioSession: \(error.localizedDescription, privacy: .public)")
            }
        }

        let contentController = WKUserContentController()

        // Bridge JS console and error logging to Xcode os.Logger
        contentController.add(context.coordinator, name: "nativeLog")
        // Bridge JS haptics / navigator.vibrate to iOS UIImpactFeedbackGenerator / UINotificationFeedbackGenerator
        contentController.add(context.coordinator, name: "nativeHaptic")

        // Inject script: forward console.log/info/warn/error and window.onerror, and polyfill navigator.vibrate
        let bridgeScriptSource = """
        (function() {
            function sendLog(level, message) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeLog) {
                    window.webkit.messageHandlers.nativeLog.postMessage({ level: level, message: String(message) });
                }
            }

            var origLog = console.log;
            var origWarn = console.warn;
            var origError = console.error;
            var origInfo = console.info;

            console.log = function() {
                var args = Array.prototype.slice.call(arguments).join(' ');
                sendLog('log', args);
                origLog.apply(console, arguments);
            };
            console.info = function() {
                var args = Array.prototype.slice.call(arguments).join(' ');
                sendLog('info', args);
                origInfo.apply(console, arguments);
            };
            console.warn = function() {
                var args = Array.prototype.slice.call(arguments).join(' ');
                sendLog('warn', args);
                origWarn.apply(console, arguments);
            };
            console.error = function() {
                var args = Array.prototype.slice.call(arguments).join(' ');
                sendLog('error', args);
                origError.apply(console, arguments);
            };

            window.addEventListener('error', function(e) {
                sendLog('error', (e.message || 'Error') + ' at ' + (e.filename || '') + ':' + (e.lineno || 0));
            });

            // Polyfill navigator.vibrate for iOS WebKit
            navigator.vibrate = function(pattern) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeHaptic) {
                    window.webkit.messageHandlers.nativeHaptic.postMessage(pattern);
                    return true;
                }
                return false;
            };
        })();
        """
        let userScript = WKUserScript(source: bridgeScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.08, green: 0.06, blue: 0.11, alpha: 1.0)

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        if let url = Bundle.main.url(forResource: "game", withExtension: "html") {
            logger.info("Loading game bundle from: \(url.path, privacy: .public)")
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            logger.error("Could not find game.html in main bundle!")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let lightImpact = UIImpactFeedbackGenerator(style: .light)
        private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
        private let notificationFeedback = UINotificationFeedbackGenerator()

        override init() {
            super.init()
            lightImpact.prepare()
            mediumImpact.prepare()
            heavyImpact.prepare()
            notificationFeedback.prepare()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "nativeLog",
               let dict = message.body as? [String: Any],
               let level = dict["level"] as? String,
               let text = dict["message"] as? String {
                switch level {
                case "error":
                    logger.error("[JS Error] \(text, privacy: .public)")
                case "warn":
                    logger.warning("[JS Warn] \(text, privacy: .public)")
                case "info":
                    logger.info("[JS Info] \(text, privacy: .public)")
                default:
                    logger.log("[JS Log] \(text, privacy: .public)")
                }
            } else if message.name == "nativeHaptic" {
                triggerHaptic(body: message.body)
            }
        }

        private func triggerHaptic(body: Any) {
            if let pattern = body as? [Int] {
                if pattern.count > 1 {
                    notificationFeedback.notificationOccurred(.success)
                    notificationFeedback.prepare()
                } else if let first = pattern.first {
                    playDurationHaptic(first)
                }
            } else if let pattern = body as? [Double] {
                if pattern.count > 1 {
                    notificationFeedback.notificationOccurred(.success)
                    notificationFeedback.prepare()
                } else if let first = pattern.first {
                    playDurationHaptic(Int(first))
                }
            } else if let duration = body as? Int {
                playDurationHaptic(duration)
            } else if let durationDouble = body as? Double {
                playDurationHaptic(Int(durationDouble))
            }
        }

        private func playDurationHaptic(_ duration: Int) {
            if duration <= 25 {
                lightImpact.impactOccurred()
                lightImpact.prepare()
            } else if duration <= 80 {
                mediumImpact.impactOccurred()
                mediumImpact.prepare()
            } else {
                notificationFeedback.notificationOccurred(.error)
                notificationFeedback.prepare()
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            logger.info("Game webView started provisional navigation")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("Game webView finished loading successfully")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("Game webView navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("Game webView provisional navigation failed: \(error.localizedDescription, privacy: .public)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.warning("Game WebContent process terminated unexpectedly. Reloading...")
            webView.reload()
        }
    }
}

struct ContentView: View {
    var body: some View {
        GameWebView()
            .ignoresSafeArea()
            .background(Color(red: 0.08, green: 0.06, blue: 0.11))
    }
}
