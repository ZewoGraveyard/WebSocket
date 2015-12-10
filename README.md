WebSockets
==========

[![Swift 2.2](https://img.shields.io/badge/Swift-2.1-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms Linux](https://img.shields.io/badge/Platforms-Linux-lightgray.svg?style=flat)](https://developer.apple.com/swift/)
[![License MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://tldrlegal.com/license/mit-license)
[![Slack Status](https://zewo-slackin.herokuapp.com/badge.svg)](https://zewo-slackin.herokuapp.com)

**WebSockets** is a WebSockets server for **Swift 2.2**.

## Dependencies

**WebSockets** is made of:

- [HTTP](https://github.com/Zewo/HTTP) - HTTP request/response
- [Venice](https://github.com/Zewo/Venice) - CSP and TCP/IP

## Related Projects

- [Epoch](https://github.com/Zewo/Epoch) - Venice based HTTP server

## Usage

### WebSockets + Epoch

You'll need an HTTP server to make this work. **WebSockets** and [Epoch](https://www.github.com/Zewo/Epoch) were designed to work with each other seamlessly.

```swift
#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif
import HTTP
import Epoch
import CHTTPParser
import CLibvenice
import WebSockets

let webSocketsServer = WebSocketsServer()

func onWebSocket(webSocket: WebSocket) {
	print("webSocket conntected")
	webSocket.listener = { event in
		switch event {
		case .Binary(let data):
			webSocket.send(data)
		case .Text(let text):
			webSocket.send(text)
		case .Ping(let data):
			webSocket.pong(data)
		case .Pong(let data):
			break
		case .Close(let code, let reason):
			print("webSocket closed")
		}
	}
}

struct Responder: ContextResponderType {
	func respond(context: Context) {
		if webSocketsServer.handleContext(context, websocketHandler: onWebSocket) { return }
		context.respond(Response(status: .OK, body: "Hello from Swift"))
	}
}

let server = Server(port: 8080, responder: Responder())
server.start()
```

## Installation

**WebSockets** depends on the C lib [libvenice](https://github.com/Zewo/libvenice). Install it through:

### Homebrew 
```bash
$ brew tap zewo/tap
$ brew install libvenice
```

### Ubuntu/Debian
```bash
$ add-apt-repository 'deb [trusted=yes] http://apt.zewo.io/deb ./'
$ apt-get install libvenice
```

### Source
```bash
$ git clone https://github.com/Zewo/libvenice.git && cd libvenice
$ make
$ (sudo) make install
```

> You only have to install the C libs once.

Then add `WebSockets` to your `Package.swift`

```swift
import PackageDescription

let package = Package(
	dependencies: [
		.Package(url: "https://github.com/Zewo/WebSockets.git", majorVersion: 0, minor: 1)
	]
)
```

## Community

[![Slack](http://s13.postimg.org/ybwy92ktf/Slack.png)](http://slack.zewo.io/)

Join us on [Slack](http://slack.zewo.io/).

License
-------

**WebSockets** is released under the MIT license. See LICENSE for details.
