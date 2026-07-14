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

/// Attributes of a file or directory, as reported by the Windows file system.
///
/// These correspond to the `FILE_ATTRIBUTE_*` constants and appear in
/// the `FileAttributes` member of several structures returned by
/// ``FileDescriptor/fileInformation(_:)`` and related APIs, such as
/// ``FileBasicInfo`` and ``FileAttributeTagInfo``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileAttributes: OptionSet, Sendable, Hashable, Codable {
  /// The raw C `DWORD` bitmask of `FILE_ATTRIBUTE_*` flags.
  @_alwaysEmitIntoClient
  public let rawValue: DWORD

  /// Creates a strongly-typed set of file attributes from a raw C bitmask.
  @_alwaysEmitIntoClient
  public init(rawValue: DWORD) { self.rawValue = rawValue }

  /// The file is read-only.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_READONLY`.
  @_alwaysEmitIntoClient
  public static var readOnly: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_READONLY))
  }

  /// The file is hidden and not included in an ordinary directory listing.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_HIDDEN`.
  @_alwaysEmitIntoClient
  public static var hidden: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_HIDDEN))
  }

  /// The file is part of, or used exclusively by, the operating system.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_SYSTEM`.
  @_alwaysEmitIntoClient
  public static var system: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_SYSTEM))
  }

  /// The handle identifies a directory.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_DIRECTORY`.
  @_alwaysEmitIntoClient
  public static var directory: FileAttributes {
    FileAttributes(rawValue: DWORD(WinSDK.FILE_ATTRIBUTE_DIRECTORY))
  }

  /// The file should be archived. Applications use this attribute to mark
  /// files for backup or removal.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_ARCHIVE`.
  @_alwaysEmitIntoClient
  public static var archive: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_ARCHIVE))
  }

  /// The file has no other attributes set. Valid only when used alone.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_NORMAL`.
  @_alwaysEmitIntoClient
  public static var normal: FileAttributes {
    FileAttributes(rawValue: DWORD(WinSDK.FILE_ATTRIBUTE_NORMAL))
  }

  /// The file is being used for temporary storage.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_TEMPORARY`.
  @_alwaysEmitIntoClient
  public static var temporary: FileAttributes {
    FileAttributes(rawValue: DWORD(WinSDK.FILE_ATTRIBUTE_TEMPORARY))
  }

  /// The file is a sparse file.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_SPARSE_FILE`.
  @_alwaysEmitIntoClient
  public static var sparseFile: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_SPARSE_FILE))
  }

  /// The file or directory has an associated reparse point, or is a symbolic link.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_REPARSE_POINT`.
  @_alwaysEmitIntoClient
  public static var reparsePoint: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_REPARSE_POINT))
  }

  /// The file or directory is compressed.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_COMPRESSED`.
  @_alwaysEmitIntoClient
  public static var compressed: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_COMPRESSED))
  }

  /// The data of the file is not immediately available (offline storage).
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_OFFLINE`.
  @_alwaysEmitIntoClient
  public static var offline: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_OFFLINE))
  }

  /// The file or directory is not to be indexed by the content indexing service.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_NOT_CONTENT_INDEXED`.
  @_alwaysEmitIntoClient
  public static var notContentIndexed: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_NOT_CONTENT_INDEXED))
  }

  /// The file or directory is encrypted.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_ENCRYPTED`.
  @_alwaysEmitIntoClient
  public static var encrypted: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_ENCRYPTED))
  }

  /// The directory or user data stream is configured with integrity. This is
  /// only supported on ReFS volumes.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_INTEGRITY_STREAM`.
  @_alwaysEmitIntoClient
  public static var integrityStream: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_INTEGRITY_STREAM))
  }

  /// The user data stream is not to be read by the background data integrity
  /// scanner. This is only supported on Storage Spaces and ReFS volumes.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_NO_SCRUB_DATA`.
  @_alwaysEmitIntoClient
  public static var noScrubData: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_NO_SCRUB_DATA))
  }

  /// The file or directory should be kept fully present locally even when not
  /// being actively accessed. This attribute is used by hierarchical storage
  /// management software.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_PINNED`.
  @_alwaysEmitIntoClient
  public static var pinned: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_PINNED))
  }

  /// The file or directory should not be kept fully present locally except
  /// when being actively accessed. This attribute is used by hierarchical
  /// storage management software.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_UNPINNED`.
  @_alwaysEmitIntoClient
  public static var unpinned: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_UNPINNED))
  }

  /// The file or directory is not fully present locally. Reading the file or
  /// enumerating the directory will be more expensive than normal, as it will
  /// cause at least some of the content to be fetched from a remote store.
  ///
  /// The corresponding C constant is `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS`.
  @_alwaysEmitIntoClient
  public static var recallOnDataAccess: FileAttributes {
    FileAttributes(rawValue: DWORD(FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS))
  }
}

@available(System 99, *)
extension FileAttributes: CustomStringConvertible {
  /// A textual representation of the file attributes.
  @inline(never)
  public var description: String {
    let descriptions: [(Element, StaticString)] = [
      (.readOnly, ".readOnly"),
      (.hidden, ".hidden"),
      (.system, ".system"),
      (.directory, ".directory"),
      (.archive, ".archive"),
      (.normal, ".normal"),
      (.temporary, ".temporary"),
      (.sparseFile, ".sparseFile"),
      (.reparsePoint, ".reparsePoint"),
      (.compressed, ".compressed"),
      (.offline, ".offline"),
      (.notContentIndexed, ".notContentIndexed"),
      (.encrypted, ".encrypted"),
      (.integrityStream, ".integrityStream"),
      (.noScrubData, ".noScrubData"),
      (.pinned, ".pinned"),
      (.unpinned, ".unpinned"),
      (.recallOnDataAccess, ".recallOnDataAccess"),
    ]
    return _buildDescription(descriptions)
  }
}

#endif // os(Windows)
