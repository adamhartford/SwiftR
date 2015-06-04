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

public final class SwiftR {
    static var connections = [SignalR]()
    
    public class func connect(url: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) -> SignalR? {
        let signalR = SignalR(url: url, connectionType: connectionType, readyHandler: readyHandler)
        connections.append(signalR)
        return signalR
    }
}

public class SignalR: NSObject, UIWebViewDelegate {
    var webView: UIWebView!
    var url: String
    var connectionType: ConnectionType
    
    var readyHandler: SignalR -> ()
    var hubs = [String: Hub]()
    
    public var received: (AnyObject? -> ())?
    
    public var queryString: AnyObject? {
        didSet {
            if let qs: AnyObject = queryString {
                if let jsonData = NSJSONSerialization.dataWithJSONObject(qs, options: NSJSONWritingOptions.allZeros, error: nil) {
                    let json = NSString(data: jsonData, encoding: NSUTF8StringEncoding) as! String
                    webView.stringByEvaluatingJavaScriptFromString("connection.qs = \(json)")
                }
            }
        }
    }
    
    init(url: String, connectionType: ConnectionType = .Hub, readyHandler: SignalR -> ()) {
        self.url = url
        self.readyHandler = readyHandler
        self.connectionType = connectionType
        super.init()
        
        webView = UIWebView()
        webView.delegate = self
        
#if COCOAPODS
        let bundle = NSBundle(identifier: "org.cocoapods.SwiftR")!
#else
        let bundle = NSBundle(identifier: "com.adamhartford.SwiftR")!
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
        
        webView.loadHTMLString(html, baseURL: NSBundle.mainBundle().bundleURL)
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
        webView.stringByEvaluatingJavaScriptFromString("connection.send(\(json))")
    }
    
    // MARK: - UIWebViewDelegate methods
    
    public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        if request.URL!.absoluteString!.hasPrefix("swiftR://") {
            var s = (request.URL!.absoluteString! as NSString).substringFromIndex(9)
            s = webView.stringByEvaluatingJavaScriptFromString("decodeURIComponent('\(s)')")!
            let data = s.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!
            let json: AnyObject = NSJSONSerialization.JSONObjectWithData(data, options: .allZeros, error: nil)!
            
            if let message = json["message"] as? String {
                switch message {
                case "ready":
                    let isHub = connectionType == .Hub ? "true" : "false"
                    webView.stringByEvaluatingJavaScriptFromString("initialize('\(url)',\(isHub))")
                    readyHandler(self)
                    webView.stringByEvaluatingJavaScriptFromString("start()")
                case "connected":
                    println(message)
                case "disconnected":
                    println(message)
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
    
    public func webViewDidStartLoad(webView: UIWebView) {
        //println("start")
    }
    
    public func webViewDidFinishLoad(webView: UIWebView) {
        //println("end")
    }
    
    public func webView(webView: UIWebView, didFailLoadWithError error: NSError) {
        //println(error)
    }
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
        ensureHub()
        handlers[method] = callback
        
        var p = "null"
        if let params = parameters {
            p = "['" + "','".join(params) + "']"
        }
        
        signalR.webView.stringByEvaluatingJavaScriptFromString("addHandler(\(name), '\(method)', \(p))")
    }
    
    public func invoke(method: String, arguments: [AnyObject]?) {
        ensureHub()
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
        let js = "\(name).invoke('\(method)', \(args))"
        signalR.webView.stringByEvaluatingJavaScriptFromString(js)
    }
    
    func ensureHub() {
        let js = "if (typeof \(name) == 'undefined') \(name) = connection.createHubProxy('\(name)')"
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
