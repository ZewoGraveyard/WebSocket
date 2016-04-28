// Socket.swift
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

@_exported import Event
@_exported import Base64
@_exported import OpenSSL

internal extension Data {
    init<T>(number: T) {
        let totalBytes = sizeof(T)
        let valuePointer = UnsafeMutablePointer<T>(allocatingCapacity: 1)
        valuePointer.pointee = number
        let bytesPointer = UnsafeMutablePointer<Byte>(valuePointer)
        var bytes = [UInt8](repeating: 0, count: totalBytes)
        for j in 0 ..< totalBytes {
            bytes[totalBytes - 1 - j] = (bytesPointer + j).pointee
        }
        valuePointer.deinitialize()
        valuePointer.deallocateCapacity(1)
        self.init(bytes)
    }
    
    func toInt(size: Int, offset: Int = 0) -> UIntMax {
        guard size > 0 && size <= 8 && count >= offset+size else { return 0 }
        let slice = self[startIndex.advanced(by: offset) ..< startIndex.advanced(by: offset+size)]
        var result: UIntMax = 0
        for (idx, byte) in slice.enumerated() {
            let shiftAmount = UIntMax(size.toIntMax() - idx - 1) * 8
            result += UIntMax(byte) << shiftAmount
        }
        return result
    }
}

public class Socket {
    
    public enum Error: ErrorProtocol {
        case NoFrame
        case InvalidOpCode
        case MaskedFrameFromServer
        case UnaskedFrameFromClient
        case ControlFrameNotFinal
        case ControlFrameInvalidLength
        case ContinuationOutOfOrder
        case DataFrameWithInvalidBits
        case MaskKeyInvalidLength
        case NoMaskKey
        case InvalidUTF8Payload
        case InvalidCloseCode
    }
    
    private static let GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    
    public enum Mode {
        case Server
        case Client
    }
    
    private enum State {
        case Header
        case HeaderExtra
        case Payload
    }
    
    private enum CloseState {
        case Open
        case ServerClose
        case ClientClose
    }
    
    public let mode: Mode
    public let request: Request
    public let response: Response
    private let stream: Stream
    private var state: State = .Header
    private var closeState: CloseState = .Open

    private var incompleteFrame: Frame?
    private var continuationFrames: [Frame] = []

    private let binaryEventEmitter = EventEmitter<Data>()
    private let textEventEmitter = EventEmitter<String>()
    private let pingEventEmitter = EventEmitter<Data>()
    private let pongEventEmitter = EventEmitter<Data>()
    private let closeEventEmitter = EventEmitter<(code: CloseCode?, reason: String?)>()
    
    init(stream: Stream, mode: Mode, request: Request, response: Response) {
        self.stream = stream
        self.mode = mode
        self.request = request
        self.response = response
    }
    
    public func onBinary(_ listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return binaryEventEmitter.addListener(listen: listen)
    }
    
    public func onText(_ listen: EventListener<String>.Listen) -> EventListener<String> {
        return textEventEmitter.addListener(listen: listen)
    }
    
    public func onPing(_ listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return pingEventEmitter.addListener(listen: listen)
    }
    
    public func onPong(_ listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return pongEventEmitter.addListener(listen: listen)
    }
    
    public func onClose(_ listen: EventListener<(code: CloseCode?, reason: String?)>.Listen) -> EventListener<(code: CloseCode?, reason: String?)> {
        return closeEventEmitter.addListener(listen: listen)
    }
    
    public func send(_ string: String) throws {
        try send(.Text, data: string.data)
    }
    
    public func send(_ data: Data) throws {
        try send(.Binary, data: data)
    }
    
    public func send(_ convertible: DataConvertible) throws {
        try send(.Binary, data: convertible.data)
    }
    
    public func close(_ code: CloseCode?, reason: String? = nil) throws {
        if closeState == .ServerClose {
            return
        }
        
        if closeState == .Open {
            closeState = .ServerClose
        }
        
        var data = Data()

        if let code = code {
            data += Data(number: code.code)
        }
        
        if let reason = reason {
            data += reason
        }

        if closeState == .ServerClose && code == .ProtocolError {
            try stream.close()
        }
        
        try send(.Close, data: data)
        
        if closeState == .ClientClose {
            try stream.close()
        }
    }
    
    public func ping(_ data: Data = []) throws {
        try send(.Ping, data: data)
    }
    
    public func ping(_ convertible: DataConvertible) throws {
        try send(.Ping, data: convertible.data)
    }
    
    public func pong(_ data: Data = []) throws {
        try send(.Pong, data: data)
    }
    
    public func pong(_ convertible: DataConvertible) throws {
        try send(.Pong, data: convertible.data)
    }

    func loop() throws {
        while !stream.closed {
            do {
                let data = try stream.receive(upTo: 4096)
                try processData(data)
            } catch StreamError.closedStream {
                break
            }
        }
        if closeState == .Open {
            try closeEventEmitter.emit((code: .Abnormal, reason: nil))
        }
    }
    
    private func processData(_ data: Data) throws {
        guard data.count > 0 else {
            return
        }
        
        var totalBytesRead = 0
        
        while totalBytesRead < data.count {
            let bytesRead = try readBytes(Data(data[totalBytesRead ..< data.count]))

            if bytesRead == 0 {
                break
            }
            
            totalBytesRead += bytesRead
        }
    }

    private func readBytes(_ data: Data) throws -> Int {
        if data.count == 0 {
            return 0
        }

        var remainingData = data

        repeat {
            if (incompleteFrame == nil) {
                incompleteFrame = Frame()
            }

            // Use ! because if let will add data to a copy of the frame
            remainingData = incompleteFrame!.add(data: remainingData)

            if incompleteFrame!.isComplete {
                try processFrame(incompleteFrame!)
                incompleteFrame = nil
            }
        } while remainingData.count > 0

        return data.count
    }

    private func processFrame(_ frame: Frame) throws {
        func fail(_ error: ErrorProtocol) throws -> ErrorProtocol {
            try close(.ProtocolError)
            return error
        }

        // TODO Check for validity within Frame struct
        guard !frame.rsv1 && !frame.rsv2 && !frame.rsv3 else {
            throw try fail(Error.DataFrameWithInvalidBits)
        }

        guard frame.opCode != .Invalid else {
            throw try fail(Error.InvalidOpCode)
        }

        guard !frame.masked || self.mode == .Server else {
            throw try fail(Error.MaskedFrameFromServer)
        }

        guard frame.masked || self.mode == .Client else {
            throw try fail(Error.UnaskedFrameFromClient)
        }

        if frame.opCode.isControl {
            guard frame.fin else {
                throw try fail(Error.ControlFrameNotFinal)
            }

            guard frame.payloadLength < 126 else {
                throw try fail(Error.ControlFrameInvalidLength)
            }

            if frame.opCode == .Close && frame.payloadLength == 1 {
                throw try fail(Error.ControlFrameInvalidLength)
            }
        } else {
            if frame.opCode == .Continuation && continuationFrames.isEmpty {
                throw try fail(Error.ContinuationOutOfOrder)
            }

            if frame.opCode != .Continuation && !continuationFrames.isEmpty {
                throw try fail(Error.ContinuationOutOfOrder)
            }

            continuationFrames.append(frame)
        }

        if !frame.fin {
            return
        }

        var opCode = frame.opCode


        if frame.opCode == .Continuation {
            let firstFrame = continuationFrames.first!
            opCode = firstFrame.opCode
        }

        switch opCode {
        case .Binary:
            try binaryEventEmitter.emit(continuationFrames.payload)
        case .Text:
            if (try? String(data: continuationFrames.payload)) == nil {
                throw try fail(Error.InvalidUTF8Payload)
            }
            try textEventEmitter.emit(try String(data: continuationFrames.payload))
        case .Ping:
            try pingEventEmitter.emit(frame.payload)
        case .Pong:
            try pongEventEmitter.emit(frame.payload)
        case .Close:
            if self.closeState == .Open {
                var rawCloseCode: UInt16?
                var closeReason: String?
                var data = frame.payload

                if data.count >= 2 {
                    rawCloseCode = UInt16(Data(data.prefix(2)).toInt(size: 2))
                    data.removeFirst(2)

                    if data.count > 0 {
                        closeReason = try? String(data: data)
                    }

                    if data.count > 0 && closeReason == nil {
                        throw try fail(Error.InvalidUTF8Payload)
                    }
                }

                closeState = .ClientClose

                if let rawCloseCode = rawCloseCode {
                    let closeCode = CloseCode(code: rawCloseCode)
                    if closeCode.isValid {
                        try close(closeCode ?? .Normal, reason: closeReason)
                        try closeEventEmitter.emit((closeCode, closeReason))
                    } else {
                        throw try fail(Error.InvalidCloseCode)
                    }
                } else {
                    try close(nil, reason: nil)
                    try closeEventEmitter.emit((nil, nil))
                }
            } else if self.closeState == .ServerClose {
                try stream.close()
            }
        default:
            break
        }

        if !frame.opCode.isControl {
            continuationFrames.removeAll()
        }
    }

    private func send(_ opCode: Frame.OpCode, data: Data) throws {
        let maskKey: Data
        if mode == .Client {
            maskKey = try Random.getBytes(4)
        } else {
            maskKey = []
        }
        let frame = Frame(opCode: opCode, data: data, maskKey: maskKey)
        let data = frame.data
        try stream.send(data)
        try stream.flush()
    }
    
    static func accept(_ key: String) -> String? {
        return try? Base64.encode(Hash.hash(.SHA1, message: (key + GUID).data))
    }
    
}
