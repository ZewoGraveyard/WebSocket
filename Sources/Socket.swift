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
        var totalBytes = sizeof(T)
        let valuePointer = UnsafeMutablePointer<T>(allocatingCapacity: 1)
        valuePointer.pointee = number
        let bytesPointer = UnsafeMutablePointer<Byte>(valuePointer)
        var bytes = [UInt8](repeating: 0, count: totalBytes)
        let size = sizeof(UInt16)
        if totalBytes > size { totalBytes = size }
        for j in 0 ..< totalBytes {
            bytes[totalBytes - 1 - j] = (bytesPointer + j).pointee
        }
        valuePointer.deinitialize()
        valuePointer.deallocateCapacity(1)
        self.init(bytes)
    }
    
    func toInt(size size: Int, offset: Int = 0) -> UIntMax {
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
        case SmallData
        case InvalidOpCode
        case MaskedFrameFromServer
        case UnaskedFrameFromClient
        case ControlFrameNotFinal
        case ControlFrameWithReservedBits
        case ControlFrameInvalidLength
        case ContinuationOutOfOrder
        case DataFrameWithInvalidBits
        case MaskKeyInvalidLength
        case NoMaskKey
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
    
    private var initialFrame: Frame?
    private var frames: [Frame] = []
    private var buffer: Data = []
    
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
    
    public func onBinary(listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return binaryEventEmitter.addListener(listen: listen)
    }
    
    public func onText(listen: EventListener<String>.Listen) -> EventListener<String> {
        return textEventEmitter.addListener(listen: listen)
    }
    
    public func onPing(listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return pingEventEmitter.addListener(listen: listen)
    }
    
    public func onPong(listen: EventListener<Data>.Listen) -> EventListener<Data> {
        return pongEventEmitter.addListener(listen: listen)
    }
    
    public func onClose(listen: EventListener<(code: CloseCode?, reason: String?)>.Listen) -> EventListener<(code: CloseCode?, reason: String?)> {
        return closeEventEmitter.addListener(listen: listen)
    }
    
    public func send(string: String) throws {
        try send(.Text, data: string.data)
    }
    
    public func send(data: Data) throws {
        try send(.Binary, data: data)
    }
    
    public func send(convertible: DataConvertible) throws {
        try send(.Binary, data: convertible.data)
    }
    
    public func close(code: CloseCode = .Normal, reason: String? = nil) throws {
        if closeState == .ServerClose {
            return
        }
        
        if closeState == .Open {
            closeState = .ServerClose
        }
        
        var data = Data(number: code.code)
        
        if let reason = reason {
            data += reason
        }
        
        try send(.Close, data: data)
        
        if closeState == .ClientClose {
            stream.close()
        }
    }
    
    public func ping(data: Data = []) throws {
        try send(.Ping, data: data)
    }
    
    public func ping(convertible: DataConvertible) throws {
        try send(.Ping, data: convertible.data)
    }
    
    public func pong(data: Data = []) throws {
        try send(.Pong, data: data)
    }
    
    public func pong(convertible: DataConvertible) throws {
        try send(.Pong, data: convertible.data)
    }
    
    func loop() throws {
        while !stream.closed {
            do {
                let data = try stream.receive()
                try processData(data)
            } catch StreamError.closedStream {
                break
            }
        }
        if closeState == .Open {
            try closeEventEmitter.emit((code: .Abnormal, reason: nil))
        }
    }
    
    private func processData(data: Data) throws {
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
    
    private func readBytes(data: Data) throws -> Int {
        
        if data.count == 0 {
            return 0
        }
        
        func fail(error: ErrorProtocol) throws -> ErrorProtocol {
            try close(.ProtocolError)
            return error
        }
        
        switch state {
        case .Header:
            guard data.count >= 2 else {
                throw try fail(Error.SmallData)
            }
            
            let fin = data[0] & Frame.FinMask != 0
            let rsv1 = data[0] & Frame.Rsv1Mask != 0
            let rsv2 = data[0] & Frame.Rsv2Mask != 0
            let rsv3 = data[0] & Frame.Rsv3Mask != 0
            
            guard let opCode = Frame.OpCode(rawValue: data[0] & Frame.OpCodeMask) else {
                throw try fail(Error.InvalidOpCode)
            }
            
            let masked = data[1] & Frame.MaskMask != 0
            
            guard !masked || self.mode == .Server else {
                throw try fail(Error.MaskedFrameFromServer)
            }
            
            guard masked || self.mode == .Client else {
                throw try fail(Error.UnaskedFrameFromClient)
            }
            
            let payloadLength = data[1] & Frame.PayloadLenMask
            var headerExtraLength = masked ? sizeof(UInt32) : 0
            
            if payloadLength == 126 {
                headerExtraLength += sizeof(UInt16)
            } else if payloadLength == 127 {
                headerExtraLength += sizeof(UInt64)
            }
            
            if opCode.isControl {
                guard fin else {
                    throw try fail(Error.ControlFrameNotFinal)
                }
                
                guard !rsv1 && !rsv2 && !rsv3 else {
                    throw try fail(Error.ControlFrameWithReservedBits)
                }
                
                guard payloadLength < 126 else {
                    throw try fail(Error.ControlFrameInvalidLength)
                }
            } else {
                guard opCode != .Continuation || frames.count != 0 else {
                    throw try fail(Error.ContinuationOutOfOrder)
                }
                
                guard opCode == .Continuation || frames.count == 0 else {
                    throw try fail(Error.ContinuationOutOfOrder)
                }
                
                //				guard !rsv1 || pmdEnabled else { return fail("Data frames must only use rsv1 bit if permessage-deflate extension is on") }
                
                guard !rsv2 && !rsv3 else {
                    throw try fail(Error.DataFrameWithInvalidBits)
                }
            }
            
            var _opCode = opCode
            
            if !opCode.isControl && frames.count > 0 {
                initialFrame = frames.last
                _opCode = initialFrame!.opCode
            } else {
                buffer = []
            }
            
            let frame = Frame(
                fin: fin,
                rsv1: rsv1,
                rsv2: rsv2,
                rsv3: rsv3,
                opCode: _opCode,
                masked: masked,
                payloadLength: UInt64(payloadLength),
                headerExtraLength: headerExtraLength
            )
            
            frames.append(frame)
            
            if headerExtraLength > 0 {
                state = .HeaderExtra
            } else if payloadLength > 0 {
                state = .Payload
            } else {
                state = .Header
                try processFrames()
            }
            
            return 2
        case .HeaderExtra:
            guard var frame = frames.last where data.count >= frame.headerExtraLength else {
                return 0
            }
            
            var payloadLength = UIntMax(frame.payloadLength)
            
            if payloadLength == 126 {
                payloadLength = data.toInt(size: 2)
            } else if payloadLength == 127 {
                payloadLength = data.toInt(size: 8)
            }
            
            frame.payloadLength = payloadLength
            frame.payloadRemainingLength = payloadLength
            
            if frame.masked {
                let maskOffset = max(Int(frame.headerExtraLength) - 4, 0)
                let maskKey = Data(data[maskOffset ..< maskOffset+4])
                
                guard maskKey.count == 4 else {
                    throw try fail(Error.MaskKeyInvalidLength)
                }
                
                frame.maskKey = maskKey
            }
            
            if frame.payloadLength > 0 {
                state = .Payload
            } else {
                state = .Header
                try processFrames()
            }
            
            let ind = frames.endIndex.predecessor()
            if ind >= 0 && ind < frames.count {
                frames[ind] = frame
            }
            
            return frame.headerExtraLength
        case .Payload:
            guard var frame = frames.last where data.count > 0 else {
                return 0
            }
            
            let consumeLength = min(frame.payloadRemainingLength, UInt64(data.count))
            var _data: Data
            
            if self.mode == .Server {
                guard frame.maskKey != nil else {
                    throw try fail(Error.NoMaskKey)
                }
                
                _data = []
                
                for byte in data[0..<Int(consumeLength)] {
                    _data.append(byte ^ frame.maskKey[frame.maskOffset % 4])
                    frame.maskOffset += 1
                }
            } else {
                _data = Data(data[0..<Int(consumeLength)])
            }
            
            buffer += _data
            
            let newPayloadRemainingLength = frame.payloadRemainingLength - consumeLength
            frame.payloadRemainingLength = newPayloadRemainingLength
            
            if newPayloadRemainingLength == 0 {
                state = .Header
                try processFrames()
            }
            let ind = frames.endIndex.predecessor()
            if ind >= 0 && ind < frames.count {
                frames[ind] = frame
            }
            return Int(consumeLength)
        }
    }
    
    private func processFrames() throws {
        guard let frame = frames.last else {
            throw Error.NoFrame
        }
        
        guard frame.fin else {
            return
        }
        
        let buffer = self.buffer
        
        self.frames.removeAll()
        self.buffer.removeAll()
        self.initialFrame = nil
        
        switch frame.opCode {
        case .Binary:
            try binaryEventEmitter.emit(buffer)
        case .Text:
            try textEventEmitter.emit(try String(data: buffer))
        case .Ping:
            try pingEventEmitter.emit(buffer)
        case .Pong:
            try pongEventEmitter.emit(buffer)
        case .Close:
            if self.closeState == .Open {
                var rawCloseCode: Int?
                var closeReason: String?
                var data = buffer
                
                if data.count >= 2 {
                    rawCloseCode = Int(UInt16(Data(data.prefix(2)).toInt(size: 2)))
                    data.removeFirst(2)
                    
                    if data.count > 0 {
                        closeReason = try String(data: data)
                    }
                }
                
                closeState = .ClientClose
                
                let closeCode: CloseCode?
                if let rawCloseCode = rawCloseCode {
                    closeCode = CloseCode(code: rawCloseCode)
                } else {
                    closeCode = nil
                }
                
                try close(closeCode ?? .Normal, reason: closeReason)
                try closeEventEmitter.emit((closeCode, closeReason))
            } else if self.closeState == .ServerClose {
                stream.close()
            }
        case .Continuation:
            return
        }
    }
    
    private func send(opCode: Frame.OpCode, data: Data) throws {
        let maskKey: Data
        if mode == .Client {
            maskKey = try Random.getBytes(4)
        } else {
            maskKey = nil
        }
        let frame = Frame(opCode: opCode, data: data, maskKey: maskKey)
        let data = frame.getData()
        try stream.send(data)
        try stream.flush()
    }
    
    static func accept(key: String) -> String? {
        return try? Base64.encode(Hash.hash(.SHA1, message: (key + GUID).data))
    }
    
}
