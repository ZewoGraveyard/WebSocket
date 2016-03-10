WebSocket
=========

[![Swift 2.2](https://img.shields.io/badge/Swift-2.2-orange.svg?style=flat)](https://swift.org)
[![Platform Linux](https://img.shields.io/badge/Platform-Linux-lightgray.svg?style=flat)](https://swift.org)
[![License MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://tldrlegal.com/license/mit-license)
[![Slack Status](https://zewo-slackin.herokuapp.com/badge.svg)](http://slack.zewo.io)

## Installation

```swift
import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "https://github.com/Zewo/WebSocket.git", majorVersion: 0, minor: 3)
    ]
)
```


## Example
```swift
    
import WebSocket
import HTTPServer
    
let webSocketServer = WebSocket.Server { webSocket in
    print("connected")
    
    webSocket.onBinary { data in
        print("data \(data)")
        try webSocket.send(data)
    }

    webSocket.onText { text in
        print("data \(text)")
        try webSocket.send(text)
    }
}


try! HTTPServer.Server(address: "127.0.0.1", port: 8180, responder: webSocketServer).start()
```

## Community

[![Slack](http://s13.postimg.org/ybwy92ktf/Slack.png)](http://slack.zewo.io)

Join us on [Slack](http://slack.zewo.io).

License
-------

**WebSocket** is released under the MIT license. See LICENSE for details.
