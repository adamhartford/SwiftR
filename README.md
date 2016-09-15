# SwiftR

[![Join the chat at https://gitter.im/adamhartford/SwiftR](https://badges.gitter.im/adamhartford/SwiftR.svg)](https://gitter.im/adamhartford/SwiftR?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A Swift client for SignalR. Supports hubs and persistent connections.

### Demo

I have published a sample SignalR server at http://swiftr.azurewebsites.net. The iOS demo application now uses this server. See [SwiftRChat](https://github.com/adamhartford/SwiftRChat) for the souce code. It's based on this, with some minor changes:

http://www.asp.net/signalr/overview/deployment/using-signalr-with-azure-web-sites

### How does it work?

It's a wrapper around the SignalR JavaScript client running in a hidden web view. As such, it's subject to the same limitations of that client -- namely, no support for custom headers when using WebSockets. This is because the browser's WebSocket client does not support custom headers.

### UIWebView or WKWebView?

Either, your choice. Note that since WKWebView runs in a separate process, it does not have access to cookies in NSHTTPCookieStorage. If you need cookies, use UIWebView. SwiftR uses UIWebView by default, but you can choose WKWebView instead:

```swift
// Client
SwiftR.useWKWebView = true
```

Also when using WKWebView, make sure to enable CORS on your server:

```csharp
// Server
app.UseCors (CorsOptions.AllowAll);

// See my SignalRApplication repo for a CORS example with ASP.NET Core.
```

### What versions of SignalR are supported?

SwiftR supports SignalR version 2.x. Version 2.2.1 is assumed by default. To change the SignalR version:

```swift
SwiftR.signalRVersion = .v2_2_1
//SwiftR.signalRVersion = .v2_2_0
//SwiftR.signalRVersion = .v2_1_2
//SwiftR.signalRVersion = .v2_1_1
//SwiftR.signalRVersion = .v2_1_0
//SwiftR.signalRVersion = .v2_0_3
//SwiftR.signalRVersion = .v2_0_2
//SwiftR.signalRVersion = .v2_0_1
//SwiftR.signalRVersion = .v2_0_0
```

### Installation

[CocoaPods](https://cocoapods.org):
``` ruby
use_frameworks!
pod 'SwiftR'
```

[Carthage](https://github.com/Carthage/Carthage):
```
github 'adamhartford/SwiftR'
```

### Server Example

See https://github.com/adamhartford/SignalRDemo for a sample self-hosted SignalR application. Or, https://github.com/adamhartford/SignalRApplication for an ASP.NET 5 version.

### Simple Example (Hub)

```c#
// Server
public class SimpleHub : Hub 
{
    public void SendSimple(string message, string detail)
    {
        Clients.All.notifySimple (message, detail);
    }
}
```

Default parameter names in callback response:
```swift
// Client
SwiftR.connect("http://localhost:8080") { connection in
    let simpleHub = connection.createHubProxy("simpleHub")
  
    // Event handler
    simpleHub.on("notifySimple") { args in
        let message = args![0] as! String
        let detail = args![1] as! String
        print("Message: \(message)\nDetail: \(detail)")
    }
}

...

// Invoke server method
simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"])

// Invoke server method and handle response
simpleHub.invoke("sendSimple", arguments: ["Simple Test", "This is a simple message"]) { (result, error) in
    if let e = error {
        print("Error: \(e)")
    } else {
        print("Success!")
        if let r = result {
            print("Result: \(r)")
        }
    }
}
```

### Complex Example (Hub)

```c#
// Server
public class ComplexMessage
{
    public int MessageId { get; set; }
    public string Message { get; set; }
    public string Detail { get; set; }
    public IEnumerable<String> Items { get; set; }
}

// Server
public class ComplexHub : Hub
{
    public void SendComplex(ComplexMessage message) 
    {
        Clients.All.notifyComplex (message);
    }
}
```

```swift
// Client
var complexHub: Hub!

SwiftR.connect("http://localhost:8080") { [weak self] connection in
    self?.complexHub = connection.createHubProxy("complexHub")
    
    self?.complexHub.on("notifyComplex") { args in
        let m: AnyObject = args![0] as AnyObject!
        print(m)
    }
}

...

let message = [
    "messageId": 1,
    "message": "Complex Test",
    "detail": "This is a complex message",
    "items": ["foo", "bar", "baz"]
]

// Invoke server method
complexHub.invoke("sendComplex", parameters: [message])
```

### Persistent Connections
```c#
// Server
app.MapSignalR<MyConnection> ("/echo");

...

public class MyConnection : PersistentConnection 
{
    protected override Task OnReceived(IRequest request, string connectionId, string data) 
    {
        return Connection.Broadcast(data);
    }
}
```

```swift
// Client
var persistentConnection: SignalR!

persistentConnection = SwiftR.connect("http://localhost:8080/echo", connectionType: .persistent) { connection in
    connection.received = { data in
        print(data!)
    }
}

// Send data
persistentConnection.send("Persistent Connection Test")
```

### Transport Method

By default, SignalR will choose the best transport available to you. You can also specify the transport method:

```swift
SwiftR.transport = .auto // This is the default
SwiftR.transport = .webSockets
SwiftR.transport = .serverSentEvents
SwiftR.transport = .foreverFrame
SwiftR.transport = .longPolling
```

### Connection Lifetime Events

SwiftR exposes the following SignalR events:

```swift
SwiftR.connect("http://localhost:8080") { connection in
    ...
    
    connection.started = { print("started") }
    connection.connected = { print("connected: \(connection.connectionID)") }
    connection.connectionSlow = { print("connectionSlow") }
    connection.reconnecting = { print("reconnecting") }
    connection.reconnected = { print("reconnected") }
    connection.disconnected = { print("disconnected") }
}
```

### Reconnecting

You may find it necessary to try reconnecting manually once disconnected. Here's an example of how to do that:

```swift
connection.disconnected = {
    print("Disconnected...")
    
    // Try again after 5 seconds
    let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(5 * Double(NSEC_PER_SEC)))
    dispatch_after(delayTime, dispatch_get_main_queue()) {
        connection.start()
    }
}
```

### Stop/Start Connection

Use the `stop()` and `start()` methods to manage connections manually.

```swift
var myConnection: SignalR!

myConnection = SwiftR.connect("http://localhost:8080") { connection in
    let simpleHub = connection.createHubProxy("simpleHub")
  
    // Event handler
    simpleHub.on("notifySimple") { args in
        let message = args![0] as! String
        let detail = args![1] as! String
        print("Message: \(message)\nDetail: \(detail)")
    }
}

...

if myConnection.state == .connected {
    myConnection.stop()
} else if myConnection.state == .disonnected {
    myConnection.start()
}

... // Or...

SwiftR.stopAll()
SwiftR.startAll()
```

### Connection State

```swift
public enum State {
    case Connecting
    case Connected
    case Disconnected
}

...

if myConnection.state == .connecting {
    // Do something...
}

```

### Sending information to SignalR

#### Query String

```swift
SwiftR.connect("http://localhost:8080") { connection in
    connection.queryString = ["foo": "bar"]
    ...
}
```

#### Custom Headers (Non-WebSocket Only)

```swift
SwiftR.connect("http://localhost:8080") { connection in
    connection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2", "Value2"]
    ...
}
```

#### Cookies (UIWebView Only)

SwiftR will send any cookies in your app's NSHTTPCookieStorage to SignalR. You can also set cookies manually:

```swift
let cookieProperties = [
    NSHTTPCookieName: "Foo",
    NSHTTPCookieValue: "Bar",
    NSHTTPCookieDomain: "myserver.com",
    NSHTTPCookiePath: "/",
]
let cookie = NSHTTPCookie(properties: cookieProperties)
NSHTTPCookieStorage.sharedHTTPCookieStorage().setCookie(cookie!)
```

### Error Handling

```swift
connection.error = { error in 
  print("Error: \(error)")
  
  if let source = error?["source"] as? String, source == "TimeoutException" {
      print("Connection timed out. Restarting...")
      connection.start()
  }
}
```

### License
SwiftR is released under the MIT license. See LICENSE for details.
