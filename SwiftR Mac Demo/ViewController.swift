//
//  ViewController.swift
//  SwiftR Mac Demo
//
//  Created by Adam Hartford on 4/16/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Cocoa
import SwiftR
import WebKit

class ViewController: NSViewController {
    
    var simpleHub: Hub!
    var complexHub: Hub!
    
    var hubConnection: SignalR!
    var persistentConnection: SignalR!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Make sure myserver.com is mapped to 127.0.0.1 in /etc/hosts
        // Or change myserver.com to localhost or IP below
        
        // Hubs...
        hubConnection = SignalR("http://myserver.com:5000")
        hubConnection.useWKWebView = true
        hubConnection.transport = .serverSentEvents
        hubConnection.queryString = ["foo": "bar"]
        hubConnection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2": "Value2"]
        
        // This only works with WKWebView on OS X >= 10.11, or with WebView on OS X >= 10.2.
        hubConnection.customUserAgent = "SwiftR Mac Demo App"
        
        simpleHub = Hub("simpleHub")
        complexHub = Hub("complexHub")
        
        simpleHub.on("notifySimple") { args in
            let message = args![0] as! String
            let detail = args![1] as! String
            print("Message: \(message)\nDetail: \(detail)")
        }
        
        complexHub.on("notifyComplex") { args in
            let m: AnyObject = args![0] as AnyObject!
            print(m)
        }
        
        // SignalR events
        hubConnection.starting = { print("Starting...") }
        hubConnection.connected = { [weak self] in print("Connected. Connection ID: \(self!.hubConnection.connectionID!)") }
        hubConnection.connectionSlow = { print("Connection Slow...") }
        hubConnection.reconnecting = { print("Reconnecting...") }
        hubConnection.reconnected = { print("Reconnected.") }
        hubConnection.disconnected = { print("Disconnected.") }
        hubConnection.error = { error in print(error!) }
        
        hubConnection.start()
        
        // Persistent connection...
        // Uncomment when using persitent connections on your SignalR server
        persistentConnection = SignalR("http://myserver.com:5000/echo", connectionType: .persistent)
        persistentConnection.received = { (data) in
            print(data!)
        }
        persistentConnection.start()
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func sendSimpleMessage(_ sender: AnyObject?) {
        
        simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"])
    }
    
    @IBAction func sendComplexMessage(_ sender: AnyObject?) {
        let message = [
            "messageId": 1,
            "message": "Complex Test",
            "detail": "This is a complex message",
            "items": ["foo", "bar", "baz"]
        ] as [String : Any]
        
        complexHub.invoke("sendComplex", arguments: [message])
    }

    @IBAction func sendData(_ sender: AnyObject?) {
        persistentConnection.send("Persistent Connection Test")
    }
    
}

