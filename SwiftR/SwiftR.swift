//
//  SwiftR.swift
//  SwiftR
//
//  Created by Adam Hartford on 4/13/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Foundation
import WebKit

struct Constants {
    static let kSwiftR = "_SwiftR"
}

public enum ConnectionType {
    case Hub
    case Persistent
}

public final class SwiftR: NSObject {
    static var connections = [SignalR]()
    
    static var once = dispatch_once_t()
    
    public class func connect(url: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) -> SignalR? {
        dispatch_once(&once) {
            NSURLProtocol.registerClass(SwiftRURLProtocol)
        }
        
        let signalR = SignalR(baseUrl: url, connectionType: connectionType, readyHandler: readyHandler)
        connections.append(signalR)
        return signalR
    }
}

public class SignalR: NSObject, SwiftRProtocol {
    var webView: SwiftRWebView!

    var baseUrl: String
    var connectionType: ConnectionType
    
    var readyHandler: SignalR -> ()
    var hubs = [String: Hub]()
    
    public var received: (AnyObject? -> ())?
    
    public var queryString: AnyObject? {
        didSet {
            if var qs = queryString as? [String: AnyObject] {
                qs[Constants.kSwiftR] = 1
                if let jsonData = NSJSONSerialization.dataWithJSONObject(qs, options: NSJSONWritingOptions.allZeros, error: nil) {
                    let json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
                    webView.stringByEvaluatingJavaScriptFromString("swiftR.connection.qs = \(json)")
                }
            }
        }
    }
    
    var headers: [String: String] = [:]
    
    init(baseUrl: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) {
        self.baseUrl = baseUrl
        self.readyHandler = readyHandler
        self.connectionType = connectionType
        super.init()
        
        webView = SwiftRWebView()
#if os(iOS)
        webView.delegate = self
#else
        webView.policyDelegate = self
#endif
        
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
        
        let jqueryInclude = "<script src='\(jqueryURL.absoluteString!)'></script>"
        let signalRInclude = "<script src='\(signalRURL.absoluteString!)'></script>"
        let jsInclude = "<script src='\(jsURL.absoluteString!)'></script>"
        
        let html = "<!doctype html><html><head></head><body>"
            + "\(jqueryInclude)\(signalRInclude)\(jsInclude))"
            + "</body></html>"
        
#if os(iOS)
        webView.loadHTMLString(html, baseURL: bundle.bundleURL)
#else
        webView.mainFrame.loadHTMLString(html, baseURL: bundle.bundleURL)
#endif
    }
    
    public func setValue(value: String, forHTTPHeaderField: String) {
        headers[forHTTPHeaderField] = value
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
        webView.stringByEvaluatingJavaScriptFromString("swiftR.connection.send(\(json))")
    }
    
    func shouldHandleRequest(request: NSURLRequest) -> Bool {
        if request.URL!.absoluteString!.hasPrefix("swiftR://") {
            var s = (request.URL!.absoluteString! as NSString).substringFromIndex(9)
            s = webView.stringByEvaluatingJavaScriptFromString("decodeURIComponent(\"\(s)\")")!
            let data = s.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            let json: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: .allZeros, error: nil)!
            
            // TODO callbacks
            if let message = json["message"] as? String {
                switch message {
                case "ready":
                    let isHub = connectionType == .Hub ? "true" : "false"
                    webView.stringByEvaluatingJavaScriptFromString("initialize('\(baseUrl)',\(isHub))")
                    webView.stringByEvaluatingJavaScriptFromString("swiftR.connection.qs = { \(Constants.kSwiftR): 1 }")
                    readyHandler(self)
                    webView.stringByEvaluatingJavaScriptFromString("start()")
                case "connected":
                    println(message)
                case "disconnected":
                    println(message)
                case "connectionSlow":
                    println("connectionSlow")
                case "connectionFailed":
                    println("connectionFailed")
                case "error":
                    if let error: AnyObject = json["error"] {
                        if let errorData = NSJSONSerialization.dataWithJSONObject(error, options: NSJSONWritingOptions.allZeros, error: nil) {
                            let err = NSString(data: errorData, encoding: NSUTF8StringEncoding) as! String
                            println("error: \(err)")
                        } else {
                            println("error")
                        }
                    } else {
                        println("error")
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
            
            return false
        }
        
        return true
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
        
        signalR.webView.stringByEvaluatingJavaScriptFromString("addHandler('\(name)', '\(method)', \(p))")
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
        
        signalR.webView.stringByEvaluatingJavaScriptFromString(js)
    }
    
}

extension Hub: Hashable {
    public var hashValue: Int {
        return name.hashValue
    }
}

public func==(lhs: Hub, rhs: Hub) -> Bool {
    return lhs.name == rhs.name
}

class SwiftRURLProtocol: NSURLProtocol, NSURLConnectionDataDelegate {
    var connection: NSURLConnection!
    
    override class func canonicalRequestForRequest(request: NSURLRequest) -> NSURLRequest {
        var mutableRequest = request.mutableCopy() as! NSMutableURLRequest
        NSURLProtocol.setProperty(Constants.kSwiftR, forKey: Constants.kSwiftR, inRequest: mutableRequest)
        if let signalR = request.signalR {
            for (h,v) in signalR.headers {
                mutableRequest.setValue(v, forHTTPHeaderField: h)
            }
        }
        return mutableRequest
    }
    
    override class func canInitWithRequest(request: NSURLRequest) -> Bool {
        if NSURLProtocol.propertyForKey(Constants.kSwiftR, inRequest: request) != nil {
            return false
        }
        return request.signalR != nil
    }
    
    override func startLoading() {
        connection = NSURLConnection(request: request, delegate: self)
        connection.start()
    }
    
    override func stopLoading() {
        connection.cancel()
    }
    
    func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        client?.URLProtocol(self, didReceiveResponse: response, cacheStoragePolicy: .Allowed)
    }
    
    func connection(connection: NSURLConnection, didReceiveData data: NSData) {
        client?.URLProtocol(self, didLoadData: data)
    }
    
    func connectionDidFinishLoading(connection: NSURLConnection) {
        client?.URLProtocolDidFinishLoading(self)
    }
}

extension NSURLRequest {
    var signalR: SignalR? {
        let url = URL!.absoluteString!
        for connection in SwiftR.connections {
            if url.hasPrefix(connection.baseUrl) && url.rangeOfString(Constants.kSwiftR) != nil {
                return connection
            }
        }
        return nil
    }
}

#if os(iOS)
    typealias SwiftRWebView = UIWebView
    public protocol SwiftRProtocol: UIWebViewDelegate {}
#else
    typealias SwiftRWebView = WebView
    public protocol SwiftRProtocol {}
#endif
