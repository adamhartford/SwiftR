//
//  SwiftR.swift
//  SwiftR
//
//  Created by Adam Hartford on 4/13/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Foundation
import WebKit

public class SwiftR: NSObject, WKScriptMessageHandler {

    var webView = WKWebView()
    var url: String!
    
    var ready = false
    var connected = false
    
    var readyBuffer = [String]()
    var connectedBuffer = [String]()
    
    var handlers: Dictionary<Hub, AnyObject? -> ()> = [:]
    
    public convenience init(url: String) {
        self.init()
        
        self.url = url
        
        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(self, name: "interOp")
        //config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        webView = WKWebView(frame: CGRectZero, configuration: config)
        
        let bundle = NSBundle(identifier: "com.adamhartford.SwiftR")!
        let jqueryURL = bundle.URLForResource("jquery-2.1.3.min", withExtension: "js")!
        let signalRURL = bundle.URLForResource("jquery.signalR-2.2.0.min", withExtension: "js")!
        let jsURL = bundle.URLForResource("SwiftR", withExtension: "js")!
        
        // Loading file:// URLs from NSTemporaryDirectory() works on iOS, not OS X.
        // Workaround on OS X is to include the script directly.

#if os(iOS)
        let temp = NSURL(fileURLWithPath: NSTemporaryDirectory())!
        let jqueryTempURL = temp.URLByAppendingPathComponent("jquery-2.1.3.min.js")
        let signalRTempURL = temp.URLByAppendingPathComponent("jquery.signalR-2.2.0.min.js")
        let jsTempURL = temp.URLByAppendingPathComponent("SwiftR.js")
        
        let fileManager = NSFileManager.defaultManager()
        fileManager.removeItemAtURL(jqueryTempURL, error: nil)
        fileManager.removeItemAtURL(signalRTempURL, error: nil)
        fileManager.removeItemAtURL(jsTempURL, error: nil)
        
        fileManager.copyItemAtURL(jqueryURL, toURL: jqueryTempURL, error: nil)
        fileManager.copyItemAtURL(signalRURL, toURL: signalRTempURL, error: nil)
        fileManager.copyItemAtURL(jsURL, toURL: jsTempURL, error: nil)
    
        let jqueryInclude = "<script src='\(jqueryURL.absoluteString!)'></script>"
        let signalRInclude = "<script src='\(signalRURL.absoluteString!)'></script>"
        let jsInclude = "<script src='\(jsURL.absoluteString!)'></script>"
        let hubsInclude = "<script src='\(url)/hubs'></script>"
#else
        var jqueryString = NSString(contentsOfURL: jqueryURL, encoding: NSUTF8StringEncoding, error: nil)!
        var signalRString = NSString(contentsOfURL: signalRURL, encoding: NSUTF8StringEncoding, error: nil)!
        var jsString = NSString(contentsOfURL: jsURL, encoding: NSUTF8StringEncoding, error: nil)!
        
        jqueryString = jqueryString.stringByReplacingOccurrencesOfString("\n", withString: "")
        signalRString = signalRString.stringByReplacingOccurrencesOfString("\n", withString: "")
        jsString = jsString.stringByReplacingOccurrencesOfString("\n", withString: "")
        
        let jqueryInclude = "<script>\(jqueryString)</script>"
        let signalRInclude = "<script>\(signalRString)</script>"
        let jsInclude = "<script>\(jsString)</script>"
        let hubsInclude = "<script src='\(url)/hubs'></script>"
#endif
        
        let html = "<!doctype html><html><head></head><body>"
            + "\(jqueryInclude)\(signalRInclude)\(jsInclude)\(hubsInclude)"
            + "</body></html>"
        
        webView.loadHTMLString(html, baseURL: NSBundle.mainBundle().bundleURL)
    }
    
    public func invoke(hub: String, method: String, parameters: [AnyObject]?) {
        var jsonParams = [String]()
        
        if let params = parameters {
            for param in params {
                if param is String {
                    jsonParams.append("'\(param)'")
                } else if let data = NSJSONSerialization.dataWithJSONObject(param, options: NSJSONWritingOptions.allZeros, error: nil) {
                    jsonParams.append(NSString(data: data, encoding: NSUTF8StringEncoding) as String!)
                }
            }
        }
        
        let args = ",".join(jsonParams)
        let js = "$.connection.\(hub).server.\(method)(\(args))"
        
        if connected {
            flushBuffer(&connectedBuffer)
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            connectedBuffer.append(js)
        }
    }
    
    public func addHandler(hub: String, event: String, handler: AnyObject? -> ()) {
        let js = "$.connection.\(hub).client.\(event) = function() { processResponse('\(hub)', '\(event)', arguments); }"
        
        let h = Hub(name: hub, event: event)
        handlers[h] = handler
        
        if ready {
            flushBuffer(&readyBuffer)
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            readyBuffer.append(js)
        }
    }
    
    public func start() {
        let js = "connect('\(url)')"
        
        if ready {
            flushBuffer(&readyBuffer)
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            readyBuffer.append(js)
        }
    }
    
    // MARK: - Private
    
    func flushBuffer(inout buffer: [String]) {
        if buffer.count > 0 {
            for js in buffer {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            buffer.removeAll(keepCapacity: false)
        }
    }
    
    // MARK: - WKScriptMessageHandler functions
    
    public func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let m = message.body as? String {
            if m == "ready" {
                ready = true
                flushBuffer(&readyBuffer)
            } else if m == "connected" {
                connected = true
                flushBuffer(&connectedBuffer)
            }
        } else if let m = message.body as? [String: AnyObject] {
            let hub = m["hub"] as! String
            let event = m["func"] as! String
            let h = Hub(name: hub, event: event)
            handlers[h]?(m["args"])
        }
    }
}

// Mark: - Hub

struct Hub: Hashable {
    let name: String
    let event: String
}

// MARK: Hashable

extension Hub: Hashable {
    var hashValue: Int {
        return name.hashValue ^ event.hashValue
    }
}

// MARK: Equatable

func ==(lhs: Hub, rhs: Hub) -> Bool {
    return lhs.name == rhs.name && rhs.event == rhs.event
}