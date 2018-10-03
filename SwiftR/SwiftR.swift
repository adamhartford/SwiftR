//
//  SwiftR.swift
//  SwiftR
//
//  Created by Adam Hartford on 4/13/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Foundation
import WebKit

@objc public enum ConnectionType: Int {
    case hub
    case persistent
}

@objc public enum State: Int {
    case connecting
    case connected
    case disconnected
}

public enum Transport {
    case auto
    case webSockets
    case foreverFrame
    case serverSentEvents
    case longPolling
    
    var stringValue: String {
        switch self {
        case .webSockets:
            return "webSockets"
        case .foreverFrame:
            return "foreverFrame"
        case .serverSentEvents:
            return "serverSentEvents"
        case .longPolling:
            return "longPolling"
        default:
            return "auto"
        }
    }
}

public enum SwiftRError: Error {
	case notConnected
	
	public var message: String {
		switch self {
		case .notConnected:
			return "Operation requires connection, but none available."
		}
	}
}

class SwiftR {
    static var connections = [SignalR]()
    
#if os(iOS)
    public class func cleanup() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SwiftR", isDirectory: true)
        let fileManager = FileManager.default
        
        do {
            if fileManager.fileExists(atPath: temp.path) {
                try fileManager.removeItem(at: temp)
            }
        } catch {
            print("Failed to remove temp JavaScript: \(error)")
        }
    }
#endif
}

open class SignalR: NSObject, SwiftRWebDelegate {
    static var connections = [SignalR]()
    
    var internalID: String!
    var ready = false
    
    public var signalRVersion: SignalRVersion = .v2_2_2
    public var useWKWebView = false
    public var transport: Transport = .auto
    /// load Web resource from the provided url, which will be used as Origin HTTP header
    public var originUrlString: String?

    var webView: SwiftRWebView!
    var wkWebView: WKWebView!

    var baseUrl: String
    var connectionType: ConnectionType
    
    var readyHandler: ((SignalR) -> ())!
    var hubs = [String: Hub]()

    open var state: State = .disconnected
    open var connectionID: String?
    open var received: ((Any?) -> ())?
    open var starting: (() -> ())?
    open var connected: (() -> ())?
    open var disconnected: (() -> ())?
    open var connectionSlow: (() -> ())?
    open var connectionFailed: (() -> ())?
    open var reconnecting: (() -> ())?
    open var reconnected: (() -> ())?
    open var error: (([String: Any]?) -> ())?
    
    var jsQueue: [(String, ((Any?) -> ())?)] = []
    
    open var customUserAgent: String?
    
    open var queryString: Any? {
        didSet {
            if let qs: Any = queryString {
                if let jsonData = try? JSONSerialization.data(withJSONObject: qs, options: JSONSerialization.WritingOptions()) {
                    let json = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)! as String
                    runJavaScript("swiftR.connection.qs = \(json)")
                }
            } else {
                runJavaScript("swiftR.connection.qs = {}")
            }
        }
    }
    
    open var headers: [String: String]? {
        didSet {
            if let h = headers {
                if let jsonData = try? JSONSerialization.data(withJSONObject: h, options: JSONSerialization.WritingOptions()) {
                    let json = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)! as String
                    runJavaScript("swiftR.headers = \(json)")
                }
            } else {
                runJavaScript("swiftR.headers = {}")
            }
        }
    }
    
    public init(_ baseUrl: String, connectionType: ConnectionType = .hub) {
        internalID = NSUUID().uuidString
        self.baseUrl = baseUrl
        self.connectionType = connectionType
        super.init()
    }
    
    public func connect(_ callback: (() -> ())? = nil) {
        readyHandler = { [weak self] _ in
            self?.jsQueue.forEach { self?.runJavaScript($0.0, callback: $0.1) }
            self?.jsQueue.removeAll()
            
            if let hubs = self?.hubs {
                hubs.forEach { $0.value.initialize() }
            }
            
            self?.ready = true
            callback?()
        }
        
        initialize()
    }
    
    private func initialize() {
        #if COCOAPODS
            let bundle = Bundle(identifier: "org.cocoapods.SwiftR")!
        #elseif SWIFTR_FRAMEWORK
            let bundle = Bundle(identifier: "com.adamhartford.SwiftR")!
        #else
            let bundle = Bundle.main
        #endif
        
        let jqueryURL = bundle.url(forResource: "jquery-2.1.3.min", withExtension: "js")!
        let signalRURL = bundle.url(forResource: "jquery.signalr-\(signalRVersion).min", withExtension: "js")!
        let jsURL = bundle.url(forResource: "SwiftR", withExtension: "js")!
        // script HTML snippet helpers
        let scriptAsSrc: (URL) -> String = { url in return "<script src='\(url.absoluteString)'></script>" }
        let scriptAsContent: (URL) -> String = { url in
            let scriptContent = try! String(contentsOf: url, encoding: .utf8)
            return "<script>\(scriptContent)</script>"
        }
        let script: (URL) -> String = { url in return self.originUrlString != nil ? scriptAsContent(url) : scriptAsSrc(url) }
        // build script sections
        var jqueryInclude = script(jqueryURL)
        var signalRInclude = script(signalRURL)
        var jsInclude = script(jsURL)

        /// use originUrlString if provided, otherwise fallback to bundle URL
        let baseHTMLUrl = originUrlString.map { URL(string: $0) } ?? bundle.bundleURL

        if useWKWebView {
            // Loading file:// URLs from NSTemporaryDirectory() works on iOS, not OS X.
            // Workaround on OS X is to include the script directly.
            #if os(iOS)
                if #available(iOS 9.0, *), originUrlString == nil {
                    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SwiftR", isDirectory: true)
                    let jqueryTempURL = temp.appendingPathComponent("jquery-2.1.3.min.js")
                    let signalRTempURL = temp.appendingPathComponent("jquery.signalr-\(signalRVersion).min")
                    let jsTempURL = temp.appendingPathComponent("SwiftR.js")
                    
                    let fileManager = FileManager.default
                    
                    do {
                        if SwiftR.connections.isEmpty {
                            SwiftR.cleanup()
                            try fileManager.createDirectory(at: temp, withIntermediateDirectories: false)
                        }
                        
                        if !fileManager.fileExists(atPath: jqueryTempURL.path) {
                            try fileManager.copyItem(at: jqueryURL, to: jqueryTempURL)
                        }
                        if !fileManager.fileExists(atPath: signalRTempURL.path) {
                            try fileManager.copyItem(at: signalRURL, to: signalRTempURL)
                        }
                        if !fileManager.fileExists(atPath: jsTempURL.path) {
                            try fileManager.copyItem(at: jsURL, to: jsTempURL)
                        }
                    } catch {
                        print("Failed to copy JavaScript to temp dir: \(error)")
                    }
                    
                    jqueryInclude = scriptAsSrc(jqueryTempURL)
                    signalRInclude = scriptAsSrc(signalRTempURL)
                    jsInclude = scriptAsSrc(jsTempURL)
                }
            #else
                if originUrlString == nil {
                    // force to content regardless Origin configuration for OS X
                    jqueryInclude = scriptAsContent(jqueryURL)
                    signalRInclude = scriptAsContent(signalRURL)
                    jsInclude = scriptAsContent(jsURL)
                }
            #endif
            
            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "interOp")
            #if !os(iOS)
                //config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            #endif
            wkWebView = WKWebView(frame: CGRect.zero, configuration: config)
            wkWebView.navigationDelegate = self
            
            let html = "<!doctype html><html><head></head><body>"
                + "\(jqueryInclude)\(signalRInclude)\(jsInclude)"
                + "</body></html>"
            
            wkWebView.loadHTMLString(html, baseURL: baseHTMLUrl)
        } else {
            let html = "<!doctype html><html><head></head><body>"
                + "\(jqueryInclude)\(signalRInclude)\(jsInclude)"
                + "</body></html>"
            
            webView = SwiftRWebView()
            #if os(iOS)
                webView.delegate = self
                webView.loadHTMLString(html, baseURL: baseHTMLUrl)
            #else
                webView.policyDelegate = self
                webView.mainFrame.loadHTMLString(html, baseURL: baseHTMLUrl)
            #endif
        }
        
        if let ua = customUserAgent {
            applyUserAgent(ua)
        }
        
        SwiftR.connections.append(self)
    }
    
    deinit {
        if let view = wkWebView {
            view.removeFromSuperview()
        }
    }
    
    open func createHubProxy(_ name: String) -> Hub {
        let hub = Hub(name: name, connection: self)
        hubs[name.lowercased()] = hub
        return hub
    }
    
    open func addHub(_ hub: Hub) {
        hub.connection = self
        hubs[hub.name.lowercased()] = hub
    }
    
    open func send(_ data: Any?) {
        var json = "null"
        if let d = data {
            if let val = SignalR.stringify(d) {
                json = val
            }
        }
        runJavaScript("swiftR.connection.send(\(json))")
    }

    open func start() {
        if ready {
            runJavaScript("start()")
        } else {
            connect()
        }
    }
    
    open func stop() {
        runJavaScript("swiftR.connection.stop()")
    }
    
    func shouldHandleRequest(_ request: URLRequest) -> Bool {
        if request.url!.absoluteString.hasPrefix("swiftr://") {
            let id = (request.url!.absoluteString as NSString).substring(from: 9)
            let msg = webView.stringByEvaluatingJavaScript(from: "readMessage('\(id)')")!
            let data = msg.data(using: String.Encoding.utf8, allowLossyConversion: false)!
            let json = try! JSONSerialization.jsonObject(with: data, options: [])
            
            if let m = json as? [String: Any] {
                processMessage(m)
            }

            return false
        }
        
        return true
    }

    func processMessage(_ json: [String: Any]) {
        if let message = json["message"] as? String {
            switch message {
            case "ready":
                let isHub = connectionType == .hub ? "true" : "false"
                runJavaScript("swiftR.transport = '\(transport.stringValue)'")
                runJavaScript("initialize('\(baseUrl)', \(isHub))")
                readyHandler(self)
                runJavaScript("start()")
            case "starting":
                state = .connecting
                starting?()
            case "connected":
                state = .connected
                connectionID = json["connectionId"] as? String
                connected?()
            case "disconnected":
                state = .disconnected
                disconnected?()
            case "connectionSlow":
                connectionSlow?()
            case "connectionFailed":
                connectionFailed?()
            case "reconnecting":
                state = .connecting
                reconnecting?()
            case "reconnected":
                state = .connected
                reconnected?()
            case "invokeHandler":
                let hubName = json["hub"] as! String
                if let hub = hubs[hubName] {
                    let uuid = json["id"] as! String
                    let result = json["result"]
                    let error = json["error"] as AnyObject?
                    if let callback = hub.invokeHandlers[uuid] {
                        callback(result as AnyObject?, error)
                        hub.invokeHandlers.removeValue(forKey: uuid)
                    } else if let e = error {
                        print("SwiftR invoke error: \(e)")
                    }
                }
            case "error":
                if let err = json["error"] as? [String: Any] {
                    error?(err)
                } else {
                    error?(nil)
                }
            default:
                break
            }
        } else if let data: Any = json["data"] {
            received?(data)
        } else if let hubName = json["hub"] as? String {
            let callbackID = json["id"] as? String
            let method = json["method"] as? String
            let arguments = json["arguments"] as? [AnyObject]
            let hub = hubs[hubName]
            
            if let method = method, let callbackID = callbackID, let handlers = hub?.handlers[method], let handler = handlers[callbackID] {
                handler(arguments)
            }
        }
    }
    
    func runJavaScript(_ script: String, callback: ((Any?) -> ())? = nil) {
        guard wkWebView != nil || webView != nil else {
            jsQueue.append((script, callback))
            return
        }
        
        if useWKWebView {
            wkWebView.evaluateJavaScript(script, completionHandler: { (result, _)  in
                callback?(result)
            })
        } else {
            let result = webView.stringByEvaluatingJavaScript(from: script)
            callback?(result as AnyObject!)
        }
    }
    
    func applyUserAgent(_ userAgent: String) {
        #if os(iOS)
            if useWKWebView {
                if #available(iOS 9.0, *) {
                    wkWebView.customUserAgent = userAgent
                } else {
                    print("Unable to set user agent for WKWebView on iOS <= 8. Please register defaults via NSUserDefaults instead.")
                }
            } else {
                print("Unable to set user agent for UIWebView. Please register defaults via NSUserDefaults instead.")
            }
        #else
            if useWKWebView {
                if #available(OSX 10.11, *) {
                    wkWebView.customUserAgent = userAgent
                } else {
                    print("Unable to set user agent for WKWebView on OS X <= 10.10.")
                }
            } else {
                webView.customUserAgent = userAgent
            }
        #endif
    }
    
    // MARK: - WKNavigationDelegate
    
    // http://stackoverflow.com/questions/26514090/wkwebview-does-not-run-javascriptxml-http-request-with-out-adding-a-parent-vie#answer-26575892
    open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        #if os(iOS)
            UIApplication.shared.keyWindow?.addSubview(wkWebView)
        #endif
    }
    
    // MARK: - WKScriptMessageHandler
    
    open func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let id = message.body as? String {
            wkWebView.evaluateJavaScript("readMessage('\(id)')", completionHandler: { [weak self] (msg, err) in
                if let m = msg as? [String: Any] {
                    self?.processMessage(m)
                } else if let e = err {
                    print("SwiftR unable to process message \(id): \(e)")
                } else {
                    print("SwiftR unable to process message \(id)")
                }
            })
        }
    }
    
    // MARK: - Web delegate methods
    
#if os(iOS)
    open func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebView.NavigationType) -> Bool {
        return shouldHandleRequest(request)
    }
#else
    public func webView(_ webView: WebView!, decidePolicyForNavigationAction actionInformation: [AnyHashable : Any]!, request: URLRequest!, frame: WebFrame!, decisionListener listener: WebPolicyDecisionListener!) {
        
        if shouldHandleRequest(request as URLRequest) {
            listener.use()
        }
    }
#endif
    
    class func stringify(_ obj: Any) -> String? {
        // Using an array to start with a valid top level type for NSJSONSerialization
        let arr = [obj]
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: JSONSerialization.WritingOptions()) {
            if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String? {
                // Strip the array brackets to be left with the desired value
                let range = str.index(str.startIndex, offsetBy: 1) ..< str.index(str.endIndex, offsetBy: -1)
                return String(str[range])
            }
        }
        return nil
    }
}

// MARK: - Hub

open class Hub: NSObject {
    let name: String
    var handlers: [String: [String: ([Any]?) -> ()]] = [:]
    var invokeHandlers: [String: (_ result: Any?, _ error: AnyObject?) -> ()] = [:]
    var connection: SignalR!
    
    public init(_ name: String) {
        self.name = name
        self.connection = nil
    }
    
    init(name: String, connection: SignalR) {
        self.name = name
        self.connection = connection
    }
    
    open func on(_ method: String, callback: @escaping ([Any]?) -> ()) {
        let callbackID = UUID().uuidString
        
        if handlers[method] == nil {
            handlers[method] = [:]
        }
        
        handlers[method]?[callbackID] = callback
    }
    
    func initialize() {
        for (method, callbacks) in handlers {
            callbacks.forEach { connection.runJavaScript("addHandler('\($0.key)', '\(name)', '\(method)')") }
        }
    }
    
    open func invoke(_ method: String, arguments: [Any]? = nil, callback: ((_ result: Any?, _ error: Any?) -> ())? = nil) throws {
		guard connection != nil else {
			throw SwiftRError.notConnected
		}
		
        var jsonArguments = [String]()
        
        if let args = arguments {
            for arg in args {
                if let val = SignalR.stringify(arg) {
                    jsonArguments.append(val)
                } else {
                    jsonArguments.append("null")
                }
            }
        }
        
        let args = jsonArguments.joined(separator: ", ")
        
        let uuid = UUID().uuidString
        if let handler = callback {
            invokeHandlers[uuid] = handler
        }
        
        let doneJS = "function() { postMessage({ message: 'invokeHandler', hub: '\(name.lowercased())', id: '\(uuid)', result: arguments[0] }); }"
        let failJS = "function() { postMessage({ message: 'invokeHandler', hub: '\(name.lowercased())', id: '\(uuid)', error: processError(arguments[0]) }); }"
        let js = args.isEmpty
            ? "ensureHub('\(name)').invoke('\(method)').done(\(doneJS)).fail(\(failJS))"
            : "ensureHub('\(name)').invoke('\(method)', \(args)).done(\(doneJS)).fail(\(failJS))"
        
        connection.runJavaScript(js)
    }
    
}

public enum SignalRVersion : CustomStringConvertible {
    case v2_2_2
    case v2_2_1
    case v2_2_0
    case v2_1_2
    case v2_1_1
    case v2_1_0
    case v2_0_3
    case v2_0_2
    case v2_0_1
    case v2_0_0
    
    public var description: String {
        switch self {
            case .v2_2_2: return "2.2.2"
            case .v2_2_1: return "2.2.1"
            case .v2_2_0: return "2.2.0"
            case .v2_1_2: return "2.1.2"
            case .v2_1_1: return "2.1.1"
            case .v2_1_0: return "2.1.0"
            case .v2_0_3: return "2.0.3"
            case .v2_0_2: return "2.0.2"
            case .v2_0_1: return "2.0.1"
            case .v2_0_0: return "2.0.0"
        }
    }
}

#if os(iOS)
    typealias SwiftRWebView = UIWebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler, UIWebViewDelegate {}
#else
    typealias SwiftRWebView = WebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler, WebPolicyDelegate {}
#endif
