import CoreMotion
import SwiftUI
import UIKit
import WebKit
import os

/// The full-screen 3D sky: the Celestial Birth Chart web page (WebSky/index.html, an unchanged copy of
/// the visual-tatvaum-ui-reimagined design, shared with the Android app) running in a WKWebView, opened
/// on the selected profile's birth moment.
///
/// Everything is served from the app bundle, so it works offline:
///  - the page, cities.js and look-around.js from WebSky/
///  - three.js, which the page imports from cdn.jsdelivr.net, from WebSky/three@0.160.0/
/// A small script added to the page as it's served skips its PIN screen, fills in the birth details,
/// trims the page to the planet view, and adds Tour and Look around buttons. Look around
/// (WebSky/look-around.js) follows the phone's orientation, streamed in by `LookAround`.
struct WebSkyView: View {
    let profile: UserProfile
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(argb: 0xFF05060D).ignoresSafeArea()
            WebSkyPage(birth: WebSky.birthJSON(profile)).ignoresSafeArea()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Color(argb: 0x99141630), in: Circle())
            }
            .accessibilityLabel("Close sky")
            .padding(8)
        }
    }
}

private struct WebSkyPage: UIViewRepresentable {
    let birth: String

    func makeCoordinator() -> LookAround { LookAround() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SkySchemeHandler(birth: birth), forURLScheme: WebSky.scheme)
        let content = config.userContentController
        // The page calls window.TatvaumApp.startLook() / stopLook(), as on Android.
        content.addUserScript(WKUserScript(source: """
            window.TatvaumApp = {
              startLook: function () { window.webkit.messageHandlers.tatvaumLook.postMessage('start'); },
              stopLook: function () { window.webkit.messageHandlers.tatvaumLook.postMessage('stop'); }
            };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakMessageHandler(context.coordinator), name: "tatvaumLook")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 5 / 255, green: 6 / 255, blue: 13 / 255, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.webView = web
        web.load(URLRequest(url: WebSky.page))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: LookAround) {
        coordinator.stop()
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "tatvaumLook")
    }
}

enum WebSky {
    static let scheme = "tatvaum-sky"
    static let origin = "\(scheme)://app/"
    static let page = URL(string: origin + "index.html")!
    static let threeCDN = "https://cdn.jsdelivr.net/npm/three@0.160.0/"
    static let log = Logger(subsystem: "com.tatvaum.connect", category: "WebSky")

    /// Birth moment for the page: date and time in the birth timezone, plus coordinates.
    static func birthJSON(_ p: UserProfile) -> String {
        var o: [String: Any] = [
            "date": p.dateOfBirth ?? "",
            "time": String((p.timeOfBirth ?? "").prefix(5)),
            "tz": p.birthTimezone,
            "place": p.placeOfBirth.split(separator: ",").first.map(String.init) ?? "",
        ]
        if let lat = p.birthPlaceLatitude { o["lat"] = lat }
        if let lon = p.birthPlaceLongitude { o["lon"] = lon }
        if let dob = p.dateOfBirth, let tob = p.timeOfBirth,
           let ms = ProfileStore.birthMillis(dob, tob, p.birthTimezone) { o["utc"] = ms }
        guard let data = try? JSONSerialization.data(withJSONObject: o), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func mime(_ path: String) -> String {
        switch (path as NSString).pathExtension {
        case "html": "text/html"
        case "js": "text/javascript"
        case "svg": "image/svg+xml"
        case "css": "text/css"
        case "json": "application/json"
        default: "application/octet-stream"
        }
    }

    /// Changes applied to the page as it's served (the bundled file itself stays an unchanged copy):
    ///  - three.js is loaded from the bundle instead of the CDN;
    ///  - styles that trim it to the splash, the 3D planet view and the app's buttons (its form,
    ///    profile, tab bar, legend and hint are hidden);
    ///  - marks the PIN screen as passed for this session;
    ///  - two hooks into its scene script for Look around: expose the scene objects, and let
    ///    look-around.js position the camera each frame (pausing the orbit controls meanwhile);
    ///  - once the page has booted: sets the birth details, recalculates, and adds the buttons.
    static func withBootstrap(_ original: String, birth: String) -> String {
        var html = original.replacingOccurrences(of: threeCDN, with: origin + "three@0.160.0/")
        var hooked = true
        func hook(_ anchor: String, _ replacement: String) {
            if html.contains(anchor) { html = html.replacingOccurrences(of: anchor, with: replacement) } else { hooked = false }
        }
        hook("earth.userData.key = 'earth';", "earth.userData.key = 'earth';\nwindow.__sky = { THREE, camera, controls, scene, earth };")
        hook("    controls.update();\n  }\n  composer.render();",
             "    if (!window.__skyLooking) controls.update();\n  }\n  if (window.__skyLookFrame) window.__skyLookFrame();\n  composer.render();")
        if !hooked { log.warning("Page changed: Look around hooks not applied, button hidden") }

        let head = #"""
        <style>
          .panel, .profile, .profile-toggle, .tabbar, .legend, .hint, .collapse, .share-modal { display: none !important; }
          html, body { height: 100% !important; }
          :root { --tabbar-h: calc(84px + env(safe-area-inset-bottom)) !important; }   /* planet pop-up sits above the buttons */
          #tvBar { position: fixed; left: 0; right: 0; bottom: calc(24px + env(safe-area-inset-bottom)); z-index: 13;
            display: flex; justify-content: center; gap: 10px; pointer-events: none; }
          #tvBar button { pointer-events: auto; padding: 12px 22px; border-radius: 999px; font-size: 15px; letter-spacing: .03em;
            box-shadow: 0 0 24px -4px rgba(245,198,107,0.5), 0 10px 30px rgba(0,0,0,0.5); }
          #tvBar button.ghost { background: rgba(14,16,32,0.85); }
          body.touring #tvBar, body:has(.popup.show) #tvBar { display: none; }
          #tvLook { display: none; position: fixed; left: 0; right: 0; z-index: 13; pointer-events: none;
            top: calc(64px + env(safe-area-inset-top)); text-align: center; }
          #tvLookNote { display: inline-block; max-width: 86%; font-size: 12.5px; color: var(--text); background: var(--panel);
            border: 1px solid var(--border); border-radius: 20px; padding: 7px 14px; }
          body.looking #tvLook { display: block; }
          body.looking #tvTourBtn, body.looking #tvLookBtn { display: none; }
          #tvExitBtn { display: none; }
          body.looking #tvExitBtn { display: inline-block; }
        </style>
        <script>
          window.__TATVAUM_BIRTH = \#(birth);
        </script>
        <script src="look-around.js"></script>
        <script>
        (function () {
          try { sessionStorage.setItem('celestial-unlocked', '6a02bae4'); } catch (e) {}
          var B = window.__TATVAUM_BIRTH;
          function ready() { var c = document.getElementById('calc'); return c && !document.body.classList.contains('locked'); }
          function button(id, text, cls, onClick) {
            var b = document.createElement('button');
            b.id = id; b.type = 'button'; b.textContent = text; if (cls) b.className = cls;
            b.addEventListener('click', onClick);
            return b;
          }
          function apply(tries) {
            if (!ready()) { if (tries < 200) setTimeout(function () { apply(tries + 1); }, 50); return; }
            var $ = function (id) { return document.getElementById(id); };
            if (B.date) {
              $('date').value = B.date;
              if (B.time) $('time').value = B.time;
              if (B.tz) { $('tz').value = B.tz; $('tzSearch').value = B.tz.replace(/_/g, ' '); }
              if (B.lat != null && B.lon != null) {
                $('lat').value = B.lat; $('lon').value = B.lon;
                $('lat').dispatchEvent(new Event('change'));     // the page recalculates on coordinate changes
              } else {
                $('date').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
              }
            }
            var sky = document.querySelector('#tabbar [data-act="sky"]');
            if (sky) sky.click();                                // close the form sheet the page opens on phones

            var bar = document.createElement('div'); bar.id = 'tvBar';
            bar.appendChild(button('tvTourBtn', '⊕ Tour', '', function () {
              var t = document.querySelector('#tabbar [data-act="tour"]');
              if (t) t.click();                                  // the page's own planet tour
            }));
            if (window.__skyLookAvailable && window.__skyLookAvailable()) {
              bar.appendChild(button('tvLookBtn', '🧭 Look around', 'ghost', function () { window.__skyLookStart(); }));
              bar.appendChild(button('tvExitBtn', '✕ Exit look around', '', function () { window.__skyLookStop(); }));
            }
            document.body.appendChild(bar);
            var note = document.createElement('div'); note.id = 'tvLook';
            note.innerHTML = '<span id="tvLookNote"></span>';
            document.body.appendChild(note);
          }
          document.addEventListener('DOMContentLoaded', function () { setTimeout(function () { apply(0); }, 0); });
        })();
        </script>
        """#
        guard let at = html.range(of: "<head>") else { return head + html }
        html.insert(contentsOf: head, at: at.upperBound)
        return html
    }
}

/// Serves `tatvaum-sky://app/<path>` from the bundled WebSky folder.
private final class SkySchemeHandler: NSObject, WKURLSchemeHandler {
    let birth: String
    init(birth: String) { self.birth = birth }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let root = Bundle.main.resourceURL!.appendingPathComponent("WebSky", isDirectory: true).standardizedFileURL
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), var data = try? Data(contentsOf: file) else {
            WebSky.log.error("not found: \(path, privacy: .public)")
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!)
            task.didFinish()
            return
        }
        if path == "index.html", let s = String(data: data, encoding: .utf8) {
            data = Data(WebSky.withBootstrap(s, birth: birth).utf8)
        }
        let headers = ["Content-Type": "\(WebSky.mime(path)); charset=utf-8", "Content-Length": "\(data.count)",
                       "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// `WKUserContentController` keeps its handlers alive; this breaks the cycle with the coordinator.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// Look around: streams the phone's orientation to the page as a device → east/north/up rotation
/// matrix (row-major, the same layout Android's SensorManager.getRotationMatrixFromVector gives),
/// with the device axes turned to match the screen when an iPad is in landscape.
final class LookAround: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var webView: WKWebView?
    private let motion = CMMotionManager()
    private var running = false

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.body as? String {
        case "start": start()
        case "stop": stop()
        default: break
        }
    }

    // Keep the page in the app; links (none expected) open nothing.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        action.request.url?.scheme == WebSky.scheme ? .allow : .cancel
    }

    private func start() {
        guard !running else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        guard motion.isDeviceMotionAvailable, frames.contains(.xMagneticNorthZVertical) else {
            webView?.evaluateJavaScript("window.__skyLookUnavailable && window.__skyLookUnavailable()")
            return
        }
        running = true
        motion.deviceMotionUpdateInterval = 1 / 60
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] m, _ in
            guard let self, let m, self.running else { return }
            let r = Self.enuMatrix(m.attitude.rotationMatrix, screen: self.webView?.window?.windowScene?.interfaceOrientation ?? .portrait)
            self.webView?.evaluateJavaScript("window.__skyLookSet && window.__skyLookSet([\(r.map { String($0) }.joined(separator: ","))])")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
    }

    /// CoreMotion's attitude matrix maps the reference frame (x north, y west, z up) to the device
    /// frame, so its transpose takes device axes to north/west/up; west is flipped to east.
    /// Columns are then the screen's x and y axes (and z) in east/north/up.
    static func enuMatrix(_ m: CMRotationMatrix, screen: UIInterfaceOrientation) -> [Double] {
        // Device axis j (x, y, z) in east/north/up.
        let dx = [-m.m12, m.m11, m.m13], dy = [-m.m22, m.m21, m.m23], dz = [-m.m32, m.m31, m.m33]
        let neg = { (v: [Double]) in v.map { -$0 } }
        let (sx, sy): ([Double], [Double]) = switch screen {
        case .landscapeRight: (neg(dy), dx)
        case .landscapeLeft: (dy, neg(dx))
        case .portraitUpsideDown: (neg(dx), neg(dy))
        default: (dx, dy)
        }
        return [sx[0], sy[0], dz[0], sx[1], sy[1], dz[1], sx[2], sy[2], dz[2]]
    }
}
