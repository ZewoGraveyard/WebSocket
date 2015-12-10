// WebSocket.swift
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

import HTTP
import Stream
import Venice

public class WebSocket {

	internal static let KeyGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

	public enum WebSocketMode {
		case Server, Client
	}

	public enum WebSocketEvent {
		case Binary([UInt8])
		case Text(String)
		case Ping([UInt8])
		case Pong([UInt8])
		case Close(UInt16?, String?)
	}

	private enum State {
//		case HandshakeRequest, HandshakeResponse
		case Header, HeaderExtra, Payload
	}

	private enum CloseState {
		case Open
		case ServerClose
		case ClientClose
	}

	public enum WebSocketError: ErrorType {
		case NoFrame
	}

	public let mode: WebSocketMode = .Server
	public let context: Context
	private let stream: StreamType
	private var state: State = .Header
	private var closeState: CloseState = .Open

	private let queue = Channel<[UInt8]>(bufferSize: 10)

	private var initialFrame: WebSocketFrame?
	private var frames: [WebSocketFrame] = []
	private var buffer: [UInt8] = []

	public var request: Request {
		return self.context.request
	}

	public var listener: (WebSocketEvent -> Void)?

	public init(context: Context, stream: StreamType) {
		self.context = context
		self.stream = stream

		stream.receive { result in
			do {
				let data = try result()
				self.queue <- data.map({ UInt8(bitPattern: $0) })
			} catch {
				print("ws error: \(error)")
			}
		}

		co {
			self.processData()
		}
	}

	private func processData() {
		for data in self.queue {
			guard data.count > 0 else { return }
			var totalBytesRead = 0
			while totalBytesRead < data.count {
				let bytesRead = self.readBytes(Array(data[totalBytesRead..<data.count]))
				if bytesRead < 0 {
					print("An unknown error occurred")
					break
				} else if bytesRead == 0 {
					break
				}
				totalBytesRead += bytesRead
			}
		}
	}

	private func readBytes(data: [UInt8]) -> Int {
		guard data.count > 0 else { return -1 }

		let fail: String -> Int = { reason in
			print(reason)
			self.close(1002)
			return -1
		}

		switch state {
		case .Header:
			guard data.count >= 2 else { return -1 }

			let fin = data[0] & WebSocketFrame.FinMask != 0
			let rsv1 = data[0] & WebSocketFrame.Rsv1Mask != 0
			let rsv2 = data[0] & WebSocketFrame.Rsv2Mask != 0
			let rsv3 = data[0] & WebSocketFrame.Rsv3Mask != 0

			guard let opCode = WebSocketFrame.OpCode(rawValue: data[0] & WebSocketFrame.OpCodeMask) else { return fail("Invalid OpCode") }

			let masked = data[1] & WebSocketFrame.MaskMask != 0
			guard !masked || self.mode == .Server else { return fail("Frames must never be masked from server") }
			guard masked || self.mode == .Client else { return fail("Frames must always be masked from client") }

			let payloadLength = data[1] & WebSocketFrame.PayloadLenMask

			var headerExtraLength = masked ? sizeof(UInt32) : 0
			if payloadLength == 126 {
				headerExtraLength += sizeof(UInt16)
			} else if payloadLength == 127 {
				headerExtraLength += sizeof(UInt64)
			}

			if opCode.isControl {
				guard fin else { return fail("Control frames must be final") }
				guard !rsv1 && !rsv2 && !rsv3 else { return fail("Control frames must not use reserved bits") }
				guard payloadLength < 126 else { return fail("Control frame payload must have length < 126") }
			} else {
				guard opCode != .Continuation || frames.count != 0 else { return fail("Data continuation frames must follow an initial data frame") }
				guard opCode == .Continuation || frames.count == 0 else { return fail("Data frames must not follow an initial data frame unless continuations") }
//				guard !rsv1 || pmdEnabled else { return fail("Data frames must only use rsv1 bit if permessage-deflate extension is on") }
				guard !rsv2 && !rsv3 else { return fail("Data frames must never use rsv2 or rsv3 bits") }
			}

			var _opCode = opCode
			if !opCode.isControl && frames.count > 0 {
				initialFrame = frames.last
				_opCode = initialFrame!.opCode
			} else {
				self.buffer = []
			}

			frames.append(WebSocketFrame(fin: fin, rsv1: rsv1, rsv2: rsv2, rsv3: rsv3, opCode: _opCode, masked: masked, payloadLength: UInt64(payloadLength), headerExtraLength: headerExtraLength))

			if headerExtraLength > 0 {
				self.state = .HeaderExtra
			} else if payloadLength > 0 {
				self.state = .Payload
			} else {
				self.state = .Header
				do {
					try self.processFrames()
				} catch {
					return -1
				}
			}

			return 2
		case .HeaderExtra:
			guard let frame = frames.last where data.count >= frame.headerExtraLength else { return 0 }

			var payloadLength = UIntMax(frame.payloadLength)
			if payloadLength == 126 {
				payloadLength = data.toInt(size: 2)
			} else if payloadLength == 127 {
				payloadLength = data.toInt(size: 8)
			}

			self.frames.unsafeLast.payloadLength = payloadLength
			self.frames.unsafeLast.payloadRemainingLength = payloadLength

			if frame.masked {
				let maskOffset = max(Int(frame.headerExtraLength) - 4, 0)
				let maskKey = Array(data[maskOffset ..< maskOffset+4])
				guard maskKey.count == 4 else { return fail("maskKey wrong length") }
				self.frames.unsafeLast.maskKey = maskKey
			}

			if frame.payloadLength > 0 {
				state = .Payload
			} else {
				self.state = .Header
				do {
					try self.processFrames()
				} catch {
					return -1
				}
			}

			return frame.headerExtraLength
		case .Payload:
			guard let frame = frames.last where data.count > 0 else { return 0 }

			let consumeLength = min(frame.payloadRemainingLength, UInt64(data.count))

			var _data: [UInt8]
			if self.mode == .Server {
				guard let maskKey = frame.maskKey else { return -1 }
				_data = []
				for byte in data[0..<Int(consumeLength)] {
					_data.append(byte ^ maskKey[self.frames.unsafeLast.maskOffset++ % 4])
				}
			} else {
				_data = data
			}

			buffer += _data

			let newPayloadRemainingLength = frame.payloadRemainingLength - consumeLength
			self.frames.unsafeLast.payloadRemainingLength = newPayloadRemainingLength

			if newPayloadRemainingLength == 0 {
				self.state = .Header
				do {
					try self.processFrames()
				} catch {
					return -1
				}
			}

			return Int(consumeLength)
		}
	}

	private func processFrames() throws {
		guard let frame = frames.last else { throw WebSocketError.NoFrame }

		guard frame.fin else { return }

		let buffer = self.buffer

		self.frames.removeAll()
		self.buffer.removeAll()
		self.initialFrame = nil

		switch frame.opCode {
		case .Binary:
			self.listener?(.Binary(buffer))
		case .Text:
			let str = String.fromBytes(buffer)
			self.listener?(.Text(str))
		case .Ping:
			self.listener?(.Ping(buffer))
		case .Pong:
			self.listener?(.Pong(buffer))
		case .Close:
			print("Received close frame")
			if self.closeState == .Open {
				var closeCode: UInt16?
				var closeReason: String?
				var data = buffer
				if data.count >= 2 {
					closeCode = UInt16(data.prefix(2).toInt(size: 2))
					data.removeFirst(2)
					if data.count > 0 { closeReason = String.fromBytes(data) }
				}
				self.closeState = .ClientClose
				self.close(closeCode ?? 1000, reason: closeReason)
				self.listener?(.Close(closeCode, closeReason))
			} else if self.closeState == .ServerClose {
				print("Close / ServerClose -> stream.close()")
				self.stream.close()
			}
		case .Continuation:
			return
		}
	}

	private func send(opCode: WebSocketFrame.OpCode, data: [UInt8], completion: (ErrorType? -> Void)? = nil) {
		let frame = WebSocketFrame(opCode: opCode, data: data)
		let data = frame.getData()
		self.stream.send(unsafeBitCast(data, [Int8].self)) { sendResult in
			do {
				try sendResult()
				completion?(nil)
			} catch {
				print("websocket send error: \(error)")
				completion?(error)
			}
		}
	}

	public func send(string: String) {
		self.send(.Text, data: Array(string.utf8))
	}

	public func send(data: [UInt8]) {
		self.send(.Binary, data: data)
	}

	public func close(code: UInt16 = 1000, reason: String? = nil) {
		print("closing with code \(code) | closeState=\(self.closeState)")
		if self.closeState == .ServerClose { return }
		if self.closeState == .Open { self.closeState = .ServerClose }
		let shouldCloseStream = self.closeState == .ClientClose
		var data: [UInt8] = code.bytes()
		if let reason = reason { data += Array(reason.utf8) }
		self.send(.Close, data: data) { _ in
			if shouldCloseStream {
				self.stream.close()
			}
		}
	}

	public func ping(data: [UInt8] = []) {
		self.send(.Ping, data: data)
	}

	public func pong(data: [UInt8] = []) {
		self.send(.Pong, data: data)
	}

}
