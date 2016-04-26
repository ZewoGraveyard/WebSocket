// Frame.swift
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

//	0                   1                   2                   3
//	0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
//	+-+-+-+-+-------+-+-------------+-------------------------------+
//	|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
//	|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
//	|N|V|V|V|       |S|             |   (if payload len==126/127)   |
//	| |1|2|3|       |K|             |                               |
//	+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
//	|     Extended payload length continued, if payload len == 127  |
//	+ - - - - - - - - - - - - - - - +-------------------------------+
//	|                               |Masking-key, if MASK set to 1  |
//	+-------------------------------+-------------------------------+
//	| Masking-key (continued)       |          Payload Data         |
//	+-------------------------------- - - - - - - - - - - - - - - - +
//	:                     Payload Data continued ...                :
//	+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
//	|                     Payload Data continued ...                |
//	+---------------------------------------------------------------+

struct Frame {
    
    private static let FinMask : UInt8 = 0b10000000
    private static let Rsv1Mask : UInt8 = 0b01000000
    private static let Rsv2Mask : UInt8 = 0b00100000
    private static let Rsv3Mask : UInt8 = 0b00010000
    private static let OpCodeMask : UInt8 = 0b00001111
    
    private static let MaskMask : UInt8 = 0b10000000
    private static let PayloadLenMask : UInt8 = 0b01111111
    
    enum OpCode: UInt8 {
        case Continuation	= 0x0
        case Text			= 0x1
        case Binary			= 0x2
        // 0x3 -> 0x7 reserved
        case Close			= 0x8
        case Ping			= 0x9
        case Pong			= 0xA
        // 0xB -> 0xF reserved
        case Invalid        = 0x10
        
        var isControl: Bool {
            return self == .Close || self == .Ping || self == .Pong
        }
    }
    
    var fin: Bool {
        return headerData[0] & Frame.FinMask != 0
    }

    var rsv1: Bool {
        return headerData[0] & Frame.Rsv1Mask != 0
    }

    var rsv2: Bool {
        return headerData[0] & Frame.Rsv2Mask != 0
    }

    var rsv3: Bool {
        return headerData[0] & Frame.Rsv3Mask != 0
    }

    var opCode: OpCode {
        if let opCode = Frame.OpCode(rawValue: headerData[0] & Frame.OpCodeMask) {
            return opCode
        }
        return .Invalid
    }

    var masked: Bool {
        return headerData[1] & Frame.MaskMask != 0
    }

    var payloadLength: UInt64 {
        return UInt64(headerData[1] & Frame.PayloadLenMask)
    }

    private var extendedPayloadLength: UInt64 {
        if payloadLength == 126 {
            return UInt64(UInt16(headerExtraData[0]) << 8 | UInt16(headerExtraData[1]) << 0)
        } else if payloadLength == 127 {
            return headerExtraData.withUnsafeBufferPointer(body: { ptr -> UInt64 in
                if let baseAddress = ptr.baseAddress {
//                    Int(UInt16(Data(data.prefix(2)).toInt(size: 2))) TODO TRY SOMETHING LIKE THIS
                    return UnsafePointer<UInt64>(baseAddress).pointee.bigEndian
                }
                return 0
            })
        }
        return payloadLength
    }

    private var maskKey: Data {
        if payloadLength <= 125 {
            return Data(headerExtraData[0..<4])
        } else if payloadLength == 126 {
            return Data(headerExtraData[2..<6])
        }
        return Data(headerExtraData[8..<12])
    }

    private var headerData = Data()
    private var headerExtraData = Data()
    private var payloadData = Data()

    init() {

    }

    init(opCode: OpCode, data: Data, maskKey: Data) {
        headerData.append((1 << 7) | (0 << 6) | (0 << 5) | (0 << 4) | opCode.rawValue)

        let masked = maskKey.count == 4
        let payloadLength = UInt64(data.count)

        if payloadLength > UInt64(UInt16.max) {
            headerData.append((masked ? 1 : 0) << 7 | 127)
            headerExtraData += Data(number: payloadLength)
        } else if payloadLength > 125 {
            headerData.append((masked ? 1 : 0) << 7 | 126)
            headerExtraData += Data(number: UInt16(payloadLength))
        } else {
            headerData.append((masked ? 1 : 0) << 7 | (UInt8(payloadLength) & 0x7F))
        }

        payloadData += data
    }

    func getPayload() -> Data {
        var unmaskedPayloadData = payloadData

        if masked {
            var maskOffset = 0
            for i in 0..<unmaskedPayloadData.count {
                unmaskedPayloadData[i] ^= maskKey[maskOffset % 4]
                maskOffset += 1
            }
        }

        return unmaskedPayloadData
    }

    func getData() -> Data {
        var data = Data()
        data += headerData
        data += headerExtraData
        data += getPayload()
        return data
    }

    mutating func addByte(byte: Byte) {
        func getExtendedPayloadLength() -> Int {
            return payloadLength == 126 ? 2 : (payloadLength == 127 ? 8 : 0)
        }

        if headerData.count < 2 {
            headerData.append(byte)
        } else if payloadLength == 126 && headerExtraData.count < 2 {
            headerExtraData.append(byte)
        } else if payloadLength == 127 && headerExtraData.count < 8 {
            headerExtraData.append(byte)
        } else if masked && headerExtraData.count < 4 + getExtendedPayloadLength() {
            headerExtraData.append(byte)
        } else {
            payloadData.append(byte)
        }
    }

    var isComplete: Bool {
        if headerData.count < 2 {
            return false
        } else if masked && headerExtraData.count < 4 {
            return false
        } else if payloadLength == 126 && headerExtraData.count < (masked ? 6 : 2) {
            return false
        } else if payloadLength == 127 && headerExtraData.count < (masked ? 12 : 8) {
            return false
        } else {
            if payloadLength <= 125 {
                return payloadData.count == Int(payloadLength)
            } else {
                return UInt64(payloadData.count) == extendedPayloadLength
            }
        }
    }

}

extension Sequence where Self.Iterator.Element == Frame {

    func getPayload() -> Data {
        var payload = Data()

        for frame in self {
            payload += frame.getPayload()
        }

        return payload
    }

}
