//
//  DemoViewController.swift
//  SwiftR
//
//  Created by Adam Hartford on 5/26/16.
//  Copyright © 2016 Adam Hartford. All rights reserved.
//

import AppKit
import SwiftR

class DemoViewController: NSViewController {
    
    @IBOutlet weak var sendButton: NSButton!
	@IBOutlet weak var messageTextField: NSTextField!
	@IBOutlet var chatTextView: NSTextView!
	@IBOutlet weak var statusLabel: NSTextField!
	@IBOutlet weak var startButton: NSButton!
	
    var chatHub: Hub!
    var connection: SignalR!
    var name: String!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        connection = SignalR("http://swiftr.azurewebsites.net")
        connection.useWKWebView = true
        connection.signalRVersion = .v2_2_0
        
        chatHub = Hub("chatHub")
        chatHub.on("broadcastMessage") { [weak self] args in
            if let name = args?[0] as? String, let message = args?[1] as? String, let text = self?.chatTextView.string {
                self?.chatTextView.string = "\(text)\n\n\(name): \(message)"
            }
        }
        connection.addHub(chatHub)
        
         // SignalR events
        
        connection.starting = { [weak self] in
            self?.statusLabel.stringValue = "Starting..."
            self?.startButton.isEnabled = false
            self?.sendButton.isEnabled = false
        }

        connection.reconnecting = { [weak self] in
            self?.statusLabel.stringValue = "Reconnecting..."
            self?.startButton.isEnabled = false
            self?.sendButton.isEnabled = false
        }

        connection.connected = { [weak self] in
            print("Connection ID: \(self!.connection.connectionID!)")
            self?.statusLabel.stringValue = "Connected"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Stop"
            self?.sendButton.isEnabled = true
        }

        connection.reconnected = { [weak self] in
            self?.statusLabel.stringValue = "Reconnected. Connection ID: \(self!.connection.connectionID!)"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Stop"
            self?.sendButton.isEnabled = true
        }

        connection.disconnected = { [weak self] in
            self?.statusLabel.stringValue = "Disconnected"
            self?.startButton.isEnabled = true
            self?.startButton.title = "Start"
            self?.sendButton.isEnabled = false
        }

        connection.connectionSlow = { print("Connection slow...") }

        connection.error = { [weak self] error in
            print("Error: \(error)")

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
    
    override func viewDidAppear() {
        //let alertController = NSAlertController(title: "Name", message: "Please enter your name", preferredStyle: .alert)
        
		let popup = NSAlert()
		popup.messageText = "Name"
		popup.informativeText = "Please enter your name"
		popup.alertStyle = NSAlertStyle.informational
		popup.addButton(withTitle: "OK")
		
		let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
		inputTextField.placeholderString = "Your Name"
		popup.accessoryView = inputTextField
		
		let window = NSApplication.shared().mainWindow
		
		popup.beginSheetModal(for: window!, completionHandler: { (modalResponse) -> Void in
			if modalResponse == NSAlertFirstButtonReturn {
				self.name = inputTextField.stringValue
				if let name = self.name , name.isEmpty {
					self.name = "Anonymous"
				}
				print("Entered name = \"\(self.name)\"")
				inputTextField.resignFirstResponder()
			}
		})

        /*let okAction = NSAlertAction(title: "OK", style: .default) { [weak self] _ in
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
		*/
    }

	/*iOS-only
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }*/
    
    @IBAction func send(_ sender: AnyObject?) {
		guard name != nil else {
			print("Cannot send, name is nil!")
			return
		}
		
		if let hub = chatHub {
			let message = messageTextField.stringValue
			do {
				try hub.invoke("send", arguments: [name, message])
			}
			catch {
				
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
