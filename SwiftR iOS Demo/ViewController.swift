//
//  ViewController.swift
//  SwiftR iOS Demo
//
//  Created by Adam Hartford on 4/16/15.
//  Copyright (c) 2015 Adam Hartford. All rights reserved.
//

import UIKit
import SwiftR

class ViewController: UIViewController {
    
    @IBOutlet weak var startButton: UIButton!
    
    var simpleHub: Hub!
    var complexHub: Hub!
    
    var hubConnection: SignalR!
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
        hubConnection = SwiftR.connect("http://myserver.com:8080") { [weak self] connection in
            connection.queryString = ["foo": "bar"]
            connection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2": "Value2"]
            
            self?.simpleHub = connection.createHubProxy("simpleHub")
            self?.complexHub = connection.createHubProxy("complexHub")
            
            self?.simpleHub.on("notifySimple", parameters: ["message", "details"]) { args in
                let message = args!["message"] as! String
                let detail = args!["details"] as! String
                println("Message: \(message)\nDetail: \(detail)")
            }
            
            self?.complexHub.on("notifyComplex") { args in
                let m: AnyObject = args!["0"] as AnyObject!
                println(m)
            }
            
            // SignalR events
            
            connection.starting = { [weak self] in
                println("Starting...")
                self?.startButton.enabled = false
                self?.startButton.setTitle("Connecting...", forState: .Normal)
            }
            
            connection.reconnecting = { [weak self] in
                println("Reconnecting...")
                self?.startButton.enabled = false
                self?.startButton.setTitle("Reconnecting...", forState: .Normal)
            }
            
            connection.connected = { [weak self] in
                println("Connected. Connection ID: \(connection.connectionID!)")
                self?.startButton.enabled = true
                self?.startButton.setTitle("Stop", forState: .Normal)
            }
            
            connection.reconnected = { [weak self] in
                println("Reconnected. Connection ID: \(connection.connectionID!)")
                self?.startButton.enabled = true
                self?.startButton.setTitle("Stop", forState: .Normal)
            }
            
            connection.disconnected = { [weak self] in
                println("Disconnected.")
                self?.startButton.enabled = true
                self?.startButton.setTitle("Start", forState: .Normal)
            }
            
            connection.connectionSlow = { println("Connection slow...") }
            connection.error = { error in println(error!) }
        }
        
        // Persistent connection...
        // Uncomment when using persitent connections on your SignalR server
//        persistentConnection = SwiftR.connect("http://myserver.com:8080/echo", connectionType: .Persistent) { connection in
//            connection.received = { data in
//                println(data!)
//            }
//        }
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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
    
    @IBAction func startStop(sender: AnyObject?) {
        switch hubConnection.state {
        case .Disconnected:
            hubConnection.start() // or... SwiftR.startAll()
        case .Connected:
            hubConnection.stop() // or... SwiftR.stopAll()
        default:
            break
        }
    }
}

