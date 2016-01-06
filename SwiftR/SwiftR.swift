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
    
    class func checkConnections() {
        if connections.count == 0 {
            print("No active SignalR connections. Use SwiftR.connect(...) first.")
        }
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
        let signalRURL = bundle.URLForResource("jquery.signalR-2.2.0.min", withExtension: "js")!
        let jsURL = bundle.URLForResource("SwiftR", withExtension: "js")!
        
        if SwiftR.useWKWebView {
            // Loading file:// URLs from NSTemporaryDirectory() works on iOS, not OS X.
            // Workaround on OS X is to include the script directly.
            #if os(iOS)
                let temp = NSURL(fileURLWithPath: NSTemporaryDirectory())
                let jqueryTempURL = temp.URLByAppendingPathComponent("jquery-2.1.3.min.js")
                let signalRTempURL = temp.URLByAppendingPathComponent("jquery.signalR-2.2.0.min")
                let jsTempURL = temp.URLByAppendingPathComponent("SwiftR.js")
                
                let fileManager = NSFileManager.defaultManager()

                if fileManager.fileExistsAtPath(jqueryTempURL.path!) {
                    try! fileManager.removeItemAtURL(jqueryTempURL)
                }
                if fileManager.fileExistsAtPath(signalRTempURL.path!) {
                    try! fileManager.removeItemAtURL(signalRTempURL)
                }
                if fileManager.fileExistsAtPath(jsTempURL.path!) {
                    try! fileManager.removeItemAtURL(jsTempURL)
                }
                
                try! fileManager.copyItemAtURL(jqueryURL, toURL: jqueryTempURL)
                try! fileManager.copyItemAtURL(signalRURL, toURL: signalRTempURL)
                try! fileManager.copyItemAtURL(jsURL, toURL: jsTempURL)
                
                let jqueryInclude = "<script src='\(jqueryTempURL.absoluteString)'></script>"
                let signalRInclude = "<script src='\(signalRTempURL.absoluteString)'></script>"
                let jsInclude = "<script src='\(jsTempURL.absoluteString)'></script>"
            #else
                let jqueryString = try! NSString(contentsOfURL: jqueryURL, encoding: NSUTF8StringEncoding)
                let signalRString = try! NSString(contentsOfURL: signalRURL, encoding: NSUTF8StringEncoding)
                let jsString = try! NSString(contentsOfURL: jsURL, encoding: NSUTF8StringEncoding)
                
                let jqueryInclude = "<script>\(jqueryString)</script>"
                let signalRInclude = "<script>\(signalRString)</script>"
                let jsInclude = "<script>\(jsString)</script>"
            #endif
            
            let config = WKWebViewConfiguration()
            config.userContentController.addScriptMessageHandler(self, name: "interOp")
            #if !os(iOS)
                //config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            #endif
            wkWebView = WKWebView(frame: CGRectZero, configuration: config)
            wkWebView.navigationDelegate = self
            
            let html = "<!doctype html><html><head></head><body>"
                + "\(jqueryInclude)\(signalRInclude)\(jsInclude))"
                + "</body></html>"
            
            wkWebView.loadHTMLString(html, baseURL: bundle.bundleURL)
            return
        } else {
            let jqueryInclude = "<script src='\(jqueryURL.absoluteString)'></script>"
            let signalRInclude = "<script src='\(signalRURL.absoluteString)'></script>"
            let jsInclude = "<script src='\(jsURL.absoluteString)'></script>"
            
            let html = "<!doctype html><html><head></head><body>"
                + "\(jqueryInclude)\(signalRInclude)\(jsInclude))"
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
            if d is String {
                json = "'\(d)'"
            } else if d is NSNumber {
                json = "\(d)"
            } else if let jsonData = try? NSJSONSerialization.dataWithJSONObject(d, options: NSJSONWritingOptions()) {
                json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
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
                    let error = json["error"]
                    if let callback = hub.invokeHandlers[uuid] {
                        callback(result: result, error: error)
                        hub.invokeHandlers.removeValueForKey(uuid)
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
            let method = json["method"] as! String
            let arguments: AnyObject? = json["arguments"]
            let hub = hubs[hubName]
            hub?.handlers[method]?(arguments)
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
            wkWebView.evaluateJavaScript("readMessage('\(id)')", completionHandler: { [weak self] (msg, _) in
                if let data = msg?.dataUsingEncoding(NSUTF8StringEncoding) {
                    do {
                        let json: AnyObject = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                        self?.processMessage(json)
                    } catch {
                        // TODO
                        print("Failed to serialize JSON.")
                    }
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
    var handlers: [String: AnyObject? -> ()] = [:]
    var invokeHandlers: [String: (result: AnyObject?, error: AnyObject?) -> ()] = [:]
    
    public let connection: SignalR!
    
    init(name: String, connection: SignalR) {
        self.name = name
        self.connection = connection
    }
    
    public func on(method: String, parameters: [String]? = nil, callback: AnyObject? -> ()) {
        handlers[method] = callback
        
        var p = "null"
        if let params = parameters {
            p = "['" + params.joinWithSeparator("','") + "']"
        }
        
        connection.runJavaScript("addHandler('\(name)', '\(method)', \(p))")
    }
    
    public func invoke(method: String, arguments: [AnyObject]?, callback: ((result: AnyObject?, error: AnyObject?) -> ())? = nil) {
        var jsonArguments = [String]()
        
        if let args = arguments {
            for arg in args {
                if arg is String {
                    jsonArguments.append("'\(arg)'")
                } else if arg is NSNumber {
                    jsonArguments.append("\(arg)")
                } else if let data = try? NSJSONSerialization.dataWithJSONObject(arg, options: NSJSONWritingOptions()) {
                    jsonArguments.append(NSString(data: data, encoding: NSUTF8StringEncoding) as! String)
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
        let js = "swiftR.hubs.\(name).invoke('\(method)', \(args)).done(\(doneJS)).fail(\(failJS))"
        
        connection.runJavaScript(js)
    }
    
}

#if os(iOS)
    typealias SwiftRWebView = UIWebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler, UIWebViewDelegate {}
#else
    typealias SwiftRWebView = WebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler, WebPolicyDelegate {}
#endif
