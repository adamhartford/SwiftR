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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view, typically from a nib.
        
        SwiftR.connect("http://localhost:8080") { [weak self] (connection) in
            self?.simpleHub = connection.createHubProxy("simpleHub")
            self?.complexHub = connection.createHubProxy("complexHub")
            
            self?.simpleHub.on("notifySimple", parameters: ["message", "details"]) { (response) in
                let message = response!["message"] as! String
                let detail = response!["details"] as! String
                println("Message: \(message)\nDetail: \(detail)\n")
            }
            
            self?.complexHub.on("notifyComplex") { (response) in
                let m: AnyObject = response!["0"] as AnyObject!
                println(m)
            }
        }
        
        // Most basic example...
        
//        SwiftR.connect("http://localhost:8080") { (connection) in
//            let hub = connection.createHubProxy("myHub")
//            hub.on("addMessage") { (response) in
//                println(response!["0"])
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

}

