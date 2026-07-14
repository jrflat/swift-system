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

/// A point in time expressed in Windows FILETIME format: a 64-bit count of
/// 100-nanosecond intervals since January 1, 1601 (UTC).
///
/// This mirrors the way timestamps are stored in the `LARGE_INTEGER` time
/// members of structures such as ``FileBasicInfo``. It is the equivalent of
/// a `FILETIME`, but as a single scalar rather than a split high/low pair.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileTime: RawRepresentable, Sendable, Hashable, Codable {
  /// The raw count of 100-nanosecond intervals since January 1, 1601 (UTC).
  ///
  /// A value of `0` indicates the timestamp is unavailable; some file systems
  /// do not record every timestamp, such as the last-access time.
  @_alwaysEmitIntoClient
  public var rawValue: Int64

  /// Creates a strongly-typed `FileTime` from a raw interval count.
  @_alwaysEmitIntoClient
  public init(rawValue: Int64) { self.rawValue = rawValue }

  /// The number of 100-nanosecond intervals between the Windows epoch
  /// (1601-01-01) and the Unix epoch (1970-01-01).
  @_alwaysEmitIntoClient
  internal static var _ticksBetweenEpochs: Int64 { 116_444_736_000_000_000 }

  /// The number of 100-nanosecond intervals per second.
  @_alwaysEmitIntoClient
  internal static var _ticksPerSecond: Int64 { 10_000_000 }

  /// Creates a `FileTime` from a WinSDK `LARGE_INTEGER`.
  @_alwaysEmitIntoClient
  public init(_ value: LARGE_INTEGER) {
    self.rawValue = value.QuadPart
  }

  /// Creates a `FileTime` from a WinSDK `FILETIME`.
  @_alwaysEmitIntoClient
  public init(_ value: FILETIME) {
    self.rawValue = Int64(bitPattern:
      (UInt64(value.dwHighDateTime) << 32) | UInt64(value.dwLowDateTime)
    )
  }

  /// The value as a WinSDK `LARGE_INTEGER`, suitable for passing back to
  /// file-system APIs.
  @_alwaysEmitIntoClient
  public var largeInteger: LARGE_INTEGER {
    LARGE_INTEGER(QuadPart: rawValue)
  }

  /// The number of seconds between this timestamp and the Unix epoch
  /// (1970-01-01 00:00:00 UTC), truncated toward the epoch.
  ///
  /// This is convenient for bridging to POSIX-style time values.
  @_alwaysEmitIntoClient
  public var secondsSinceUnixEpoch: Int64 {
    (rawValue - Self._ticksBetweenEpochs) / Self._ticksPerSecond
  }
}

#endif // os(Windows)
