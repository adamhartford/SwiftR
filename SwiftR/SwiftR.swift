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
}

public class SignalR: NSObject, SwiftRWebDelegate {
    var webView: SwiftRWebView!
    var wkWebView: WKWebView!

    var baseUrl: String
    var connectionType: ConnectionType
    
    var readyHandler: SignalR -> ()
    var hubs = [String: Hub]()
    
    public var received: (AnyObject? -> ())?
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
                if let jsonData = NSJSONSerialization.dataWithJSONObject(qs, options: NSJSONWritingOptions.allZeros, error: nil) {
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
                if let jsonData = NSJSONSerialization.dataWithJSONObject(h, options: NSJSONWritingOptions.allZeros, error: nil) {
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
                let temp = NSURL(fileURLWithPath: NSTemporaryDirectory())!
                let jqueryTempURL = temp.URLByAppendingPathComponent("jquery-2.1.3.min.js")
                let signalRTempURL = temp.URLByAppendingPathComponent("jquery.signalR-2.2.0.min")
                let jsTempURL = temp.URLByAppendingPathComponent("SwiftR.js")
                
                let fileManager = NSFileManager.defaultManager()
                fileManager.removeItemAtURL(jqueryTempURL, error: nil)
                fileManager.removeItemAtURL(signalRTempURL, error: nil)
                fileManager.removeItemAtURL(jsTempURL, error: nil)
                
                fileManager.copyItemAtURL(jqueryURL, toURL: jqueryTempURL, error: nil)
                fileManager.copyItemAtURL(signalRURL, toURL: signalRTempURL, error: nil)
                fileManager.copyItemAtURL(jsURL, toURL: jsTempURL, error: nil)
                
                let jqueryInclude = "<script src='\(jqueryTempURL.absoluteString!)'></script>"
                let signalRInclude = "<script src='\(signalRTempURL.absoluteString!)'></script>"
                let jsInclude = "<script src='\(jsTempURL.absoluteString!)'></script>"
            #else
                let jqueryString = NSString(contentsOfURL: jqueryURL, encoding: NSUTF8StringEncoding, error: nil)!
                let signalRString = NSString(contentsOfURL: signalRURL, encoding: NSUTF8StringEncoding, error: nil)!
                let jsString = NSString(contentsOfURL: jsURL, encoding: NSUTF8StringEncoding, error: nil)!
                
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
            let jqueryInclude = "<script src='\(jqueryURL.absoluteString!)'></script>"
            let signalRInclude = "<script src='\(signalRURL.absoluteString!)'></script>"
            let jsInclude = "<script src='\(jsURL.absoluteString!)'></script>"
            
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
        let hub = Hub(name: name, signalR: self)
        hubs[name.lowercaseString] = hub
        return hub
    }
    
    public func send(data: AnyObject?) {
        var json = "null"
        if let d: AnyObject = data {
            if d is String {
                json = "'\(d)'"
            } else if let jsonData = NSJSONSerialization.dataWithJSONObject(d, options: NSJSONWritingOptions.allZeros, error: nil) {
                json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
            }
        }
        runJavaScript("swiftR.connection.send(\(json))")
    }
    
    func shouldHandleRequest(request: NSURLRequest) -> Bool {
        if request.URL!.absoluteString!.hasPrefix("swiftr://") {
            let id = (request.URL!.absoluteString! as NSString).substringFromIndex(9)
            let msg = webView.stringByEvaluatingJavaScriptFromString("readMessage(\(id))")!
            let data = msg.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            let json: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: .allZeros, error: nil)!
            
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
            case "connected":
                connected?()
            case "disconnected":
                disconnected?()
            case "connectionSlow":
                connectionSlow?()
            case "connectionFailed":
                connectionFailed?()
            case "reconnecting":
                reconnecting?()
            case "reconnected":
                reconnected?()
            case "error":
                if let err: AnyObject = json["error"] {
                    error?(err["context"])
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
        let id = message.body as! String
        wkWebView.evaluateJavaScript("readMessage(\(id))", completionHandler: { [weak self] (msg, _) in
            let data = msg.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            let json: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: .allZeros, error: nil)!
            self?.processMessage(json)
        })
    }
    
    // MARK: - Web delegate methods
    
#if os(iOS)
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        return shouldHandleRequest(request)
    }
#else
    public override func webView(webView: WebView!,
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
    let signalR: SignalR!
    
    init(name: String, signalR: SignalR) {
        self.name = name
        self.signalR = signalR
    }
    
    public func on(method: String, parameters: [String]? = nil, callback: AnyObject? -> ()) {
        handlers[method] = callback
        
        var p = "null"
        if let params = parameters {
            p = "['" + "','".join(params) + "']"
        }
        
        signalR.runJavaScript("addHandler('\(name)', '\(method)', \(p))")
    }
    
    public func invoke(method: String, arguments: [AnyObject]?) {
        var jsonArguments = [String]()
        
        if let args = arguments {
            for arg in args {
                if arg is String {
                    jsonArguments.append("'\(arg)'")
                } else if let data = NSJSONSerialization.dataWithJSONObject(arg, options: NSJSONWritingOptions.allZeros, error: nil) {
                    jsonArguments.append(NSString(data: data, encoding: NSUTF8StringEncoding) as! String)
                }
            }
        }
        
        let args = ",".join(jsonArguments)
        let js = "swiftR.hubs.\(name).invoke('\(method)', \(args))"
        
        signalR.runJavaScript(js)
    }
    
}

#if os(iOS)
    typealias SwiftRWebView = UIWebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler, UIWebViewDelegate {}
#else
    typealias SwiftRWebView = WebView
    public protocol SwiftRWebDelegate: WKNavigationDelegate, WKScriptMessageHandler {}
#endif
