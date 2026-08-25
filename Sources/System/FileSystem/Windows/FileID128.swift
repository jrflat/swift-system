//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift System open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift System project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if os(Windows)

import WinSDK

/// A 128-bit file identifier.
///
/// Combined with a volume serial number, a `FileID128` uniquely identifies a
/// file on a single computer. This wraps the WinSDK `FILE_ID_128` type and
/// appears in ``FileIDInfo``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileID128: RawRepresentable, Sendable, Hashable {
  /// The raw C `FILE_ID_128` value.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_ID_128

  /// Creates a strongly-typed `FileID128` from the raw C value.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_ID_128) { self.rawValue = rawValue }

  /// The 16 identifier bytes, in the order stored by the file system.
  @_alwaysEmitIntoClient
  public var bytes: (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  ) {
    rawValue.Identifier
  }

  @_alwaysEmitIntoClient
  public static func == (lhs: FileID128, rhs: FileID128) -> Bool {
    withUnsafeBytes(of: lhs.rawValue) { l in
      withUnsafeBytes(of: rhs.rawValue) { r in
        l.elementsEqual(r)
      }
    }
  }

  @_alwaysEmitIntoClient
  public func hash(into hasher: inout Hasher) {
    withUnsafeBytes(of: rawValue) { hasher.combine(bytes: $0) }
  }
}

@available(System 99, *)
extension FileID128: Codable {
  /// Creates a `FileID128` from an encoded array of its 16 identifier bytes.
  @_alwaysEmitIntoClient
  public init(from decoder: any Decoder) throws {
    let bytes = try [UInt8](from: decoder)
    let count = MemoryLayout<FILE_ID_128>.size
    guard bytes.count == count else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "FileID128 requires exactly \(count) bytes"))
    }
    var raw = FILE_ID_128()
    withUnsafeMutableBytes(of: &raw) { $0.copyBytes(from: bytes) }
    self.init(rawValue: raw)
  }

  @_alwaysEmitIntoClient
  public func encode(to encoder: any Encoder) throws {
    try withUnsafeBytes(of: rawValue) { try Array($0).encode(to: encoder) }
  }
}

@available(System 99, *)
extension FileID128: CustomStringConvertible {
  /// The identifier bytes as a lowercase hexadecimal string, in the order
  /// stored by the file system.
  @inline(never)
  public var description: String {
    withUnsafeBytes(of: rawValue) { bytes in
      var result = ""
      result.reserveCapacity(2 * bytes.count)
      for byte in bytes {
        result += byte < 0x10 ? "0" : ""
        result += String(byte, radix: 16)
      }
      return result
    }
  }
}

#endif // os(Windows)
