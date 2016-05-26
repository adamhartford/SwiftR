//
//  DemoViewController.swift
//  SwiftR
//
//  Created by Adam Hartford on 5/26/16.
//  Copyright © 2016 Adam Hartford. All rights reserved.
//

import UIKit
import SwiftR

class DemoViewController: UIViewController {
    
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var messageTextField: UITextField!
    @IBOutlet weak var chatTextView: UITextView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var startButton: UIBarButtonItem!
    
    var chatHub: Hub?
    var connection: SignalR?
    var name: String!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        SwiftR.useWKWebView = true

        connection = SwiftR.connect("http://swiftr.azurewebsites.net") { [weak self] connection in
            self?.chatHub = connection.createHubProxy("chatHub")
            self?.chatHub?.on("broadcastMessage") { args in
                if let name = args?[0] as? String, message = args?[1] as? String, text = self?.chatTextView.text {
                    self?.chatTextView.text = "\(name): \(message)\n\n\(text)"
                    self?.chatTextView.setContentOffset(CGPointZero, animated: true)
                }
            }
            
            // SignalR events
            
            connection.starting = { [weak self] in
                self?.statusLabel.text = "Starting..."
                self?.startButton.enabled = false
                self?.sendButton.enabled = false
            }
            
            connection.reconnecting = { [weak self] in
                self?.statusLabel.text = "Reconnecting..."
                self?.startButton.enabled = false
                self?.sendButton.enabled = false
            }
            
            connection.connected = { [weak self] in
                self?.statusLabel.text = "Connected. Connection ID: \(connection.connectionID!)"
                self?.startButton.enabled = true
                self?.startButton.title = "Stop"
                self?.sendButton.enabled = true
            }
            
            connection.reconnected = { [weak self] in
                self?.statusLabel.text = "Reconnected. Connection ID: \(connection.connectionID!)"
                self?.startButton.enabled = true
                self?.startButton.title = "Stop"
                self?.sendButton.enabled = true
            }
            
            connection.disconnected = { [weak self] in
                self?.statusLabel.text = "Disconnected"
                self?.startButton.enabled = true
                self?.startButton.title = "Start"
                self?.sendButton.enabled = false
            }
            
            connection.connectionSlow = { print("Connection slow...") }
            
            connection.error = { error in
                print("Error: \(error)")
                
                // Here's an example of how to automatically reconnect after a timeout.
                //
                // For example, on the device, if the app is in the background long enough
                // for the SignalR connection to time out, you'll get disconnected/error
                // notifications when the app becomes active again.
                
                if let source = error?["source"] as? String where source == "TimeoutException" {
                    print("Connection timed out. Restarting...")
                    connection.start()
                }
            }
        }
    }
    
    override func viewDidAppear(animated: Bool) {
        let alertController = UIAlertController(title: "Name", message: "Please enter your name", preferredStyle: .Alert)
        
        let okAction = UIAlertAction(title: "OK", style: .Default) { [weak self] _ in
            self?.name = alertController.textFields?.first?.text
            
            if let name = self?.name where name.isEmpty {
                self?.name = "Anonymous"
            }
        }
        
        alertController.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = "Your Name"
        }
        
        alertController.addAction(okAction)
        presentViewController(alertController, animated: true, completion: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func send(sender: AnyObject?) {
        if let hub = chatHub, message = messageTextField.text {
            hub.invoke("send", arguments: [name, message])
        }
    }
    
    @IBAction func startStop(sender: AnyObject?) {
        if startButton.title == "Start" {
            connection?.start()
        } else {
            connection?.stop()
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
