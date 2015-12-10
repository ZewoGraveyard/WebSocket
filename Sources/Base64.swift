// Base64.swift
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

private class Base64Encoder {

	enum Step { case A, B, C }

	static let paddingChar: UInt8 = 0x3D // =
	static let newlineChar: UInt8 = 0x0A // \n

	let chars: [UnicodeScalar]

	var step: Step = .A
	var result: UInt8 = 0

	var charsPerLine: Int?
	var stepcount: Int = 0

	let bytes: [UInt8]

	var offset = 0
	var output: [UInt8] = []

	init(bytes: [UInt8], charsPerLine: Int? = nil, specialChars: String? = nil) {
		self.charsPerLine = charsPerLine
		self.bytes = bytes
		self.chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".unicodeScalars) + Array((specialChars ?? "+/").unicodeScalars)
		guard bytes.count > 0 else { return }
		encodeBlock()
	}

	func encodeValue(value: UInt8) -> UInt8 {
		guard value <= 64 else { return Base64Encoder.paddingChar }
		return UInt8(chars[Int(value)].value)
	}

	func encodeBlock() {
		let fragment = bytes[offset]
		offset++

		switch step {
		case .A:
			result = (fragment & 0x0fc) >> 2
			output.append(encodeValue(result))
			result = (fragment & 0x003) << 4
			step = .B
		case .B:
			result |= (fragment & 0x0f0) >> 4
			output.append(encodeValue(result))
			result = (fragment & 0x00f) << 2
			step = .C
		case .C:
			result |= (fragment & 0x0c0) >> 6
			output.append(encodeValue(result))
			result  = (fragment & 0x03f) >> 0
			output.append(encodeValue(result))
			if let charsPerLine = self.charsPerLine {
				stepcount++
				if stepcount == charsPerLine/4 {
					output.append(Base64Encoder.newlineChar)
					stepcount = 0
				}
			}
			step = .A
		}

		if offset < bytes.count {
			encodeBlock()
		} else {
			encodeBlockEnd()
		}
	}

	func encodeBlockEnd() {
		switch step {
		case .A:
			break
		case .B:
			output.append(encodeValue(result))
			output.append(Base64Encoder.paddingChar)
			output.append(Base64Encoder.paddingChar)
		case .C:
			output.append(encodeValue(result))
			output.append(Base64Encoder.paddingChar)
		}
		if let _ = self.charsPerLine {
			output.append(Base64Encoder.newlineChar)
		}
	}

}

private class Base64Decoder {

	enum Step { case A, B, C, D }

	static let decoding: [Int8] = [62, -1, -1, -1, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -2, -1, -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51]

	static func decodeValue(value: UInt8) -> Int8 {
		let tmp = Int(value - 43)
		guard tmp >= 0 && tmp < Base64Decoder.decoding.count else { return -1 }
		return Base64Decoder.decoding[tmp]
	}

	var step: Step = .A

	let bytes: [UInt8]
	var offset = 0

	var output: [UInt8]
	var outputOffset = 0

	init(bytes: [UInt8]) {
		self.bytes = bytes
		self.output = [UInt8](count: bytes.count, repeatedValue: 0)
		guard bytes.count > 0 else { return }
		decodeBlock()
	}

	func decodeBlock() {
		var tmpFragment: Int8
		repeat {
			guard offset < bytes.count else { return }
			let byte = bytes[offset++]
			tmpFragment = Base64Decoder.decodeValue(byte)
		} while (tmpFragment < 0);
		let fragment = UInt8(bitPattern: tmpFragment)

		switch step {
		case .A:
			output[outputOffset]	 = (fragment & 0x03f) << 2
			step = .B
		case .B:
			output[outputOffset++]	|= (fragment & 0x030) >> 4
			output[outputOffset]	 = (fragment & 0x00f) << 4
			step = .C
		case .C:
			output[outputOffset++]	|= (fragment & 0x03c) >> 2
			output[outputOffset]	 = (fragment & 0x003) << 6
			step = .D
		case .D:
			output[outputOffset++]	|= (fragment & 0x03f)
			step = .A
		}

		decodeBlock()
	}

}

internal class Base64 {

	// MARK: - Encode

	internal static func encodeBytes(bytes bytes: [UInt8], charsPerLine: Int? = nil, specialChars: String? = nil) -> [UInt8] {
		let encoder = Base64Encoder(bytes: bytes, charsPerLine: charsPerLine)
		return encoder.output
	}

	internal static func encodeBytes(string string: String, charsPerLine: Int? = nil, specialChars: String? = nil) -> [UInt8] {
		let encoder = Base64Encoder(bytes: Array(string.utf8), charsPerLine: charsPerLine)
		return encoder.output
	}

	internal static func encodeString(bytes bytes: [UInt8], charsPerLine: Int? = nil, specialChars: String? = nil) -> String {
		let encoder = Base64Encoder(bytes: bytes, charsPerLine: charsPerLine)
		return String.fromBytes(encoder.output)
	}

	internal static func encodeString(string string: String, charsPerLine: Int? = nil, specialChars: String? = nil) -> String {
		let encoder = Base64Encoder(bytes: Array(string.utf8), charsPerLine: charsPerLine)
		return String.fromBytes(encoder.output)
	}

	// MARK: - Decode

	internal static func decodeBytes(bytes bytes: [UInt8]) -> [UInt8] {
		let encoder = Base64Decoder(bytes: bytes)
		return encoder.output
	}

	internal static func decodeBytes(string string: String) -> [UInt8] {
		let encoder = Base64Decoder(bytes: Array(string.utf8))
		return encoder.output
	}

	internal static func decodeString(bytes bytes: [UInt8]) -> String {
		let encoder = Base64Decoder(bytes: bytes)
		return String.fromBytes(encoder.output)
	}

	internal static func decodeString(string string: String) -> String {
		let encoder = Base64Decoder(bytes: Array(string.utf8))
		return String.fromBytes(encoder.output)
	}

}
