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

/// A tag identifying the owner of a reparse point, and therefore how its data
/// is to be interpreted.
///
/// These correspond to the `IO_REPARSE_TAG_*` constants and appear in
/// ``FileAttributeTagInfo/reparseTag``. Reparse tags are extensible, so a tag
/// need not match any of the values below.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct ReparseTag: RawRepresentable, Sendable, Hashable, Codable {
  /// The raw C `DWORD` tag value.
  @_alwaysEmitIntoClient
  public var rawValue: UInt32

  /// Creates a strongly-typed reparse tag from a raw C value.
  @_alwaysEmitIntoClient
  public init(rawValue: UInt32) { self.rawValue = rawValue }

  /// Cluster Shared Volumes.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_CSV`.
  @_alwaysEmitIntoClient
  public static var csv: ReparseTag { ReparseTag(rawValue: 0x8000_0009) }

  /// Data deduplication.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_DEDUP`.
  @_alwaysEmitIntoClient
  public static var dedup: ReparseTag { ReparseTag(rawValue: 0x8000_0013) }

  /// Distributed File System.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_DFS`.
  @_alwaysEmitIntoClient
  public static var dfs: ReparseTag { ReparseTag(rawValue: 0x8000_000A) }

  /// DFS Replication.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_DFSR`.
  @_alwaysEmitIntoClient
  public static var dfsr: ReparseTag { ReparseTag(rawValue: 0x8000_0012) }

  /// Hierarchical Storage Management.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_HSM`.
  @_alwaysEmitIntoClient
  public static var hsm: ReparseTag { ReparseTag(rawValue: 0xC000_0004) }

  /// Hierarchical Storage Management, second generation.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_HSM2`.
  @_alwaysEmitIntoClient
  public static var hsm2: ReparseTag { ReparseTag(rawValue: 0x8000_0006) }

  /// A directory junction.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_MOUNT_POINT`.
  @_alwaysEmitIntoClient
  public static var mountPoint: ReparseTag { ReparseTag(rawValue: 0xA000_0003) }

  /// Network File System.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_NFS`.
  @_alwaysEmitIntoClient
  public static var nfs: ReparseTag { ReparseTag(rawValue: 0x8000_0014) }

  /// Single-Instance Storage.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_SIS`.
  @_alwaysEmitIntoClient
  public static var sis: ReparseTag { ReparseTag(rawValue: 0x8000_0007) }

  /// A symbolic link.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_SYMLINK`.
  @_alwaysEmitIntoClient
  public static var symbolicLink: ReparseTag { ReparseTag(rawValue: 0xA000_000C) }

  /// A Windows Imaging Format image backing.
  ///
  /// The corresponding C constant is `IO_REPARSE_TAG_WIM`.
  @_alwaysEmitIntoClient
  public static var wim: ReparseTag { ReparseTag(rawValue: 0x8000_0008) }
}

#endif // os(Windows)
