// Client.swift
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

@_exported import HTTPClient
@_exported import HTTPSClient
@_exported import Venice
@_exported import OpenSSL

public struct Client {
	
	public enum Error: ErrorType {
		case NoRequest
		case ResponseNotWebsocket
	}
	
    private let client: ClientType
    private let onConnect: Socket throws -> Void

	public init(ssl: Bool, host: String, port: Int, onConnect: Socket throws -> Void) throws {
		if ssl {
			self.client = try HTTPSClient.Client(host: host, port: port)
		} else {
			self.client = try HTTPClient.Client(host: host, port: port)
		}
        self.onConnect =  onConnect
    }

    public func connectInBackground(path: String, failure: ErrorType -> Void = Client.logError) {
        co {
            do {
                try self.connect(path)
            } catch {
                failure(error)
            }
        }
    }

    static func logError(error: ErrorType) {
        print(error)
    }

    public func connect(path: String) throws {
		let key = try Base64.encode(Random.getBytes(16))
		
        let headers: Headers = [
            "Connection": "Upgrade",
            "Upgrade": "websocket",
            "Sec-WebSocket-Version": "13",
            "Sec-WebSocket-Key": key,
        ]
		
		var _request: Request?
		let request = try Request(method: .GET, uri: path, headers: headers) { response, stream in
			guard let request = _request else {
				throw Error.NoRequest
			}
			
            guard response.status == .SwitchingProtocols && response.isWebSocket else {
                throw Error.ResponseNotWebsocket
            }

            guard let accept = response.webSocketAccept where accept == Socket.accept(key) else {
                throw Error.ResponseNotWebsocket
			}

			let webSocket = Socket(stream: stream, mode: .Client, request: request, response: response)
            try self.onConnect(webSocket)
            try webSocket.loop()
        }
		_request = request

        try client.send(request)
    }
	
}
