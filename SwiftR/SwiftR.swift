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
    case Hub
    case Persistent
}

public enum State {
    case Connecting
    case Connected
    case Disconnected
}

public enum Transport {
    case Auto
    case WebSockets
    case ForeverFrame
    case ServerSentEvents
    case LongPolling
    
    var stringValue: String {
        switch self {
        case .WebSockets:
            return "webSockets"
        case .ForeverFrame:
            return "foreverFrame"
        case .ServerSentEvents:
            return "serverSentEvents"
        case .LongPolling:
            return "longPolling"
        default:
            return "auto"
        }
    }
}

public final class SwiftR: NSObject {
    static var connections = [SignalR]()
    
    public static var signalRVersion: SignalRVersion = .v2_2_0
    
    public static var useWKWebView = false
    
    public static var transport: Transport = .Auto
    
    public class func connect(url: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) -> SignalR? {
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
            let temp = NSURL(fileURLWithPath: NSTemporaryDirectory())
            let jqueryTempURL = temp.URLByAppendingPathComponent("jquery-2.1.3.min.js")
            let signalRTempURL = temp.URLByAppendingPathComponent("jquery.signalr-\(signalRVersion).min")
            let jsTempURL = temp.URLByAppendingPathComponent("SwiftR.js")
            
            let fileManager = NSFileManager.defaultManager()
            
            do {
                if let path = jqueryTempURL.path where fileManager.fileExistsAtPath(path) {
                    try fileManager.removeItemAtURL(jqueryTempURL)
                }
                if let path = signalRTempURL.path where fileManager.fileExistsAtPath(path) {
                    try fileManager.removeItemAtURL(signalRTempURL)
                }
                if let path = jsTempURL.path where fileManager.fileExistsAtPath(path) {
                    try fileManager.removeItemAtURL(jsTempURL)
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
    
    class func stringify(obj: AnyObject) -> String? {
        // Using an array to start with a valid top level type for NSJSONSerialization
        let arr = [obj]
        if let data = try? NSJSONSerialization.dataWithJSONObject(arr, options: NSJSONWritingOptions()) {
            if let str = NSString(data: data, encoding: NSUTF8StringEncoding) as? String {
                // Strip the array brackets to be left with the desired value
                let range = str.startIndex.advancedBy(1) ..< str.endIndex.advancedBy(-1)
                return str.substringWithRange(range)
            }
        }
        return nil
    }
}

public class SignalR: NSObject, SwiftRWebDelegate {
    var webView: SwiftRWebView!
    var wkWebView: WKWebView!

    var baseUrl: String
    var connectionType: ConnectionType
    
    var readyHandler: SignalR -> ()
    var hubs = [String: Hub]()

    public var state: State = .Disconnected
    public var connectionID: String?
    public var received: (AnyObject? -> ())?
    public var starting: (() -> ())?
    public var connected: (() -> ())?
    public var disconnected: (() -> ())?
    public var connectionSlow: (() -> ())?
    public var connectionFailed: (() -> ())?
    public var reconnecting: (() -> ())?
    public var reconnected: (() -> ())?
    public var error: (AnyObject? -> ())?
    
    public var queryString: AnyObject? {
        didSet {
            if let qs: AnyObject = queryString {
                if let jsonData = try? NSJSONSerialization.dataWithJSONObject(qs, options: NSJSONWritingOptions()) {
                    let json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
                    runJavaScript("swiftR.connection.qs = \(json)")
                }
            } else {
                runJavaScript("swiftR.connection.qs = {}")
            }
        }
    }
    
    public var headers: [String: String]? {
        didSet {
            if let h = headers {
                if let jsonData = try? NSJSONSerialization.dataWithJSONObject(h, options: NSJSONWritingOptions()) {
                    let json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
                    runJavaScript("swiftR.headers = \(json)")
                }
            } else {
                runJavaScript("swiftR.headers = {}")
            }
        }
    }
    
    public var customUserAgent: String? {
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
    
    init(baseUrl: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) {
        self.baseUrl = baseUrl
        self.readyHandler = readyHandler
        self.connectionType = connectionType
        super.init()
        
        #if COCOAPODS
            let bundle = NSBundle(identifier: "org.cocoapods.SwiftR")!
        #elseif SWIFTR_FRAMEWORK
            let bundle = NSBundle(identifier: "com.adamhartford.SwiftR")!
        #else
            let bundle = NSBundle.mainBundle()
        #endif
        
        let jqueryURL = bundle.URLForResource("jquery-2.1.3.min", withExtension: "js")!
        let signalRURL = bundle.URLForResource("jquery.signalr-\(SwiftR.signalRVersion).min", withExtension: "js")!
        let jsURL = bundle.URLForResource("SwiftR", withExtension: "js")!
        
        if SwiftR.useWKWebView {
            var jqueryInclude = "<script src='\(jqueryURL.absoluteString)'></script>"
            var signalRInclude = "<script src='\(signalRURL.absoluteString)'></script>"
            var jsInclude = "<script src='\(jsURL.absoluteString)'></script>"
            
            // Loading file:// URLs from NSTemporaryDirectory() works on iOS, not OS X.
            // Workaround on OS X is to include the script directly.
            #if os(iOS)
                if #available(iOS 9.0, *) {
                    let temp = NSURL(fileURLWithPath: NSTemporaryDirectory())
                    let jqueryTempURL = temp.URLByAppendingPathComponent("jquery-2.1.3.min.js")
                    let signalRTempURL = temp.URLByAppendingPathComponent("jquery.signalr-\(SwiftR.signalRVersion).min")
                    let jsTempURL = temp.URLByAppendingPathComponent("SwiftR.js")
                    
                    let fileManager = NSFileManager.defaultManager()
                    
                    do {
                        if fileManager.fileExistsAtPath(jqueryTempURL.path!) {
                            try fileManager.removeItemAtURL(jqueryTempURL)
                        }
                        if fileManager.fileExistsAtPath(signalRTempURL.path!) {
                            try fileManager.removeItemAtURL(signalRTempURL)
                        }
                        if fileManager.fileExistsAtPath(jsTempURL.path!) {
                            try fileManager.removeItemAtURL(jsTempURL)
                        }
                    } catch {
                        print("Failed to remove existing temp JavaScript")
                    }
                    
                    do {
                        try fileManager.copyItemAtURL(jqueryURL, toURL: jqueryTempURL)
                        try fileManager.copyItemAtURL(signalRURL, toURL: signalRTempURL)
                        try fileManager.copyItemAtURL(jsURL, toURL: jsTempURL)
                    } catch {
                        print("Failed to copy JavaScript to temp dir")
                    }
                    
                    jqueryInclude = "<script src='\(jqueryTempURL.absoluteString)'></script>"
                    signalRInclude = "<script src='\(signalRTempURL.absoluteString)'></script>"
                    jsInclude = "<script src='\(jsTempURL.absoluteString)'></script>"
                }
            #else
                let jqueryString = try! NSString(contentsOfURL: jqueryURL, encoding: NSUTF8StringEncoding)
                let signalRString = try! NSString(contentsOfURL: signalRURL, encoding: NSUTF8StringEncoding)
                let jsString = try! NSString(contentsOfURL: jsURL, encoding: NSUTF8StringEncoding)
                
                jqueryInclude = "<script>\(jqueryString)</script>"
                signalRInclude = "<script>\(signalRString)</script>"
                jsInclude = "<script>\(jsString)</script>"
            #endif
            
            let config = WKWebViewConfiguration()
            config.userContentController.addScriptMessageHandler(self, name: "interOp")
            #if !os(iOS)
                //config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            #endif
            wkWebView = WKWebView(frame: CGRectZero, configuration: config)
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
    
    public func createHubProxy(name: String) -> Hub {
        let hub = Hub(name: name, connection: self)
        hubs[name.lowercaseString] = hub
        return hub
    }
    
    public func send(data: AnyObject?) {
        var json = "null"
        if let d: AnyObject = data {
            if let val = SwiftR.stringify(d) {
                json = val
            }
        }
        runJavaScript("swiftR.connection.send(\(json))")
    }

    public func start() {
        runJavaScript("start()")
    }
    
    public func stop() {
        runJavaScript("swiftR.connection.stop()")
    }
    
    func shouldHandleRequest(request: NSURLRequest) -> Bool {
        if request.URL!.absoluteString.hasPrefix("swiftr://") {
            let id = (request.URL!.absoluteString as NSString).substringFromIndex(9)
            let msg = webView.stringByEvaluatingJavaScriptFromString("readMessage('\(id)')")!
            let data = msg.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            let json: AnyObject = try! NSJSONSerialization.JSONObjectWithData(data, options: [])
            
            processMessage(json)

            return false
        }
        
        return true
    }
    
    func processMessage(json: AnyObject) {
        if let message = json["message"] as? String {
            switch message {
            case "ready":
                let isHub = connectionType == .Hub ? "true" : "false"
                runJavaScript("swiftR.transport = '\(SwiftR.transport.stringValue)'")
                runJavaScript("initialize('\(baseUrl)', \(isHub))")
                readyHandler(self)
                runJavaScript("start()")
            case "starting":
                state = .Connecting
                starting?()
            case "connected":
                state = .Connected
                connectionID = json["connectionId"] as? String
                connected?()
            case "disconnected":
                state = .Disconnected
                disconnected?()
            case "connectionSlow":
                connectionSlow?()
            case "connectionFailed":
                connectionFailed?()
            case "reconnecting":
                state = .Connecting
                reconnecting?()
            case "reconnected":
                state = .Connected
                reconnected?()
            case "invokeHandler":
                let hubName = json["hub"] as! String
                if let hub = hubs[hubName] {
                    let uuid = json["id"] as! String
                    let result = json["result"]
                    let error = json["error"] as AnyObject?
                    if let callback = hub.invokeHandlers[uuid] {
                        callback(result: result, error: error)
                        hub.invokeHandlers.removeValueForKey(uuid)
                    } else if let e = error {
                        print("SwiftR invoke error: \(e)")
                    }
                }
            case "error":
                if let err: AnyObject = json["error"] {
                    error?(err)
                } else {
                    error?(nil)
                }
            default:
                break
            }
        } else if let data: AnyObject = json["data"] {
            received?(data)
        } else if let hubName = json["hub"] as? String {
            let callbackID = json["id"] as? String
            let method = json["method"] as? String
            let arguments = json["arguments"] as? [AnyObject]
            let hub = hubs[hubName]
            
            if let method = method, callbackID = callbackID, handlers = hub?.handlers[method], handler = handlers[callbackID] {
                handler(arguments)
            }
        }
    }
    
    func runJavaScript(script: String, callback: (AnyObject! -> ())? = nil) {
        if SwiftR.useWKWebView {
            wkWebView.evaluateJavaScript(script, completionHandler: { (result, _)  in
                callback?(result)
            })
        } else {
            let result = webView.stringByEvaluatingJavaScriptFromString(script)
            callback?(result)
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    // http://stackoverflow.com/questions/26514090/wkwebview-does-not-run-javascriptxml-http-request-with-out-adding-a-parent-vie#answer-26575892
    public func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
        #if os(iOS)
            UIApplication.sharedApplication().keyWindow?.addSubview(wkWebView)
        #endif
    }
    
    // MARK: - WKScriptMessageHandler
    
    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let id = message.body as? String {
            wkWebView.evaluateJavaScript("readMessage('\(id)')", completionHandler: { [weak self] (msg, err) in
                if let m = msg {
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
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        return shouldHandleRequest(request)
    }
#else
    public func webView(webView: WebView!,
        decidePolicyForNavigationAction actionInformation: [NSObject : AnyObject]!,
        request: NSURLRequest!,
        frame: WebFrame!,
        decisionListener listener: WebPolicyDecisionListener!) {
            
            if shouldHandleRequest(request) {
                listener.use()
            }
    }
#endif
}

// MARK: - Hub

public class Hub {
    let name: String
    var handlers: [String: [String: [AnyObject]? -> ()]] = [:]
    var invokeHandlers: [String: (result: AnyObject?, error: AnyObject?) -> ()] = [:]
    
    public let connection: SignalR!
    
    init(name: String, connection: SignalR) {
        self.name = name
        self.connection = connection
    }
    
    public func on(method: String, callback: [AnyObject]? -> ()) {
        let callbackID = NSUUID().UUIDString
        
        if handlers[method] == nil {
            handlers[method] = [:]
        }
        
        handlers[method]?[callbackID] = callback
        connection.runJavaScript("addHandler('\(callbackID)', '\(name)', '\(method)')")
    }
    
    public func invoke(method: String, arguments: [AnyObject]? = nil, callback: ((result: AnyObject?, error: AnyObject?) -> ())? = nil) {
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
        
        let args = jsonArguments.joinWithSeparator(", ")
        
        let uuid = NSUUID().UUIDString
        if let handler = callback {
            invokeHandlers[uuid] = handler
        }
        
        let doneJS = "function() { postMessage({ message: 'invokeHandler', hub: '\(name.lowercaseString)', id: '\(uuid)', result: arguments[0] }); }"
        let failJS = "function() { postMessage({ message: 'invokeHandler', hub: '\(name.lowercaseString)', id: '\(uuid)', error: processError(arguments[0]) }); }"
        let js = args.isEmpty
            ? "ensureHub('\(name)').invoke('\(method)').done(\(doneJS)).fail(\(failJS))"
            : "ensureHub('\(name)').invoke('\(method)', \(args)).done(\(doneJS)).fail(\(failJS))"
        
        connection.runJavaScript(js)
    }
    
}

public enum SignalRVersion : CustomStringConvertible {
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
