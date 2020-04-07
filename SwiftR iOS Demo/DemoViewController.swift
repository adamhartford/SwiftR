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
    
    var chatHub: Hub!
    var connection: SignalR!
    var name: String!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        connection = SignalR("http://swiftr.azurewebsites.net")
        connection.signalRVersion = .v2_2_0
        
        chatHub = Hub("chatHub")
        chatHub.on("broadcastMessage") { [weak self] args in
            if let name = args?[0] as? String, let message = args?[1] as? String, let text = self?.chatTextView.text {
                self?.chatTextView.text = "\(text)\n\n\(name): \(message)"
            }
        }
        connection.addHub(chatHub)
        
         // SignalR events
        
        connection.starting = { [weak self] in
            self?.statusLabel.text = "Starting..."
            self?.startButton.isEnabled = false
            self?.sendButton.isEnabled = false
        }

        connection.reconnecting = { [weak self] in
            self?.statusLabel.text = "Reconnecting..."
            self?.startButton.isEnabled = false
            self?.sendButton.isEnabled = false
        }

        connection.connected = { [weak self] in
            print("Connection ID: \(self!.connection.connectionID!)")
            self?.statusLabel.text = "Connected"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Stop"
            self?.sendButton.isEnabled = true
        }

        connection.reconnected = { [weak self] in
            self?.statusLabel.text = "Reconnected. Connection ID: \(self!.connection.connectionID!)"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Stop"
            self?.sendButton.isEnabled = true
        }

        connection.disconnected = { [weak self] in
            self?.statusLabel.text = "Disconnected"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Start"
            self?.sendButton.isEnabled = false
        }

        connection.connectionSlow = { print("Connection slow...") }

        connection.error = { [weak self] error in
            print("Error: \(String(describing: error))")

            // Here's an example of how to automatically reconnect after a timeout.
            //
            // For example, on the device, if the app is in the background long enough
            // for the SignalR connection to time out, you'll get disconnected/error
            // notifications when the app becomes active again.
            
            if let source = error?["source"] as? String, source == "TimeoutException" {
                print("Connection timed out. Restarting...")
                self?.connection.start()
            }
        }
        
        connection.start()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let alertController = UIAlertController(title: "Name", message: "Please enter your name", preferredStyle: .alert)
        
        let okAction = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.name = alertController.textFields?.first?.text
            
            if let name = self?.name , name.isEmpty {
                self?.name = "Anonymous"
            }
            
            alertController.textFields?.first?.resignFirstResponder()
        }
        
        alertController.addTextField { textField in
            textField.placeholder = "Your Name"
        }
        
        alertController.addAction(okAction)
        present(alertController, animated: true, completion: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func send(_ sender: AnyObject?) {
        if let hub = chatHub, let message = messageTextField.text, let name = name {
            do {
                try hub.invoke("send", arguments: [name, message])
            } catch {
                print(error)
            }
        }
        messageTextField.resignFirstResponder()
    }
    
    @IBAction func startStop(_ sender: AnyObject?) {
        if startButton.title == "Start" {
            connection.start()
        } else {
            connection.stop()
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
