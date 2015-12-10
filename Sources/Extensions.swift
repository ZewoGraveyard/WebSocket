// Extensions.swift
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

internal extension String {
	static func fromBytes(bytes: [UInt8]) -> String {
		var encodedString = ""
		var decoder = UTF8()
		var generator = bytes.generate()
		var finished: Bool = false
		repeat {
			let decodingResult = decoder.decode(&generator)
			switch decodingResult {
			case .Result(let char):
				if char == UnicodeScalar(0) {
					finished = true
				} else {
					encodedString.append(char)
				}
			case .EmptyInput:
				finished = true
			case .Error:
				finished = true
			}
		} while (!finished)
		return encodedString
	}
}

internal func bytesToUInt(byteArray: [UInt8]) -> UInt {
	assert(byteArray.count <= 4)
	var result: UInt = 0
	for idx in 0..<(byteArray.count) {
		let shiftAmount = UInt((byteArray.count) - idx - 1) * 8
		result += UInt(byteArray[idx]) << shiftAmount
	}
	return result
}

internal extension UInt8 {
	var hexString: String {
		let str = String(self, radix: 16)
		return (self < 16 ? "0"+str : str)
	}
}

internal extension Array {
	var unsafeLast: Element {
		get {
			return self[self.endIndex.predecessor()]
		}
		set {
			self[self.endIndex.predecessor()] = newValue
		}
	}
}

internal extension CollectionType where Generator.Element == UInt8 {
	var hexString: String {
		return self.map { $0.hexString }.joinWithSeparator("")
	}

	func toInt(size size: Self.Index.Distance, offset: Self.Index.Distance = 0) -> UIntMax {
		guard size > 0 && size <= 8 && self.count >= offset+size else { return 0 }
		let slice = self[self.startIndex.advancedBy(offset) ..< self.startIndex.advancedBy(offset+size)]
		var result: UIntMax = 0
		for (idx, el) in slice.enumerate() {
			guard let byte = el as? UInt8 else { return 0 }
			let shiftAmount = UIntMax(size.toIntMax() - idx - 1) * 8
			result += UIntMax(byte) << shiftAmount
		}
		return result
	}
}

internal extension UInt16 {
	func bytes(totalBytes: Int = sizeof(UInt16)) -> [UInt8] {
		var totalBytes = totalBytes
		let valuePointer = UnsafeMutablePointer<UInt16>.alloc(1)
		valuePointer.memory = self
		let bytesPointer = UnsafeMutablePointer<UInt8>(valuePointer)
		var bytes = [UInt8](count: totalBytes, repeatedValue: 0)
		let size = sizeof(UInt16)
		if totalBytes > size { totalBytes = size }
		for j in 0 ..< totalBytes {
			bytes[totalBytes - 1 - j] = (bytesPointer + j).memory
		}
		valuePointer.destroy()
		valuePointer.dealloc(1)
		return bytes
	}
}

internal extension UInt64 {
	func bytes(totalBytes: Int = sizeof(UInt64)) -> [UInt8] {
		var totalBytes = totalBytes
		let valuePointer = UnsafeMutablePointer<UInt64>.alloc(1)
		valuePointer.memory = self
		let bytesPointer = UnsafeMutablePointer<UInt8>(valuePointer)
		var bytes = [UInt8](count: totalBytes, repeatedValue: 0)
		let size = sizeof(UInt64)
		if totalBytes > size { totalBytes = size }
		for j in 0 ..< totalBytes {
			bytes[totalBytes - 1 - j] = (bytesPointer + j).memory
		}
		valuePointer.destroy()
		valuePointer.dealloc(1)
		return bytes
	}
}
