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
        
        // Hubs...
        hubConnection = SignalR("http://myserver.com:5000")
        hubConnection.useWKWebView = true
        hubConnection.transport = .serverSentEvents
        hubConnection.queryString = ["foo": "bar"]
        hubConnection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2": "Value2"]
        
        // This only works with WKWebView on iOS >= 9
        // Otherwise, use NSUserDefaults.standardUserDefaults().registerDefaults(["UserAgent": "SwiftR iOS Demo App"])
        hubConnection.customUserAgent = "SwiftR iOS Demo App"
            
        simpleHub = Hub("simpleHub")
        complexHub = Hub("complexHub")
        
        simpleHub.on("notifySimple") { args in
            let message = args![0] as! String
            let detail = args![1] as! String
            print("Message: \(message)\nDetail: \(detail)\n")
        }
        
        complexHub.on("notifyComplex") { args in
            let m: AnyObject = args![0] as AnyObject
            print(m)
        }
        
        hubConnection.addHub(simpleHub)
        hubConnection.addHub(complexHub)
            
        // SignalR events
        
        hubConnection.starting = { [weak self] in
            print("Starting...")
            self?.startButton.isEnabled = false
            self?.startButton.setTitle("Connecting...", for: UIControl.State())
        }
        
        hubConnection.reconnecting = { [weak self] in
            print("Reconnecting...")
            self?.startButton.isEnabled = false
            self?.startButton.setTitle("Reconnecting...", for: UIControl.State())
        }
        
        hubConnection.connected = { [weak self] in
            print("Connected. Connection ID: \(String(describing: self!.hubConnection.connectionID))")
            self?.startButton.isEnabled = true
            self?.startButton.setTitle("Stop", for: UIControl.State())
        }
        
        hubConnection.reconnected = { [weak self] in
            print("Reconnected. Connection ID: \(String(describing: self!.hubConnection.connectionID))")
            self?.startButton.isEnabled = true
            self?.startButton.setTitle("Stop", for: UIControl.State())
        }
        
        hubConnection.disconnected = { [weak self] in
            print("Disconnected.")
            self?.startButton.isEnabled = true
            self?.startButton.setTitle("Start", for: UIControl.State())
        }
        
        hubConnection.connectionSlow = { print("Connection slow...") }
        
        hubConnection.error = { [weak self] error in
            print("Error: \(String(describing: error))")
            
            // Here's an example of how to automatically reconnect after a timeout.
            //
            // For example, on the device, if the app is in the background long enough
            // for the SignalR connection to time out, you'll get disconnected/error
            // notifications when the app becomes active again.
            
            if let source = error?["source"] as? String , source == "TimeoutException" {
                print("Connection timed out. Restarting...")
                self?.hubConnection.start()
            }
        }
        
        hubConnection.start()
        
        // Persistent connection...
        // Uncomment when using persitent connections on your SignalR server
//        persistentConnection = SignalR("http://myserver.com:5000/echo", connectionType: .persistent)
//        persistentConnection.received = { data in
//            print(data!)
//        }
//        persistentConnection.connect()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func sendSimpleMessage(_ sender: AnyObject?) {
        do {
            try simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"])
        } catch {
            print(error)
        }
        
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
        
        do {
            try complexHub.invoke("sendComplex", arguments: [message])
        } catch {
            print(error)
        }
    }
    
    @IBAction func sendData(_ sender: AnyObject?) {
        persistentConnection.send("Persistent Connection Test")
    }
    
    @IBAction func startStop(_ sender: AnyObject?) {
        switch hubConnection.state {
        case .disconnected:
            hubConnection.start()
        case .connected:
            hubConnection.stop()
        default:
            break
        }
    }
}

