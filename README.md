# SwiftR

[![Join the chat at https://gitter.im/adamhartford/SwiftR](https://badges.gitter.im/adamhartford/SwiftR.svg)](https://gitter.im/adamhartford/SwiftR?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

A Swift client for SignalR. Supports hubs and persistent connections.

### Demo

I have published a sample SignalR server at http://swiftr.azurewebsites.net. The iOS demo application now uses this server. See [SwiftRChat](https://github.com/adamhartford/SwiftRChat) for the souce code. It's based on this, with some minor changes:

http://www.asp.net/signalr/overview/deployment/using-signalr-with-azure-web-sites

### How does it work?

It's a wrapper around the SignalR JavaScript client running in a hidden web view. As such, it's subject to the same limitations of that client -- namely, no support for custom headers when using WebSockets. This is because the browser's WebSocket client does not support custom headers.

### WKWebView?

Either, your choice. Note that since WKWebView runs in a separate process, it does not have access to cookies in NSHTTPCookieStorage.
