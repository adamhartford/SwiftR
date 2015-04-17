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
    
    var signalR: SwiftR!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Do any additional setup after loading the view, typically from a nib.
        
        signalR = SwiftR(url: "http://localhost:8080/signalr")
        
        signalR.addHandler("simpleHub", event: "notifySimple") { (response)  in
            let message = response!["0"] as! String
            let detail = response!["1"] as! String
            println("Message: \(message)\nDetail: \(detail)\n")
        }
        
        signalR.addHandler("complexHub", event: "notifyComplex") { (response) in
            let m: AnyObject = response!["0"] as AnyObject!
            println(m)
        }
        
        signalR.start()

        // Uncomment to right-click --> Inspect and use web inspector.
        // Make sure webView is pulic and developerExtrasEnabled = true in WKWebView config.
        
        //signalR.webView.frame = view.frame
        //view.addSubview(signalR.webView)
    }
    
    override var representedObject: AnyObject? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func sendSimpleMessage(sender: AnyObject?) {
        signalR.invoke("simpleHub", method: "sendSimple", parameters: ["Simple Test", "This is a simple message"])
    }
    
    @IBAction func sendComplexMessage(sender: AnyObject?) {
        let message = [
            "messageId": 1,
            "message": "Complex Test",
            "detail": "This is a complex message",
            "items": ["foo", "bar", "baz"]
        ]
        
        signalR.invoke("complexHub", method: "sendComplex", parameters: [message])
    }

}

