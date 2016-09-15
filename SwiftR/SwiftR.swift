//
//  SwiftR.swift
//  SwiftR
//
//  Created by Adam Hartford on 4/13/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Foundation
import WebKit

public enum ConnectionType {
    case hub
    case persistent
}

public enum State {
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

public final class SwiftR: NSObject {
    static var connections = [SignalR]()
    
    public static var signalRVersion: SignalRVersion = .v2_2_1
    
    public static var useWKWebView = false
    
    public static var transport: Transport = .auto
    
    @discardableResult
    public class func connect(_ url: String, connectionType: ConnectionType = .hub, readyHandler: @escaping (SignalR) -> ()) -> SignalR? {
        let signalR = SignalR(baseUrl: url, connectionType: connectionType, readyHandler: readyHandler)
        connections.append(signalR)
        return signalR
    }
    
    public class func startAll() {
        checkConnections()
        for connection in connections {
            connection.start()
        }
    }
    
    public class func stopAll() {
        checkConnections()
        for connection in connections {
            connection.stop()
        }
    }
    
    #if os(iOS)
        public class func cleanup() {
            let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            let jqueryTempURL = temp.appendingPathComponent("jquery-2.1.3.min.js")
            let signalRTempURL = temp.appendingPathComponent("jquery.signalr-\(signalRVersion).min")
            let jsTempURL = temp.appendingPathComponent("SwiftR.js")
            
            let fileManager = FileManager.default
            
            do {
                if fileManager.fileExists(atPath: jqueryTempURL.path) {
                    try fileManager.removeItem(at: jqueryTempURL)
                }
                if fileManager.fileExists(atPath: signalRTempURL.path) {
                    try fileManager.removeItem(at: signalRTempURL)
                }
                if fileManager.fileExists(atPath: jsTempURL.path) {
                    try fileManager.removeItem(at: jsTempURL)
                }
            } catch {
                print("Failed to remove temp JavaScript")
            }
        }
    #endif
    
    class func checkConnections() {
        if connections.count == 0 {
            print("No active SignalR connections. Use SwiftR.connect(...) first.")
        }
    }
    
    class func stringify(_ obj: Any) -> String? {
        // Using an array to start with a valid top level type for NSJSONSerialization
        let arr = [obj]
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: JSONSerialization.WritingOptions()) {
            if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) as? String {
                // Strip the array brackets to be left with the desired value
                let range = str.characters.index(str.startIndex, offsetBy: 1) ..< str.characters.index(str.endIndex, offsetBy: -1)
                return str.substring(with: range)
            }
        }
        return nil
    }
}

open class SignalR: NSObject, SwiftRWebDelegate {
    var webView: SwiftRWebView!
    var wkWebView: WKWebView!

    var baseUrl: String
    var connectionType: ConnectionType
    
    var readyHandler: (SignalR) -> ()
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
    
    open var queryString: Any? {
        didSet {
            if let qs: Any = queryString {
                if let jsonData = try? JSONSerialization.data(withJSONObject: qs, options: JSONSerialization.WritingOptions()) {
                    let json = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue) as! String
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
                    let json = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue) as! String
                    runJavaScript("swiftR.headers = \(json)")
                }
            } else {
                runJavaScript("swiftR.headers = {}")
            }
        }
    }
    
    open var customUserAgent: String? {
        didSet {
            #if os(iOS)
                if SwiftR.useWKWebView {
                    if #available(iOS 9.0, *) {
                        wkWebView.customUserAgent = customUserAgent
                    } else {
                        print("Unable to set user agent for WKWebView on iOS <= 8. Please register defaults via NSUserDefaults instead.")
                    }
                } else {
                    print("Unable to set user agent for UIWebView. Please register defaults via NSUserDefaults instead.")
                }
            #else
                if SwiftR.useWKWebView {
                    if #available(OSX 10.11, *) {
                        wkWebView.customUserAgent = customUserAgent
                    } else {
                        print("Unable to set user agent for WKWebView on OS X <= 10.10.")
                    }
                } else {
                    webView.customUserAgent = customUserAgent
                }
            #endif
        }
    }
    
    init(baseUrl: String, connectionType: ConnectionType = .hub, readyHandler: @escaping (SignalR) -> ()) {
        self.baseUrl = baseUrl
        self.readyHandler = readyHandler
        self.connectionType = connectionType
        super.init()
        
        #if COCOAPODS
            let bundle = Bundle(identifier: "org.cocoapods.SwiftR")!
        #elseif SWIFTR_FRAMEWORK
            let bundle = Bundle(identifier: "com.adamhartford.SwiftR")!
        #else
            let bundle = Bundle.main
        #endif
        
        let jqueryURL = bundle.url(forResource: "jquery-2.1.3.min", withExtension: "js")!
        let signalRURL = bundle.url(forResource: "jquery.signalr-\(SwiftR.signalRVersion).min", withExtension: "js")!
        let jsURL = bundle.url(forResource: "SwiftR", withExtension: "js")!
        
        if SwiftR.useWKWebView {
            var jqueryInclude = "<script src='\(jqueryURL.absoluteString)'></script>"
            var signalRInclude = "<script src='\(signalRURL.absoluteString)'></script>"
            var jsInclude = "<script src='\(jsURL.absoluteString)'></script>"
            
            // Loading file:// URLs from NSTemporaryDirectory() works on iOS, not OS X.
            // Workaround on OS X is to include the script directly.
            #if os(iOS)
                if #available(iOS 9.0, *) {
                    let temp = URL(fileURLWithPath: NSTemporaryDirectory())
                    let jqueryTempURL = temp.appendingPathComponent("jquery-2.1.3.min.js")
                    let signalRTempURL = temp.appendingPathComponent("jquery.signalr-\(SwiftR.signalRVersion).min")
                    let jsTempURL = temp.appendingPathComponent("SwiftR.js")
                    
                    let fileManager = FileManager.default
                    
                    do {
                        if fileManager.fileExists(atPath: jqueryTempURL.path) {
                            try fileManager.removeItem(at: jqueryTempURL)
                        }
                        if fileManager.fileExists(atPath: signalRTempURL.path) {
                            try fileManager.removeItem(at: signalRTempURL)
                        }
                        if fileManager.fileExists(atPath: jsTempURL.path) {
                            try fileManager.removeItem(at: jsTempURL)
                        }
                    } catch {
                        print("Failed to remove existing temp JavaScript")
                    }
                    
                    do {
                        try fileManager.copyItem(at: jqueryURL, to: jqueryTempURL)
                        try fileManager.copyItem(at: signalRURL, to: signalRTempURL)
                        try fileManager.copyItem(at: jsURL, to: jsTempURL)
                    } catch {
                        print("Failed to copy JavaScript to temp dir")
                    }
                    
                    jqueryInclude = "<script src='\(jqueryTempURL.absoluteString)'></script>"
                    signalRInclude = "<script src='\(signalRTempURL.absoluteString)'></script>"
                    jsInclude = "<script src='\(jsTempURL.absoluteString)'></script>"
                }
            #else
                let jqueryString = try! NSString(contentsOf: jqueryURL, encoding: String.Encoding.utf8.rawValue)
                let signalRString = try! NSString(contentsOf: signalRURL, encoding: String.Encoding.utf8.rawValue)
                let jsString = try! NSString(contentsOf: jsURL, encoding: String.Encoding.utf8.rawValue)
                
                jqueryInclude = "<script>\(jqueryString)</script>"
                signalRInclude = "<script>\(signalRString)</script>"
                jsInclude = "<script>\(jsString)</script>"
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
            
            wkWebView.loadHTMLString(html, baseURL: bundle.bundleURL)
            return
        } else {
            let jqueryInclude = "<script src='\(jqueryURL.absoluteString)'></script>"
            let signalRInclude = "<script src='\(signalRURL.absoluteString)'></script>"
            let jsInclude = "<script src='\(jsURL.absoluteString)'></script>"
            
            let html = "<!doctype html><html><head></head><body>"
                + "\(jqueryInclude)\(signalRInclude)\(jsInclude)"
                + "</body></html>"
            
            webView = SwiftRWebView()
            #if os(iOS)
                webView.delegate = self
                webView.loadHTMLString(html, baseURL: bundle.bundleURL)
            #else
                webView.policyDelegate = self
                webView.mainFrame.loadHTMLString(html, baseURL: bundle.bundleURL)
            #endif
        }
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
    
    open func send(_ data: Any?) {
        var json = "null"
        if let d = data {
            if let val = SwiftR.stringify(d) {
                json = val
            }
        }
        runJavaScript("swiftR.connection.send(\(json))")
    }

    open func start() {
        runJavaScript("start()")
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
                runJavaScript("swiftR.transport = '\(SwiftR.transport.stringValue)'")
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
        if SwiftR.useWKWebView {
            wkWebView.evaluateJavaScript(script, completionHandler: { (result, _)  in
                callback?(result)
            })
        } else {
            let result = webView.stringByEvaluatingJavaScript(from: script)
            callback?(result as AnyObject!)
        }
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
    open func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        return shouldHandleRequest(request)
    }
#else
    public func webView(_ webView: WebView!, decidePolicyForNavigationAction actionInformation: [AnyHashable : Any]!, request: URLRequest!, frame: WebFrame!, decisionListener listener: WebPolicyDecisionListener!) {
        
        if shouldHandleRequest(request as URLRequest) {
            listener.use()
        }
    }
#endif
}

// MARK: - Hub

open class Hub {
    let name: String
    var handlers: [String: [String: ([Any]?) -> ()]] = [:]
    var invokeHandlers: [String: (_ result: Any?, _ error: AnyObject?) -> ()] = [:]
    
    open let connection: SignalR!
    
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
        connection.runJavaScript("addHandler('\(callbackID)', '\(name)', '\(method)')")
    }
    
    open func invoke(_ method: String, arguments: [Any]? = nil, callback: ((_ result: Any?, _ error: Any?) -> ())? = nil) {
        var jsonArguments = [String]()
        
        if let args = arguments {
            for arg in args {
                if let val = SwiftR.stringify(arg) {
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
