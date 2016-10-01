import Core
import struct Foundation.Data

public enum WebSocketError : Error {
    case noFrame
    case invalidOpCode
    case maskedFrameFromServer
    case unaskedFrameFromClient
    case controlFrameNotFinal
    case controlFrameInvalidLength
    case continuationOutOfOrder
    case dataFrameWithInvalidBits
    case maskKeyInvalidLength
    case noMaskKey
    case invalidUTF8Payload
    case invalidCloseCode
}

public final class WebSocket {
    fileprivate static let GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    public let bufferSize = 4096

    public enum Mode {
        case server
        case client
    }

    fileprivate enum State {
        case header
        case headerExtra
        case payload
    }

    fileprivate enum CloseState {
        case open
        case serverClose
        case clientClose
    }

    public let mode: Mode

    fileprivate let stream: Core.Stream
    fileprivate var state: State = .header
    fileprivate var closeState: CloseState = .open

    fileprivate var incompleteFrame: Frame?
    fileprivate var continuationFrames: [Frame] = []

    fileprivate let binaryEventEmitter = EventEmitter<Data>()
    fileprivate let textEventEmitter = EventEmitter<String>()
    fileprivate let pingEventEmitter = EventEmitter<Data>()
    fileprivate let pongEventEmitter = EventEmitter<Data>()
    fileprivate let closeEventEmitter = EventEmitter<(code: CloseCode?, reason: String?)>()

    public init(stream: Core.Stream, mode: Mode) {
        self.stream = stream
        self.mode = mode
    }

    @discardableResult
    public func onBinary(_ listen: @escaping EventListener<Data>.Listen) -> EventListener<Data> {
        return binaryEventEmitter.addListener(listen: listen)
    }

    @discardableResult
    public func onText(_ listen: @escaping EventListener<String>.Listen) -> EventListener<String> {
        return textEventEmitter.addListener(listen: listen)
    }

    @discardableResult
    public func onPing(_ listen: @escaping EventListener<Data>.Listen) -> EventListener<Data> {
        return pingEventEmitter.addListener(listen: listen)
    }

    @discardableResult
    public func onPong(_ listen: @escaping EventListener<Data>.Listen) -> EventListener<Data> {
        return pongEventEmitter.addListener(listen: listen)
    }

    @discardableResult
    public func onClose(_ listen: @escaping EventListener<(code: CloseCode?, reason: String?)>.Listen) -> EventListener<(code: CloseCode?, reason: String?)> {
        return closeEventEmitter.addListener(listen: listen)
    }

    public func send(_ string: String) throws {
        try send(.text, data: Data(string))
    }

    public func send(_ data: Data) throws {
        try send(.binary, data: data)
    }

    public func send(_ convertible: DataConvertible) throws {
        try send(.binary, data: convertible.data)
    }

    public func close(_ code: CloseCode = .normal, reason: String? = nil) throws {
        if closeState == .serverClose {
            return
        }

        if closeState == .open {
            closeState = .serverClose
        }

        var data = Data(number: code.code)

        if let reason = reason {
            data.append(Data(reason))
        }

        if closeState == .serverClose && code == .protocolError {
            stream.close()
        }

        try send(.close, data: data)

        if closeState == .clientClose {
            stream.close()
        }
    }

    public func ping(_ data: Data = Data()) throws {
        try send(.ping, data: data)
    }

    public func ping(_ convertible: DataConvertible) throws {
        try send(.ping, data: convertible.data)
    }

    public func pong(_ data: Data = Data()) throws {
        try send(.pong, data: data)
    }

    public func pong(_ convertible: DataConvertible) throws {
        try send(.pong, data: convertible.data)
    }

    public func start() throws {
        while !stream.closed {
            do {
                var buffer = Data(count: bufferSize)
                let read = try stream.read(into: &buffer)
                try processData(buffer.subdata(in: 0..<read))
            } catch StreamError.closedStream {
                break
            }
        }
        if closeState == .open {
            try closeEventEmitter.emit((code: .abnormal, reason: nil))
        }
    }

    fileprivate func processData(_ data: Data) throws {
        guard data.count > 0 else {
            return
        }

        var totalBytesRead = 0

        while totalBytesRead < data.count {
            let bytesRead = try readBytes(data.subdata(in:totalBytesRead ..< data.count))

            if bytesRead == 0 {
                break
            }

            totalBytesRead += bytesRead
        }
    }

    fileprivate func readBytes(_ data: Data) throws -> Int {
        if data.count == 0 {
            return 0
        }

        var remainingData = data

        repeat {
            if incompleteFrame == nil {
                incompleteFrame = Frame()
            }

            // Use ! because if let will add data to a copy of the frame
            remainingData = incompleteFrame!.add(remainingData)

            if incompleteFrame!.isComplete {
                try validateFrame(incompleteFrame!)
                try processFrame(incompleteFrame!)
                incompleteFrame = nil
            }
        } while remainingData.count > 0

        return data.count
    }

    fileprivate func validateFrame(_ frame: Frame) throws {
        func fail(_ error: Error) throws -> Error {
            try close(.protocolError)
            return error
        }

        guard !frame.rsv1 && !frame.rsv2 && !frame.rsv3 else {
            throw try fail(WebSocketError.dataFrameWithInvalidBits)
        }

        guard frame.opCode != .invalid else {
            throw try fail(WebSocketError.invalidOpCode)
        }

        guard !frame.masked || self.mode == .server else {
            throw try fail(WebSocketError.maskedFrameFromServer)
        }

        guard frame.masked || self.mode == .client else {
            throw try fail(WebSocketError.unaskedFrameFromClient)
        }

        if frame.opCode.isControl {
            guard frame.fin else {
                throw try fail(WebSocketError.controlFrameNotFinal)
            }

            guard frame.payloadLength < 126 else {
                throw try fail(WebSocketError.controlFrameInvalidLength)
            }

            if frame.opCode == .close && frame.payloadLength == 1 {
                throw try fail(WebSocketError.controlFrameInvalidLength)
            }
        } else {
            if frame.opCode == .continuation && continuationFrames.isEmpty {
                throw try fail(WebSocketError.continuationOutOfOrder)
            }

            if frame.opCode != .continuation && !continuationFrames.isEmpty {
                throw try fail(WebSocketError.continuationOutOfOrder)
            }


        }
    }

    fileprivate func processFrame(_ frame: Frame) throws {
        func fail(_ error: Error) throws -> Error {
            try close(.protocolError)
            return error
        }

        if !frame.opCode.isControl {
            continuationFrames.append(frame)
        }

        if !frame.fin {
            return
        }

        var opCode = frame.opCode


        if frame.opCode == .continuation {
            let firstFrame = continuationFrames.first!
            opCode = firstFrame.opCode
        }

        switch opCode {
        case .binary:
            try binaryEventEmitter.emit(continuationFrames.payload)
        case .text:
            if (try? String(data: continuationFrames.payload)) == nil {
                throw try fail(WebSocketError.invalidUTF8Payload)
            }
            try textEventEmitter.emit(try String(data: continuationFrames.payload))
        case .ping:
            try pingEventEmitter.emit(frame.payload)
        case .pong:
            try pongEventEmitter.emit(frame.payload)
        case .close:
            if self.closeState == .open {
                var rawCloseCode: UInt16?
                var closeReason: String?
                var data = frame.payload

                if data.count >= 2 {
                    rawCloseCode = UInt16(data.subdata(in:0..<2).data.toInt(2))
                    data = data.subdata(in: 2..<data.count).data // TODO: is this efficient?

                    if data.count > 0 {
                        closeReason = try? String(data: data)
                    }

                    if data.count > 0 && closeReason == nil {
                        throw try fail(WebSocketError.invalidUTF8Payload)
                    }
                }

                closeState = .clientClose

                if let rawCloseCode = rawCloseCode {
                    let closeCode = CloseCode(code: rawCloseCode)
                    if closeCode.isValid {
                        try close(closeCode , reason: closeReason)
                        try closeEventEmitter.emit((closeCode, closeReason))
                    } else {
                        throw try fail(WebSocketError.invalidCloseCode)
                    }
                } else {
                    try close(reason: nil)
                    try closeEventEmitter.emit((nil, nil))
                }
            } else if self.closeState == .serverClose {
                stream.close()
            }
        default:
            break
        }

        if !frame.opCode.isControl {
            continuationFrames.removeAll()
        }
    }

    fileprivate func send(_ opCode: Frame.OpCode, data: Data) throws {
        let maskKey: Data
        if mode == .client {
            maskKey = try Data(randomBytes: 4)
        } else {
            maskKey = Data()
        }
        let frame = Frame(opCode: opCode, data: data, maskKey: maskKey)
        let data = frame.data
        try stream.write(data)
        try stream.flush()
    }

    public static func accept(_ key: String) -> String? {
        let hashed = sha1(Array((key + GUID).utf8))

        let encoded = Data(bytes: hashed).base64EncodedString(options: [])
        return encoded

    }
}
