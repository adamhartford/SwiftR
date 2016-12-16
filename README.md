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
let connection = SignalR("https://swiftr.azurewebsites.net")
connection.useWKWebView = true
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
let connection = SignalR("https://swiftr.azurewebsites.net")
connection.signalRVersion = .v2_2_1
//connection.signalRVersion = .v2_2_0
//connection.signalRVersion = .v2_1_2
//connection.signalRVersion = .v2_1_1
//connection.signalRVersion = .v2_1_0
//connection.signalRVersion = .v2_0_3
//connection.signalRVersion = .v2_0_2
//connection.signalRVersion = .v2_0_1
//connection.signalRVersion = .v2_0_0
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
let connection = SignalR("http://localhost:5000")

let simpleHub = Hub("simpleHub")
simpleHub.on("notifySimple") { args in
    let message = args![0] as! String
    let detail = args![1] as! String
    print("Message: \(message)\nDetail: \(detail)")
}

connection.addHub(simpleHub)
connection.start()

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
let connection = SignalR("http://localhost:5000")

let complexHub = Hub("complexHub")
complexHub.on("notifyComplex") { args in
    let m: AnyObject = args![0] as AnyObject!
    print(m)
}

connection.addHub(complexHub)
connection.start()

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
let persistentConnection = SignalR("http://localhost:8080/echo", connectionType: .persistent)
persistentConnection.received = { data in
    print(data)
}
persistentConnection.start()

// Send data
persistentConnection.send("Persistent Connection Test")
```

### Transport Method

By default, SignalR will choose the best transport available to you. You can also specify the transport method:

```swift
let connection = SignalR("https://swiftr.azurewebsites.net")
connection.transport = .auto // This is the default
connection.transport = .webSockets
connection.transport = .serverSentEvents
connection.transport = .foreverFrame
connection.transport = .longPolling
```

### Connection Lifetime Events

SwiftR exposes the following SignalR events:

```swift
let connection = SignalR("http://swiftr.azurewebsites.net")
connection.started = { print("started") }
connection.connected = { print("connected: \(connection.connectionID)") }
connection.connectionSlow = { print("connectionSlow") }
connection.reconnecting = { print("reconnecting") }
connection.reconnected = { print("reconnected") }
connection.disconnected = { print("disconnected") }
connection.start()
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
let connection  = SignalR("https://swiftr.azurewebsites.net")
connection.start()
connection.stop()

...

if connection.state == .connected {
    connection.stop()
} else if connection.state == .disonnected {
    connection.start()
}
```

### Connection State

```swift
public enum State {
    case connecting
    case connected
    case disconnected
}

```

### Sending information to SignalR

#### Query String

```swift
let connection = SignalR("https://swiftr.azurewebsites.net")
connection.queryString = ["foo": "bar"]
```

#### Custom Headers (Non-WebSocket Only)

```swift
let connection = SignalR("https://swiftr.azurewebsites.net")
connection.headers = ["X-MyHeader1": "Value1", "X-MyHeader2", "Value2"]
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
