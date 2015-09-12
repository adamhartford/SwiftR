//
//  ViewController.swift
//  SwiftR Mac Demo
//
//  Created by Adam Hartford on 4/16/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import Cocoa
import SwiftR

class ViewController: NSViewController {
    
    var simpleHub: Hub!
    var complexHub: Hub!
    
    var persistentConnection: SignalR!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Make sure myserver.com is mapped to 127.0.0.1 in /etc/hosts
        // Or change myserver.com to localhost or IP below
        
        // Default is false
        SwiftR.useWKWebView = true
        
        // Default is .Auto
        SwiftR.transport = .ServerSentEvents
        
        // Hubs...
        SwiftR.connect("http://myserver.com:8080") { [weak self] connection in
            connection.queryString = ["foo": "bar"]
            connection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2": "Value2"]
            
            self?.simpleHub = connection.createHubProxy("simpleHub")
            self?.complexHub = connection.createHubProxy("complexHub")
            
            self?.simpleHub.on("notifySimple", parameters: ["message", "details"]) { args in
                let message = args!["message"] as! String
                let detail = args!["details"] as! String
                println("Message: \(message)\nDetail: \(detail)")
            }
            
            self?.complexHub.on("notifyComplex") { (response) in
                let m: AnyObject = response!["0"] as AnyObject!
                println(m)
            }
            
            // SignalR events
            connection.starting = { println("Starting...") }
            connection.connected = { println("Connected. Connection ID: \(connection.connectionID!)") }
            connection.connectionSlow = { println("Connection Slow...") }
            connection.reconnecting = { println("Reconnecting...") }
            connection.reconnected = { println("Reconnected.") }
            connection.disconnected = { println("Disconnected.") }
            connection.error = { error in println(error!) }
        }
        
        // Persistent connection...
        // Uncomment when using persitent connections on your SignalR server
//        persistentConnection = SwiftR.connect("http://myserver.com:8080/echo", connectionType: .Persistent) { connection in
//            connection.received = { (data) in
//                println(data!)
//            }
//        }
        
    }
    
    override var representedObject: AnyObject? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func sendSimpleMessage(sender: AnyObject?) {
        
        simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"])
    }
    
    @IBAction func sendComplexMessage(sender: AnyObject?) {
        let message = [
            "messageId": 1,
            "message": "Complex Test",
            "detail": "This is a complex message",
            "items": ["foo", "bar", "baz"]
        ]
        
        complexHub.invoke("sendComplex", arguments: [message])
    }

    @IBAction func sendData(sender: AnyObject?) {
        persistentConnection.send("Persistent Connection Test")
    }
    
}

