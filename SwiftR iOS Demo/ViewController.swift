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
        SwiftR.transport = .serverSentEvents
        
        // Hubs...
        hubConnection = SwiftR.connect("http://myserver.com:5000") { [weak self] connection in
            connection.queryString = ["foo": "bar"]
            connection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2": "Value2"]
            
            // This only works with WKWebView on iOS >= 9
            // Otherwise, use NSUserDefaults.standardUserDefaults().registerDefaults(["UserAgent": "SwiftR iOS Demo App"])
            connection.customUserAgent = "SwiftR iOS Demo App"
            
            self?.simpleHub = connection.createHubProxy("simpleHub")
            self?.complexHub = connection.createHubProxy("complexHub")
            
            self?.simpleHub.on("notifySimple") { args in
                let message = args![0] as! String
                let detail = args![1] as! String
                print("Message: \(message)\nDetail: \(detail)\n")
            }
            
            self?.complexHub.on("notifyComplex") { args in
                let m: AnyObject = args![0] as AnyObject!
                print(m)
            }
            
            // SignalR events
            
            connection.starting = { [weak self] in
                print("Starting...")
                self?.startButton.isEnabled = false
                self?.startButton.setTitle("Connecting...", for: UIControlState())
            }
            
            connection.reconnecting = { [weak self] in
                print("Reconnecting...")
                self?.startButton.isEnabled = false
                self?.startButton.setTitle("Reconnecting...", for: UIControlState())
            }
            
            connection.connected = { [weak self] in
                print("Connected. Connection ID: \(connection.connectionID!)")
                self?.startButton.isEnabled = true
                self?.startButton.setTitle("Stop", for: UIControlState())
            }
            
            connection.reconnected = { [weak self] in
                print("Reconnected. Connection ID: \(connection.connectionID!)")
                self?.startButton.isEnabled = true
                self?.startButton.setTitle("Stop", for: UIControlState())
            }
            
            connection.disconnected = { [weak self] in
                print("Disconnected.")
                self?.startButton.isEnabled = true
                self?.startButton.setTitle("Start", for: UIControlState())
            }
            
            connection.connectionSlow = { print("Connection slow...") }
            
            connection.error = { error in
                print("Error: \(error)")
                
                // Here's an example of how to automatically reconnect after a timeout.
                //
                // For example, on the device, if the app is in the background long enough
                // for the SignalR connection to time out, you'll get disconnected/error
                // notifications when the app becomes active again.
                
                if let source = error?["source"] as? String , source == "TimeoutException" {
                    print("Connection timed out. Restarting...")
                    connection.start()
                }
            }
        }
        
        // Persistent connection...
        // Uncomment when using persitent connections on your SignalR server
//        persistentConnection = SwiftR.connect("http://myserver.com:5000/echo", connectionType: .persistent) { connection in
//            connection.received = { data in
//                print(data!)
//            }
//        }
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func sendSimpleMessage(_ sender: AnyObject?) {
        simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"])
        
        // Or...
        
//        simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"]) { (result, error) in
//            if let e = error {
//                print("Error: \(e)")
//            } else {
//                print("Done!")
//                if let r = result {
//                    print("Result: \(r)")
//                }
//            }
//        }
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
    
    @IBAction func startStop(_ sender: AnyObject?) {
        switch hubConnection.state {
        case .disconnected:
            hubConnection.start() // or... SwiftR.startAll()
        case .connected:
            hubConnection.stop() // or... SwiftR.stopAll()
        default:
            break
        }
    }
}

