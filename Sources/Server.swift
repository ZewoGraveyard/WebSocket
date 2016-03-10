// Server.swift
//
// The MIT License (MIT)
//
// Copyright (c) 2015 Zewo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

@_exported import HTTP

public struct Server: ResponderType, MiddlewareType, ChainType {
    
    public enum Error: ErrorType {
        case NoResponse
    }
    
    private let onConnect: Socket throws -> Void
    
    public init(onConnect: Socket throws -> Void) {
        self.onConnect =  onConnect
    }
    
    // MARK: - MiddlewareType
    
    public func respond(request: Request, chain: ChainType) throws -> Response {
        guard request.isWebSocket && request.webSocketVersion == "13", let key = request.webSocketKey else {
            return try chain.proceed(request)
        }
        
        guard let accept = Socket.accept(key) else {
            return Response(status: .InternalServerError)
        }
        
        let headers: Headers = [
            "Connection": "Upgrade",
            "Upgrade": "websocket",
            "Sec-WebSocket-Accept": accept
        ]
        
        var _response: Response?
        let response = Response(status: .SwitchingProtocols, headers: headers) { _, stream in
            guard let response = _response else {
                throw Error.NoResponse
            }
            
            let webSocket = Socket(stream: stream, mode: .Server, request: request, response: response)
            try self.onConnect(webSocket)
            try webSocket.loop()
        }
        _response = response
        
        return response
    }
    
    // MARK: - ResponderType
    
    public func respond(request: Request) throws -> Response {
        return try respond(request, chain: self)
    }
    
    // MARK: - ChainType
    
    public func proceed(request: Request) throws -> Response {
        return Response(status: .BadRequest)
    }
    
}

public extension MessageType {
    
    public var webSocketVersion: String? {
        return headers["Sec-Websocket-Version"]
    }
    
    public var webSocketKey: String? {
        return headers["Sec-Websocket-Key"]
    }
    
    public var webSocketAccept: String? {
        return headers["Sec-WebSocket-Accept"]
    }
    
    public var isWebSocket: Bool {
        return connection?.lowercaseString == "upgrade" && upgrade?.lowercaseString == "websocket"
    }
    
}
