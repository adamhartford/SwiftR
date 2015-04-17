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
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
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

