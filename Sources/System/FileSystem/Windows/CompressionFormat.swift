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

/// The algorithm used to compress a file.
///
/// These correspond to the `COMPRESSION_FORMAT_*` constants and appear in
/// ``FileCompressionInfo/compressionFormat``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct CompressionFormat: RawRepresentable, Sendable, Hashable, Codable {
  /// The raw C `WORD` value.
  @_alwaysEmitIntoClient
  public var rawValue: UInt16

  /// Creates a strongly-typed compression format from a raw C value.
  @_alwaysEmitIntoClient
  public init(rawValue: UInt16) { self.rawValue = rawValue }

  /// The file is not compressed.
  ///
  /// The corresponding C constant is `COMPRESSION_FORMAT_NONE`.
  @_alwaysEmitIntoClient
  public static var none: CompressionFormat { CompressionFormat(rawValue: 0x0000) }

  /// The file system's default algorithm.
  ///
  /// The corresponding C constant is `COMPRESSION_FORMAT_DEFAULT`.
  @_alwaysEmitIntoClient
  public static var `default`: CompressionFormat { CompressionFormat(rawValue: 0x0001) }

  /// LZNT1, the only algorithm NTFS implements for per-file compression, and
  /// therefore what ``default`` resolves to.
  ///
  /// The corresponding C constant is `COMPRESSION_FORMAT_LZNT1`.
  @_alwaysEmitIntoClient
  public static var lznt1: CompressionFormat { CompressionFormat(rawValue: 0x0002) }

  /// XPRESS. Defined by Windows but not reachable through NTFS per-file
  /// compression.
  ///
  /// The corresponding C constant is `COMPRESSION_FORMAT_XPRESS`.
  @_alwaysEmitIntoClient
  public static var xpress: CompressionFormat { CompressionFormat(rawValue: 0x0003) }

  /// XPRESS with Huffman coding. Defined by Windows but not reachable through
  /// NTFS per-file compression.
  ///
  /// The corresponding C constant is `COMPRESSION_FORMAT_XPRESS_HUFF`.
  @_alwaysEmitIntoClient
  public static var xpressHuffman: CompressionFormat { CompressionFormat(rawValue: 0x0004) }
}

#endif // os(Windows)
