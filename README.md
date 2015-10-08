# SwiftR
A Swift client for SignalR. Supports hubs and persistent connections.

### Swift 2

The master branch is now Swift 2. If you need support for Swift 1.2, use the `swift12` branch. For CocoaPods users:

```
pod 'SwiftR', git: 'https://github.com/adamhartford/SwiftR.git', branch: 'swift12'
```

### How does it work?

It's a wrapper around the SignalR JavaScript client running in a hidden web view. As such, it's subject to the same limitations of that client -- namely, no support for custom headers when using WebSockets. This is because the browser's WebSocket client does not support custom headers.

### UIWebView or WKWebView?

Either, your choice. Note that since WKWebView runs in a separate process, it does not have access to cookies in NSHTTPCookieStorage. If you need cookies, use UIWebView. SwiftR uses UIWebView by default, but you can choose WKWebView instead:

```swift
SwiftR.useWKWebView = true
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

See https://github.com/adamhartford/SignalRDemo for a sample self-hosted SignalR application.

### Simple Example (Hub)

```c#
// Server
public class SimpleHub : Hub 
{
    public void SendSimple(string message, detail)
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
        let message = args!["0"] as! String
        let detail = args!["1"] as! String
        println("Message: \(message)\nDetail: \(detail)")
    }
}
```
Custom parameter names in callback response:

```swift
// Client
SwiftR.connect("http://localhost:8080") { connection in
    let simpleHub = connection.createHubProxy("simpleHub")
  
    // Event handler
    simpleHub.on("notifySimple", parameters: ["message", "detail"]) { args in
        let message = args!["message"] as! String
        let detail = args!["detail"] as! String
        println("Message: \(message)\nDetail: \(detail)")
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
        let m: AnyObject = args!["0"] as AnyObject!
        println(m)
    }
}

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

persistentConnection = SwiftR.connect("http://localhost:8080/echo", connectionType: .Persistent) { connection in
    connection.received = { data in
        println(data!)
    }
}

// Send data
persistentConnection.send("Persistent Connection Test")
```

### Transport Method

By default, SignalR will choose the best transport available to you. You can also specify the transport method:

```swift
SwiftR.transport = .Auto // This is the default
SwiftR.transport = .WebSockets
SwiftR.transport = .ServerSentEvents
SwiftR.transport = .ForeverFrame
SwiftR.transport = .LongPolling
```

### Connection Lifetime Events

SwiftR exposes the following SignalR events:

```swift
SwiftR.connect("http://localhost:8080") { connection in
    ...
    
    connection.started = { println("started") }
    connection.connected = { println("connected: \(connection.connectionID)") }
    connection.connectionSlow = { println("connectionSlow") }
    connection.reconnecting = { println("reconnecting") }
    connection.reconnected = { println("reconnected") }
    connection.disconnected = { println("disconnected") }
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
        let message = args!["0"] as! String
        let detail = args!["1"] as! String
        println("Message: \(message)\nDetail: \(detail)")
    }
}

...

if myConnection.state == .Connected {
    myConnection.stop()
} else if myConnection.state == .Disonnected {
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

if myConnection.state == .Connecting {
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
SwiftR.connect("http://localhost:8080") { connection in
    ...

    connection.error = { error in println(error!) }
    
    /*
    {
        readyState = 0;
        status = 0;
        statusText = error;
    }
    */
}
```

### License
SwiftR is released under the MIT license. See LICENSE for details.
