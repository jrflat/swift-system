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

// MARK: - FileInfoClass

/// Identifies the type of file information to retrieve from a file handle.
///
/// This is a wrapper around the C `FILE_INFO_BY_HANDLE_CLASS` enumeration,
/// limited to the classes that retrieve information. The classes that only
/// set information are not included.
///
/// You rarely need this type: each class has a dedicated API that names it, and
/// which you should prefer. The fixed-size classes are retrieved by requesting
/// their ``FileInfoByHandle`` type from ``FileDescriptor/fileInformation(_:)``;
/// the rest are listed on the cases below. It is here for
/// ``FileDescriptor/withUnsafeFileInformation(_:minimumCapacity:maximumCapacity:_:)``,
/// the escape hatch for classes this library does not model.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileInfoClass: RawRepresentable, Sendable, Hashable {
  /// The raw C `FILE_INFO_BY_HANDLE_CLASS` value.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_INFO_BY_HANDLE_CLASS

  /// Creates a strongly-typed info class from the raw C enumeration value.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_INFO_BY_HANDLE_CLASS) { self.rawValue = rawValue }

  /// Minimal information: timestamps and attributes. Selects ``FileBasicInfo``.
  ///
  /// The corresponding C constant is `FileBasicInfo`.
  @_alwaysEmitIntoClient
  public static var basic: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileBasicInfo) }

  /// Extended information: sizes, link count, and status. Selects ``FileStandardInfo``.
  ///
  /// The corresponding C constant is `FileStandardInfo`.
  @_alwaysEmitIntoClient
  public static var standard: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileStandardInfo) }

  /// The file's name, as opened. Retrieved by
  /// ``FileDescriptor/fileName(normalized:)``.
  ///
  /// The corresponding C constant is `FileNameInfo`.
  @_alwaysEmitIntoClient
  public static var name: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileNameInfo) }

  /// The file's fully resolved name. Retrieved by
  /// ``FileDescriptor/fileName(normalized:)``.
  ///
  /// The corresponding C constant is `FileNormalizedNameInfo`.
  @_alwaysEmitIntoClient
  public static var normalizedName: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileNormalizedNameInfo)
  }

  /// The file's data streams, as a chain of `FILE_STREAM_INFO` entries.
  /// Retrieved by ``FileDescriptor/dataStreams()``, which decodes them into
  /// ``FileStreamInfo`` values.
  ///
  /// The corresponding C constant is `FileStreamInfo`.
  @_alwaysEmitIntoClient
  public static var stream: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileStreamInfo) }

  /// Compression information. Selects ``FileCompressionInfo``.
  ///
  /// The corresponding C constant is `FileCompressionInfo`.
  @_alwaysEmitIntoClient
  public static var compression: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileCompressionInfo) }

  /// Attributes and reparse tag. Selects ``FileAttributeTagInfo``.
  ///
  /// The corresponding C constant is `FileAttributeTagInfo`.
  @_alwaysEmitIntoClient
  public static var attributeTag: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileAttributeTagInfo) }

  /// Directory entries with 64-bit file IDs and short names, as a chain of
  /// `FILE_ID_BOTH_DIR_INFO` entries. Selects ``FileIDBothDirectoryEntry``.
  ///
  /// Requires a directory handle. Enumerate with
  /// ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)``, which drives this
  /// class and ``idBothDirectoryRestart`` together.
  ///
  /// The corresponding C constant is `FileIdBothDirectoryInfo`.
  @_alwaysEmitIntoClient
  public static var idBothDirectory: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileIdBothDirectoryInfo)
  }

  /// Like ``idBothDirectory``, but restarts the enumeration from the beginning.
  ///
  /// The corresponding C constant is `FileIdBothDirectoryRestartInfo`.
  @_alwaysEmitIntoClient
  public static var idBothDirectoryRestart: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileIdBothDirectoryRestartInfo)
  }

  /// Information about the remote protocol serving the file. Selects
  /// ``FileRemoteProtocolInfo``.
  ///
  /// The corresponding C constant is `FileRemoteProtocolInfo`.
  @_alwaysEmitIntoClient
  public static var remoteProtocol: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileRemoteProtocolInfo)
  }

  /// Directory entries, as a chain of `FILE_FULL_DIR_INFO` entries. Selects
  /// ``FileFullDirectoryEntry``.
  ///
  /// This is a subset of ``idBothDirectory`` and is faster, because it reads
  /// only the directory entry rather than also consulting the master file
  /// table. Requires a directory handle. Enumerate with
  /// ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)``, which drives this
  /// class and ``fullDirectoryRestart`` together.
  ///
  /// The corresponding C constant is `FileFullDirectoryInfo`.
  @_alwaysEmitIntoClient
  public static var fullDirectory: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileFullDirectoryInfo)
  }

  /// Like ``fullDirectory``, but restarts the enumeration from the beginning.
  ///
  /// The corresponding C constant is `FileFullDirectoryRestartInfo`.
  @_alwaysEmitIntoClient
  public static var fullDirectoryRestart: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileFullDirectoryRestartInfo)
  }

  /// Storage-alignment information. Selects ``FileStorageInfo``.
  ///
  /// The corresponding C constant is `FileStorageInfo`.
  @_alwaysEmitIntoClient
  public static var storage: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileStorageInfo) }

  /// Buffer-alignment requirements. Selects ``FileAlignmentInfo``.
  ///
  /// The corresponding C constant is `FileAlignmentInfo`.
  @_alwaysEmitIntoClient
  public static var alignment: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileAlignmentInfo) }

  /// Volume serial number and 128-bit file identifier. Selects ``FileIDInfo``.
  ///
  /// The corresponding C constant is `FileIdInfo`.
  @_alwaysEmitIntoClient
  public static var id: FileInfoClass { FileInfoClass(rawValue: WinSDK.FileIdInfo) }

  /// Directory entries with 128-bit file IDs and reparse tags, as a chain of
  /// `FILE_ID_EXTD_DIR_INFO` entries. Selects
  /// ``FileIDExtendedDirectoryEntry``.
  ///
  /// Requires a directory handle. Enumerate with
  /// ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)``, which drives this
  /// class and ``idExtendedDirectoryRestart`` together.
  ///
  /// The corresponding C constant is `FileIdExtdDirectoryInfo`.
  @_alwaysEmitIntoClient
  public static var idExtendedDirectory: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileIdExtdDirectoryInfo)
  }

  /// Like ``idExtendedDirectory``, but restarts the enumeration from the
  /// beginning.
  ///
  /// The corresponding C constant is `FileIdExtdDirectoryRestartInfo`.
  @_alwaysEmitIntoClient
  public static var idExtendedDirectoryRestart: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileIdExtdDirectoryRestartInfo)
  }

  /// Per-directory case sensitivity. Selects ``FileCaseSensitiveInfo``.
  ///
  /// The corresponding C constant is `FileCaseSensitiveInfo`.
  @_alwaysEmitIntoClient
  public static var caseSensitive: FileInfoClass {
    FileInfoClass(rawValue: WinSDK.FileCaseSensitiveInfo)
  }
}

@available(System 99, *)
extension FileInfoClass: CustomStringConvertible {
  /// A textual representation of the info class.
  @inline(never)
  public var description: String {
    switch self {
    case .basic: return "basic"
    case .standard: return "standard"
    case .name: return "name"
    case .normalizedName: return "normalizedName"
    case .stream: return "stream"
    case .compression: return "compression"
    case .attributeTag: return "attributeTag"
    case .idBothDirectory: return "idBothDirectory"
    case .idBothDirectoryRestart: return "idBothDirectoryRestart"
    case .remoteProtocol: return "remoteProtocol"
    case .fullDirectory: return "fullDirectory"
    case .fullDirectoryRestart: return "fullDirectoryRestart"
    case .storage: return "storage"
    case .alignment: return "alignment"
    case .id: return "id"
    case .idExtendedDirectory: return "idExtendedDirectory"
    case .idExtendedDirectoryRestart: return "idExtendedDirectoryRestart"
    case .caseSensitive: return "caseSensitive"
    default: return "FileInfoClass(rawValue: \(rawValue.rawValue))"
    }
  }
}

// MARK: - FileBasicInfo

/// The basic information for a file: its timestamps and attributes.
///
/// This is a Swift wrapper of the C `FILE_BASIC_INFO` struct, retrieved by
/// ``FileDescriptor/fileInformation(_:)``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileBasicInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_BASIC_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_BASIC_INFO

  /// Creates a Swift `FileBasicInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_BASIC_INFO) { self.rawValue = rawValue }

  /// The time the file was created.
  ///
  /// The corresponding C member is `CreationTime`.
  @_alwaysEmitIntoClient
  public var creationTime: FileTime {
    get { FileTime(rawValue.CreationTime) }
    set { rawValue.CreationTime = newValue.largeInteger }
  }

  /// The time the file was last accessed.
  ///
  /// The corresponding C member is `LastAccessTime`.
  @_alwaysEmitIntoClient
  public var lastAccessTime: FileTime {
    get { FileTime(rawValue.LastAccessTime) }
    set { rawValue.LastAccessTime = newValue.largeInteger }
  }

  /// The time the file's data stream was last written to.
  ///
  /// The corresponding C member is `LastWriteTime`.
  @_alwaysEmitIntoClient
  public var lastWriteTime: FileTime {
    get { FileTime(rawValue.LastWriteTime) }
    set { rawValue.LastWriteTime = newValue.largeInteger }
  }

  /// The time the file's metadata was last changed.
  ///
  /// Unlike ``lastWriteTime``, which reflects changes to the underlying data
  /// stream, this reflects metadata changes such as renames and attribute
  /// changes.
  ///
  /// The corresponding C member is `ChangeTime`.
  @_alwaysEmitIntoClient
  public var changeTime: FileTime {
    get { FileTime(rawValue.ChangeTime) }
    set { rawValue.ChangeTime = newValue.largeInteger }
  }

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  @_alwaysEmitIntoClient
  public var attributes: FileAttributes {
    get { FileAttributes(rawValue: rawValue.FileAttributes) }
    set { rawValue.FileAttributes = newValue.rawValue }
  }
}

// MARK: - FileStandardInfo

/// Standard information for a file: sizes, link count, deletion status, and
/// directory status.
///
/// This is a Swift wrapper of the C `FILE_STANDARD_INFO` struct, retrieved
/// by ``FileDescriptor/fileInformation(_:)``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileStandardInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_STANDARD_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_STANDARD_INFO

  /// Creates a Swift `FileStandardInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_STANDARD_INFO) { self.rawValue = rawValue }

  /// The number of bytes allocated for the file on disk.
  ///
  /// This is usually a multiple of the sector or cluster size of the
  /// underlying device.
  ///
  /// The corresponding C member is `AllocationSize`.
  @_alwaysEmitIntoClient
  public var allocationSize: Int64 {
    rawValue.AllocationSize.QuadPart
  }

  /// The offset of the byte immediately following the last valid byte, i.e.
  /// the logical size of the file.
  ///
  /// The corresponding C member is `EndOfFile`.
  ///
  /// - Note: ``size`` is a synonym for this property.
  @_alwaysEmitIntoClient
  public var endOfFile: Int64 {
    rawValue.EndOfFile.QuadPart
  }

  /// The logical size of the file, in bytes.
  ///
  /// This is a synonym for the ``endOfFile`` property.
  @_alwaysEmitIntoClient
  public var size: Int64 {
    endOfFile
  }

  /// The number of hard links to the file.
  ///
  /// The corresponding C member is `NumberOfLinks`.
  @_alwaysEmitIntoClient
  public var linkCount: Int {
    Int(rawValue.NumberOfLinks)
  }

  /// Whether the file is pending deletion.
  ///
  /// The corresponding C member is `DeletePending`.
  @_alwaysEmitIntoClient
  public var isDeletePending: Bool {
    rawValue.DeletePending != 0
  }

  /// Whether the handle refers to a directory.
  ///
  /// The corresponding C member is `Directory`.
  @_alwaysEmitIntoClient
  public var isDirectory: Bool {
    rawValue.Directory != 0
  }
}

// MARK: - FileIDInfo

/// Identification information for a file: its volume serial number and 128-bit
/// file identifier.
///
/// The identifier and volume serial number together uniquely identify a file
/// on a single computer at a single point in time. This is a Swift wrapper of
/// the C `FILE_ID_INFO` struct, retrieved by
/// ``FileDescriptor/fileInformation(_:)``.
///
/// Prefer this over the 64-bit index reported by `GetFileInformationByHandle`,
/// which is not guaranteed to be unique on ReFS.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileIDInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_ID_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_ID_INFO

  /// Creates a Swift `FileIDInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_ID_INFO) { self.rawValue = rawValue }

  /// The serial number of the volume that contains the file.
  ///
  /// The corresponding C member is `VolumeSerialNumber`.
  @_alwaysEmitIntoClient
  public var volumeSerialNumber: UInt64 {
    rawValue.VolumeSerialNumber
  }

  /// The 128-bit file identifier.
  ///
  /// To determine whether two open handles refer to the same file, compare
  /// both this and ``volumeSerialNumber``.
  ///
  /// - Important: File identifiers are unique only within a static file
  ///   system. They are not stable over time: file systems are free to reuse
  ///   an identifier once its file is deleted, and some can change the
  ///   identifier of a live file. On FAT, for instance, the identifier is
  ///   derived from the byte offset of the file's directory entry, which
  ///   defragmentation and lengthening renames can both move. Do not persist
  ///   an identifier and expect it to name the same file later.
  ///
  /// The corresponding C member is `FileId`.
  @_alwaysEmitIntoClient
  public var fileID: FileID128 {
    FileID128(rawValue: rawValue.FileId)
  }
}

// MARK: - FileAttributeTagInfo

/// A file's attributes together with its reparse tag.
///
/// This is a Swift wrapper of the C `FILE_ATTRIBUTE_TAG_INFO` struct,
/// retrieved by ``FileDescriptor/fileInformation(_:)``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileAttributeTagInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_ATTRIBUTE_TAG_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_ATTRIBUTE_TAG_INFO

  /// Creates a Swift `FileAttributeTagInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_ATTRIBUTE_TAG_INFO) { self.rawValue = rawValue }

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  @_alwaysEmitIntoClient
  public var attributes: FileAttributes {
    FileAttributes(rawValue: rawValue.FileAttributes)
  }

  /// The reparse tag, or `nil` if the file is not a reparse point.
  ///
  /// The corresponding C member is `ReparseTag`, which is undefined unless
  /// ``attributes`` contains ``FileAttributes/reparsePoint``.
  @_alwaysEmitIntoClient
  public var reparseTag: ReparseTag? {
    guard attributes.contains(.reparsePoint) else { return nil }
    return ReparseTag(rawValue: rawValue.ReparseTag)
  }
}

// MARK: - FileStorageInfo

/// Storage-alignment information for a file's underlying device.
///
/// This is a Swift wrapper of the C `FILE_STORAGE_INFO` struct, retrieved by
/// ``FileDescriptor/fileInformation(_:)``.
///
/// On a volume built from several devices, such as a mirrored, spanned,
/// striped, or RAID configuration, the reported sizes are those of the largest
/// underlying device.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileStorageInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_STORAGE_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_STORAGE_INFO

  /// Creates a Swift `FileStorageInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_STORAGE_INFO) { self.rawValue = rawValue }

  /// The sentinel returned in ``byteOffsetForSectorAlignment`` and
  /// ``byteOffsetForPartitionAlignment`` when alignment could not be computed.
  ///
  /// The corresponding C constant is `STORAGE_INFO_OFFSET_UNKNOWN`.
  @_alwaysEmitIntoClient
  public static var offsetUnknown: UInt32 { 0xffff_ffff }

  /// Logical bytes per sector reported by the physical storage: the smallest
  /// size for which uncached I/O is supported.
  ///
  /// The corresponding C member is `LogicalBytesPerSector`.
  @_alwaysEmitIntoClient
  public var logicalBytesPerSector: UInt32 {
    rawValue.LogicalBytesPerSector
  }

  /// Bytes per sector for atomic writes.
  ///
  /// The corresponding C member is `PhysicalBytesPerSectorForAtomicity`.
  @_alwaysEmitIntoClient
  public var physicalBytesPerSectorForAtomicity: UInt32 {
    rawValue.PhysicalBytesPerSectorForAtomicity
  }

  /// Bytes per sector for optimal write performance.
  ///
  /// The corresponding C member is `PhysicalBytesPerSectorForPerformance`.
  @_alwaysEmitIntoClient
  public var physicalBytesPerSectorForPerformance: UInt32 {
    rawValue.PhysicalBytesPerSectorForPerformance
  }

  /// The block size used for atomicity by the file system.
  ///
  /// The corresponding C member is
  /// `FileSystemEffectivePhysicalBytesPerSectorForAtomicity`.
  @_alwaysEmitIntoClient
  public var fileSystemEffectivePhysicalBytesPerSectorForAtomicity: UInt32 {
    rawValue.FileSystemEffectivePhysicalBytesPerSectorForAtomicity
  }

  /// Flags describing the alignment of the storage.
  ///
  /// The corresponding C member is `Flags`.
  @_alwaysEmitIntoClient
  public var flags: Flags {
    Flags(rawValue: rawValue.Flags)
  }

  /// The logical sector offset within the first physical sector, in bytes, or
  /// ``offsetUnknown`` if it could not be computed.
  ///
  /// The corresponding C member is `ByteOffsetForSectorAlignment`.
  @_alwaysEmitIntoClient
  public var byteOffsetForSectorAlignment: UInt32 {
    rawValue.ByteOffsetForSectorAlignment
  }

  /// The offset used to align the partition to a physical sector boundary, in
  /// bytes, or ``offsetUnknown`` if it could not be computed.
  ///
  /// The corresponding C member is `ByteOffsetForPartitionAlignment`.
  @_alwaysEmitIntoClient
  public var byteOffsetForPartitionAlignment: UInt32 {
    rawValue.ByteOffsetForPartitionAlignment
  }

  /// Alignment flags for a ``FileStorageInfo`` value.
  @frozen
  public struct Flags: OptionSet, Sendable, Hashable, Codable {
    /// The raw C bitmask.
    @_alwaysEmitIntoClient
    public var rawValue: UInt32

    /// Creates alignment flags from a raw C bitmask.
    @_alwaysEmitIntoClient
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The logical sectors of the storage device are aligned to physical
    /// sector boundaries.
    ///
    /// The corresponding C constant is `STORAGE_INFO_FLAGS_ALIGNED_DEVICE`.
    @_alwaysEmitIntoClient
    public static var alignedDevice: Flags { Flags(rawValue: 0x0000_0001) }

    /// The partition is aligned to physical sector boundaries on the storage
    /// device.
    ///
    /// The corresponding C constant is
    /// `STORAGE_INFO_FLAGS_PARTITION_ALIGNED_ON_DEVICE`.
    @_alwaysEmitIntoClient
    public static var partitionAlignedOnDevice: Flags { Flags(rawValue: 0x0000_0002) }
  }
}

// MARK: - FileAlignmentInfo

/// The buffer-alignment requirement for the file.
///
/// This is a Swift wrapper of the C `FILE_ALIGNMENT_INFO` struct, retrieved
/// by ``FileDescriptor/fileInformation(_:)``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileAlignmentInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_ALIGNMENT_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_ALIGNMENT_INFO

  /// Creates a Swift `FileAlignmentInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_ALIGNMENT_INFO) { self.rawValue = rawValue }

  /// The alignment requirement as a bit mask: one less than ``alignment``.
  /// Zero means there is no requirement.
  ///
  /// The corresponding C member is `AlignmentRequirement`. Note that although
  /// Windows documents it as a byte count, its `FILE_*_ALIGNMENT` values are
  /// masks: `FILE_LONG_ALIGNMENT`, for example, is 3 rather than 4.
  @_alwaysEmitIntoClient
  public var alignmentRequirement: UInt32 {
    rawValue.AlignmentRequirement
  }

  /// The required buffer alignment, in bytes. A value of 1 means buffers may
  /// be placed at any address.
  @_alwaysEmitIntoClient
  public var alignment: Int {
    Int(alignmentRequirement) + 1
  }
}

// MARK: - FileCompressionInfo

/// Compression information for a file.
///
/// This is a Swift wrapper of the C `FILE_COMPRESSION_INFO` struct, retrieved
/// by ``FileDescriptor/fileInformation(_:)``.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileCompressionInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_COMPRESSION_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_COMPRESSION_INFO

  /// Creates a Swift `FileCompressionInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_COMPRESSION_INFO) { self.rawValue = rawValue }

  /// The size of the compressed file, in bytes.
  ///
  /// The corresponding C member is `CompressedFileSize`.
  @_alwaysEmitIntoClient
  public var compressedFileSize: Int64 {
    rawValue.CompressedFileSize.QuadPart
  }

  /// The compression format used to compress the file.
  ///
  /// The corresponding C member is `CompressionFormat`.
  @_alwaysEmitIntoClient
  public var compressionFormat: CompressionFormat {
    CompressionFormat(rawValue: rawValue.CompressionFormat)
  }

  /// The compression unit shift factor.
  ///
  /// The corresponding C member is `CompressionUnitShift`.
  @_alwaysEmitIntoClient
  public var compressionUnitShift: UInt8 {
    rawValue.CompressionUnitShift
  }

  /// The number of chunks shifted by compression.
  ///
  /// The corresponding C member is `ChunkShift`.
  @_alwaysEmitIntoClient
  public var chunkShift: UInt8 {
    rawValue.ChunkShift
  }

  /// The number of clusters shifted by compression.
  ///
  /// The corresponding C member is `ClusterShift`.
  @_alwaysEmitIntoClient
  public var clusterShift: UInt8 {
    rawValue.ClusterShift
  }
}

// MARK: - FileCaseSensitiveInfo

/// The per-directory case-sensitivity state of a directory.
///
/// This is a Swift wrapper of the C `FILE_CASE_SENSITIVE_INFO` struct,
/// retrieved by ``FileDescriptor/fileInformation(_:)``. It requires a
/// directory handle.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileCaseSensitiveInfo: RawRepresentable, Sendable {
  /// The raw C `FILE_CASE_SENSITIVE_INFO` struct.
  @_alwaysEmitIntoClient
  public var rawValue: FILE_CASE_SENSITIVE_INFO

  /// Creates a Swift `FileCaseSensitiveInfo` from the raw C struct.
  @_alwaysEmitIntoClient
  public init(rawValue: FILE_CASE_SENSITIVE_INFO) { self.rawValue = rawValue }

  /// The case-sensitivity flags.
  ///
  /// The corresponding C member is `Flags`.
  @_alwaysEmitIntoClient
  public var flags: Flags {
    Flags(rawValue: rawValue.Flags)
  }

  /// Whether name lookup in the directory is case-sensitive. Directories are
  /// case-insensitive by default.
  @_alwaysEmitIntoClient
  public var isCaseSensitive: Bool {
    flags.contains(.caseSensitiveDirectory)
  }

  /// Case-sensitivity flags for a ``FileCaseSensitiveInfo`` value.
  @frozen
  public struct Flags: OptionSet, Sendable, Hashable, Codable {
    /// The raw C bitmask.
    @_alwaysEmitIntoClient
    public var rawValue: UInt32

    /// Creates case-sensitivity flags from a raw C bitmask.
    @_alwaysEmitIntoClient
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The directory is case-sensitive.
    ///
    /// The corresponding C constant is `FILE_CS_FLAG_CASE_SENSITIVE_DIR`.
    @_alwaysEmitIntoClient
    public static var caseSensitiveDirectory: Flags { Flags(rawValue: 0x0000_0001) }
  }
}

#endif // os(Windows)
