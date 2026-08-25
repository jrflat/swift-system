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

// MARK: - FileDirectoryEntry

/// One entry of a directory listing.
///
/// Windows offers three directory-enumeration information classes that differ in
/// what they report and what they cost, each with its own conforming type:
///
/// | Type                             | Adds                           |
/// | -------------------------------- | ------------------------------ |
/// | ``FileFullDirectoryEntry``       | nothing; the cheapest to fetch |
/// | ``FileIDBothDirectoryEntry``     | a 64-bit ID and the 8.3 name   |
/// | ``FileIDExtendedDirectoryEntry`` | a 128-bit ID and a reparse tag |
///
/// This protocol holds the members all three share. The type requested from
/// ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)`` selects the class
/// that is fetched, so code that only needs the common members can be written
/// against this protocol and stay agnostic:
///
///     func names<Entry: FileDirectoryEntry>(
///       of directory: FileDescriptor, as: Entry.Type
///     ) throws -> [FilePath.Component] {
///       try directory.withDirectoryEntries(Entry.self) { entries in
///         var result: [FilePath.Component] = []
///         while let entry = try entries.next() { result.append(entry.name) }
///         return result
///       }
///     }
///
/// - Note: Only available on Windows.
@available(System 99, *)
public protocol FileDirectoryEntry: Sendable {
  /// The info class that resumes an enumeration of this entry type.
  static var infoClass: FileInfoClass { get }

  /// The info class that restarts an enumeration of this entry type from the
  /// first entry.
  static var restartInfoClass: FileInfoClass { get }

  /// The name of the entry, relative to the directory being enumerated.
  ///
  /// A listing includes the `.` and `..` entries; check
  /// ``FilePath/Component/kind`` to tell them from a regular name.
  ///
  /// The corresponding C member is `FileName`.
  var name: FilePath.Component { get }

  /// The byte offset of the entry within its directory, or `0` if the file
  /// system does not report one.
  ///
  /// The corresponding C member is `FileIndex`.
  var fileIndex: UInt32 { get }

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  var attributes: FileAttributes { get }

  /// The logical size of the file, in bytes.
  ///
  /// The corresponding C member is `EndOfFile`.
  var size: Int64 { get }

  /// The number of bytes allocated for the file on disk.
  ///
  /// The corresponding C member is `AllocationSize`.
  var allocationSize: Int64 { get }

  /// The time the file was created.
  ///
  /// The corresponding C member is `CreationTime`.
  var creationTime: FileTime { get }

  /// The time the file was last accessed.
  ///
  /// The corresponding C member is `LastAccessTime`.
  var lastAccessTime: FileTime { get }

  /// The time the file's data stream was last written to.
  ///
  /// The corresponding C member is `LastWriteTime`.
  var lastWriteTime: FileTime { get }

  /// The time the file's metadata was last changed.
  ///
  /// The corresponding C member is `ChangeTime`.
  var changeTime: FileTime { get }

  /// The size of the file's extended attributes, in bytes.
  ///
  /// The corresponding C member is `EaSize`.
  var extendedAttributesSize: UInt32 { get }

  /// The size of the C struct's fixed part, up to its flexible name array.
  ///
  /// - Warning: An implementation detail of decoding, public only so that
  ///   ``DirectoryEntries`` can be generic over this protocol. Do not call it.
  static var _headerSize: Int { get }

  /// Decodes one record of this entry's info class.
  ///
  /// Returns `nil` if the record does not describe a representable entry, which
  /// ``DirectoryEntries/next()`` reports as ``Errno/illegalByteSequence``.
  ///
  /// - Warning: An implementation detail of decoding, public only so that
  ///   ``DirectoryEntries`` can be generic over this protocol. Do not call it.
  init?(_rawDirectoryEntry record: UnsafeRawBufferPointer)
}

@available(System 99, *)
extension FileDirectoryEntry {
  /// The smallest buffer that is guaranteed to hold any single entry.
  ///
  /// ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)`` floors its buffer
  /// at this size. A smaller one risks an entry that cannot be delivered at all:
  /// Windows answers a buffer too small for even one record with
  /// `ERROR_MORE_DATA` rather than a partial record.
  @_alwaysEmitIntoClient
  public static var minimumBufferSize: Int {
    // A record is its fixed part plus a name, and Windows bounds a name at
    // 32767 UTF-16 code units. The trailing slack covers the padding the file
    // system inserts to keep each record 8-byte aligned.
    _headerSize + 32767 * MemoryLayout<WCHAR>.stride + 8
  }

  /// Whether the entry is one of the `.` or `..` directory entries.
  ///
  /// Windows includes both in every directory listing.
  @_alwaysEmitIntoClient
  public var isSpecialDirectoryEntry: Bool {
    name.kind != .regular
  }

  /// Whether the entry is a directory.
  @_alwaysEmitIntoClient
  public var isDirectory: Bool {
    attributes.contains(.directory)
  }
}

// MARK: - FileFullDirectoryEntry

/// A directory entry reporting only the members common to every enumeration
/// class.
///
/// This is the decoded form of a C `FILE_FULL_DIR_INFO` record. It is the
/// cheapest of the three entry types to retrieve, because the file system can
/// answer it from the directory entry alone without also consulting the master
/// file table. Prefer it unless you need a file identifier or reparse tag.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileFullDirectoryEntry: Sendable {
  /// The name of the entry, relative to the directory being enumerated.
  ///
  /// The corresponding C member is `FileName`.
  public var name: FilePath.Component

  /// The byte offset of the entry within its directory, or `0` if the file
  /// system does not report one.
  ///
  /// The corresponding C member is `FileIndex`.
  public var fileIndex: UInt32

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  public var attributes: FileAttributes

  /// The logical size of the file, in bytes.
  ///
  /// The corresponding C member is `EndOfFile`.
  public var size: Int64

  /// The number of bytes allocated for the file on disk.
  ///
  /// The corresponding C member is `AllocationSize`.
  public var allocationSize: Int64

  /// The time the file was created.
  ///
  /// The corresponding C member is `CreationTime`.
  public var creationTime: FileTime

  /// The time the file was last accessed.
  ///
  /// The corresponding C member is `LastAccessTime`.
  public var lastAccessTime: FileTime

  /// The time the file's data stream was last written to.
  ///
  /// The corresponding C member is `LastWriteTime`.
  public var lastWriteTime: FileTime

  /// The time the file's metadata was last changed.
  ///
  /// The corresponding C member is `ChangeTime`.
  public var changeTime: FileTime

  /// The size of the file's extended attributes, in bytes.
  ///
  /// The corresponding C member is `EaSize`.
  public var extendedAttributesSize: UInt32
}

@available(System 99, *)
extension FileFullDirectoryEntry: FileDirectoryEntry {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .fullDirectory }

  @_alwaysEmitIntoClient
  public static var restartInfoClass: FileInfoClass { .fullDirectoryRestart }

  @_alwaysEmitIntoClient
  public static var _headerSize: Int {
    MemoryLayout<FILE_FULL_DIR_INFO>.offset(of: \.FileName)!
  }

  @_alwaysEmitIntoClient
  public init?(_rawDirectoryEntry record: UnsafeRawBufferPointer) {
    guard let entry = _decodeFullDirectoryEntry(record) else { return nil }
    self = entry
  }
}

// MARK: - FileIDBothDirectoryEntry

/// A directory entry that also reports a 64-bit file identifier and the file's
/// 8.3 short name.
///
/// This is the decoded form of a C `FILE_ID_BOTH_DIR_INFO` record. Retrieving it
/// costs more than ``FileFullDirectoryEntry``, because the identifier requires a
/// master file table lookup per entry.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileIDBothDirectoryEntry: Sendable {
  /// The name of the entry, relative to the directory being enumerated.
  ///
  /// The corresponding C member is `FileName`.
  public var name: FilePath.Component

  /// The byte offset of the entry within its directory, or `0` if the file
  /// system does not report one.
  ///
  /// The corresponding C member is `FileIndex`.
  public var fileIndex: UInt32

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  public var attributes: FileAttributes

  /// The logical size of the file, in bytes.
  ///
  /// The corresponding C member is `EndOfFile`.
  public var size: Int64

  /// The number of bytes allocated for the file on disk.
  ///
  /// The corresponding C member is `AllocationSize`.
  public var allocationSize: Int64

  /// The time the file was created.
  ///
  /// The corresponding C member is `CreationTime`.
  public var creationTime: FileTime

  /// The time the file was last accessed.
  ///
  /// The corresponding C member is `LastAccessTime`.
  public var lastAccessTime: FileTime

  /// The time the file's data stream was last written to.
  ///
  /// The corresponding C member is `LastWriteTime`.
  public var lastWriteTime: FileTime

  /// The time the file's metadata was last changed.
  ///
  /// The corresponding C member is `ChangeTime`.
  public var changeTime: FileTime

  /// The size of the file's extended attributes, in bytes.
  ///
  /// The corresponding C member is `EaSize`.
  public var extendedAttributesSize: UInt32

  /// The file's 64-bit identifier.
  ///
  /// This is the identifier reported by `GetFileInformationByHandle`, and is not
  /// guaranteed to be unique on ReFS. Enumerate as
  /// ``FileIDExtendedDirectoryEntry`` for the 128-bit identifier that is.
  ///
  /// The corresponding C member is `FileId`.
  public var fileID: Int64

  /// The file's 8.3 short name, or `nil` if it has none.
  ///
  /// Short-name generation can be disabled per volume, in which case the file
  /// system reports no short name for files created while it was off.
  ///
  /// The corresponding C member is `ShortName`.
  public var shortName: String?
}

@available(System 99, *)
extension FileIDBothDirectoryEntry: FileDirectoryEntry {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .idBothDirectory }

  @_alwaysEmitIntoClient
  public static var restartInfoClass: FileInfoClass { .idBothDirectoryRestart }

  @_alwaysEmitIntoClient
  public static var _headerSize: Int {
    MemoryLayout<FILE_ID_BOTH_DIR_INFO>.offset(of: \.FileName)!
  }

  @_alwaysEmitIntoClient
  public init?(_rawDirectoryEntry record: UnsafeRawBufferPointer) {
    guard let entry = _decodeIDBothDirectoryEntry(record) else { return nil }
    self = entry
  }
}

// MARK: - FileIDExtendedDirectoryEntry

/// A directory entry that also reports a 128-bit file identifier and a reparse
/// tag.
///
/// This is the decoded form of a C `FILE_ID_EXTD_DIR_INFO` record. Its 128-bit
/// identifier is unique on every Windows file system, including ReFS, where the
/// 64-bit identifier of ``FileIDBothDirectoryEntry`` is not.
///
/// - Note: Only available on Windows.
@frozen
@available(System 99, *)
public struct FileIDExtendedDirectoryEntry: Sendable {
  /// The name of the entry, relative to the directory being enumerated.
  ///
  /// The corresponding C member is `FileName`.
  public var name: FilePath.Component

  /// The byte offset of the entry within its directory, or `0` if the file
  /// system does not report one.
  ///
  /// The corresponding C member is `FileIndex`.
  public var fileIndex: UInt32

  /// The file's attributes.
  ///
  /// The corresponding C member is `FileAttributes`.
  public var attributes: FileAttributes

  /// The logical size of the file, in bytes.
  ///
  /// The corresponding C member is `EndOfFile`.
  public var size: Int64

  /// The number of bytes allocated for the file on disk.
  ///
  /// The corresponding C member is `AllocationSize`.
  public var allocationSize: Int64

  /// The time the file was created.
  ///
  /// The corresponding C member is `CreationTime`.
  public var creationTime: FileTime

  /// The time the file was last accessed.
  ///
  /// The corresponding C member is `LastAccessTime`.
  public var lastAccessTime: FileTime

  /// The time the file's data stream was last written to.
  ///
  /// The corresponding C member is `LastWriteTime`.
  public var lastWriteTime: FileTime

  /// The time the file's metadata was last changed.
  ///
  /// The corresponding C member is `ChangeTime`.
  public var changeTime: FileTime

  /// The size of the file's extended attributes, in bytes.
  ///
  /// The corresponding C member is `EaSize`.
  public var extendedAttributesSize: UInt32

  /// The file's 128-bit identifier.
  ///
  /// Combined with the volume serial number from ``FileIDInfo``, this uniquely
  /// identifies the file. See ``FileIDInfo/fileID`` for the caveats on treating
  /// an identifier as stable over time.
  ///
  /// The corresponding C member is `FileId`.
  public var fileID: FileID128

  /// The reparse tag, or `nil` if the entry is not a reparse point.
  ///
  /// The corresponding C member is `ReparsePointTag`, which is undefined unless
  /// ``attributes`` contains ``FileAttributes/reparsePoint``.
  public var reparseTag: ReparseTag?
}

@available(System 99, *)
extension FileIDExtendedDirectoryEntry: FileDirectoryEntry {
  @_alwaysEmitIntoClient
  public static var infoClass: FileInfoClass { .idExtendedDirectory }

  @_alwaysEmitIntoClient
  public static var restartInfoClass: FileInfoClass {
    .idExtendedDirectoryRestart
  }

  @_alwaysEmitIntoClient
  public static var _headerSize: Int {
    MemoryLayout<FILE_ID_EXTD_DIR_INFO>.offset(of: \.FileName)!
  }

  @_alwaysEmitIntoClient
  public init?(_rawDirectoryEntry record: UnsafeRawBufferPointer) {
    guard let entry = _decodeIDExtendedDirectoryEntry(record) else { return nil }
    self = entry
  }
}

// MARK: - DirectoryEntries

/// A cursor over the entries of a directory.
///
/// Obtained from ``FileDescriptor/withDirectoryEntries(_:bufferSize:_:)`` and
/// advanced with ``next()`` until it returns `nil`:
///
///     try directory.withDirectoryEntries(FileFullDirectoryEntry.self) { entries in
///       while let entry = try entries.next() {
///         guard !entry.isSpecialDirectoryEntry else { continue }
///         print(entry.name, entry.size)
///       }
///     }
///
/// Windows delivers entries a batch at a time, from a cursor it keeps in the
/// open handle rather than in this value. That has two consequences the type is
/// shaped around:
///
/// - It is non-copyable. Two copies would share the one kernel cursor, so each
///   would silently consume entries the other expected to see.
/// - It is scoped to the closure it is passed to, which owns the buffer the
///   entries are decoded from.
///
/// Because the cursor belongs to the handle, enumerating the same descriptor
/// twice at once (e.g. from two nested calls, or from two threads) interleaves the
/// two listings. Open a second descriptor instead.
///
/// - Note: Only available on Windows.
@available(System 99, *)
public struct DirectoryEntries<Entry: FileDirectoryEntry>: ~Copyable {
  @usableFromInline
  internal let _descriptor: FileDescriptor

  /// The batch buffer. Borrowed from the enclosing `withDirectoryEntries` call,
  /// which allocates and frees it; this type does not own it.
  @usableFromInline
  internal let _buffer: UnsafeMutableRawBufferPointer

  /// Offset of the next undecoded record in `_buffer`, or `nil` when the
  /// current batch is spent and a refill is due.
  @usableFromInline
  internal var _offset: Int?

  /// Whether the next refill should restart the enumeration rather than resume
  /// it. Set for the first refill, so a freshly made cursor always begins at the
  /// first entry no matter what the handle's cursor was left pointing at.
  @usableFromInline
  internal var _restarting: Bool

  /// Whether the enumeration has ended, either normally or through an error.
  @usableFromInline
  internal var _exhausted: Bool

  @usableFromInline
  internal init(
    descriptor: FileDescriptor, buffer: UnsafeMutableRawBufferPointer
  ) {
    self._descriptor = descriptor
    self._buffer = buffer
    self._offset = nil
    self._restarting = true
    self._exhausted = false
  }

  /// Returns the next entry, or `nil` once the directory has been fully
  /// enumerated.
  ///
  /// - Throws: ``Errno`` if the file system fails while producing a batch, or
  ///   ``Errno/illegalByteSequence`` if it reports a name that is not a single
  ///   path component. Reaching the end of the directory is not an error.
  ///
  /// After a throw the cursor is spent: a further call returns `nil` rather than
  /// failing again. Call ``restart()`` to enumerate from the beginning.
  @_alwaysEmitIntoClient
  public mutating func next() throws(Errno) -> Entry? {
    try _next().get()
  }

  @usableFromInline
  internal mutating func _next() -> Result<Entry?, Errno> {
    while true {
      guard let offset = _offset else {
        if _exhausted { return .success(nil) }
        if let error = _refill() { return .failure(error) }
        continue
      }
      guard let record = _fileInformationEntry(
        in: UnsafeRawBufferPointer(_buffer),
        at: offset,
        headerSize: Entry._headerSize
      ) else {
        // No whole record at this offset. A batch that ends normally arrives
        // here with `_offset` already `nil` — its last record reports a next
        // offset of zero — so reaching this point means the batch could not be
        // parsed at all. Ending the enumeration is what keeps a refill that
        // cannot make progress from looping forever.
        _offset = nil
        _exhausted = true
        continue
      }
      _offset = record.nextOffset
      guard let entry = Entry(_rawDirectoryEntry: record.bytes) else {
        return .failure(Errno.illegalByteSequence)
      }
      return .success(entry)
    }
  }

  /// Fetches the next batch of entries into `_buffer`.
  ///
  /// - Returns: The error to report, or `nil` if the batch was fetched or the
  ///   enumeration ended normally.
  @usableFromInline
  internal mutating func _refill() -> Errno? {
    // The first fetch restarts, every later one resumes. Folding the two
    // classes into one cursor is what keeps a caller from having to know that
    // the plain class picks up wherever the handle was left.
    let infoClass = _restarting
      ? Entry.restartInfoClass.rawValue
      : Entry.infoClass.rawValue
    _restarting = false

    // Zero first: Windows reports neither how many bytes it wrote nor where the
    // chain ends, so this is what keeps a malformed `NextEntryOffset` landing on
    // zeroes — which terminates the walk — rather than on the previous batch.
    _buffer.initializeMemory(as: UInt8.self, repeating: 0)

    let error = system_getFileInformationByHandleEx_error(
      _descriptor.rawValue, infoClass, _buffer)

    if error == ERROR_SUCCESS {
      _offset = 0
      return nil
    }

    // Every later call is a no-op, whether the enumeration ended or failed.
    _exhausted = true
    _offset = nil

    // Windows signals a finished enumeration with a failure code. Neither of
    // these is an error, and neither can be told apart from a real one after
    // mapping — `ERROR_NO_MORE_FILES` becomes `ENOENT` and `ERROR_HANDLE_EOF`
    // becomes `EINVAL` — which is why the raw code is checked here instead.
    if error == ERROR_NO_MORE_FILES || error == ERROR_HANDLE_EOF { return nil }
    return Errno(windowsError: error)
  }

  /// Restarts the enumeration, so the next call to ``next()`` returns the
  /// directory's first entry.
  ///
  /// The corresponding C information classes are the `…RestartInfo` ones.
  @_alwaysEmitIntoClient
  public mutating func restart() {
    _offset = nil
    _restarting = true
    _exhausted = false
  }
}

// MARK: - FileDescriptor API

@available(System 99, *)
extension FileDescriptor {
  /// Enumerates the entries of the directory referred to by this descriptor.
  ///
  /// The requested entry type determines the information class that is fetched,
  /// and so what each entry reports and what it costs to produce:
  ///
  ///     let sizes = try directory.withDirectoryEntries(
  ///       FileFullDirectoryEntry.self
  ///     ) { entries in
  ///       var total: Int64 = 0
  ///       while let entry = try entries.next() {
  ///         if !entry.isDirectory { total += entry.size }
  ///       }
  ///       return total
  ///     }
  ///
  /// - Parameters:
  ///   - type: The entry type to decode, which selects the information class.
  ///   - bufferSize: The size of the batch buffer, in bytes. A larger buffer
  ///     yields more entries per system call. Values below
  ///     ``FileDirectoryEntry/minimumBufferSize`` are raised to it, so that a
  ///     maximum-length name can always be delivered.
  ///   - body: Receives the cursor. The cursor and the storage its entries were
  ///     decoded from are valid only for the duration of the call; the entries
  ///     themselves own their contents and may be kept.
  /// - Returns: Whatever `body` returns.
  ///
  /// - Precondition: This descriptor must refer to a directory opened with
  ///   ``FileDescriptor/OpenOptions`` directory support.
  ///
  /// Windows reports a listing as `.` and `..` followed by the directory's own
  /// entries, in no guaranteed order. Check
  /// ``FileDirectoryEntry/isSpecialDirectoryEntry`` to skip the first two.
  ///
  /// The corresponding C function is `GetFileInformationByHandleEx` with one of
  /// the directory information classes.
  @_alwaysEmitIntoClient
  public func withDirectoryEntries<Entry: FileDirectoryEntry, R, E: Error>(
    _ type: Entry.Type = Entry.self,
    bufferSize: Int = 128 << 10,
    _ body: (inout DirectoryEntries<Entry>) throws(E) -> R
  ) throws(E) -> R {
    // The chained structs place 8-byte members at fixed offsets, so the buffer
    // has to be 8-byte aligned for the file system to fill it.
    let capacity = Swift.max(bufferSize, Entry.minimumBufferSize)
    let buffer = UnsafeMutableRawBufferPointer.allocate(
      byteCount: capacity, alignment: 8)
    defer { buffer.deallocate() }

    var entries = DirectoryEntries<Entry>(
      descriptor: self, buffer: buffer)
    return try body(&entries)
  }
}

// MARK: - Decoding

/// The members every directory-entry class shares.
@available(System 99, *)
internal struct _CommonDirectoryFields {
  var name: FilePath.Component
  var fileIndex: UInt32
  var attributes: FileAttributes
  var size: Int64
  var allocationSize: Int64
  var creationTime: FileTime
  var lastAccessTime: FileTime
  var lastWriteTime: FileTime
  var changeTime: FileTime
  var extendedAttributesSize: UInt32
}

/// Where each shared member sits within one of the three C structs.
///
/// The three happen to agree on every offset here, but each type derives its own
/// from its own key paths rather than relying on that.
@available(System 99, *)
internal struct _DirectoryFieldOffsets {
  var fileIndex: Int
  var creationTime: Int
  var lastAccessTime: Int
  var lastWriteTime: Int
  var changeTime: Int
  var endOfFile: Int
  var allocationSize: Int
  var fileAttributes: Int
  var fileNameLength: Int
  var eaSize: Int
  var fileName: Int
}

/// Decodes the shared members of one directory record.
///
/// - Returns: `nil` if `FileName` does not spell a single path component, which
///   the file system should never report but is not prevented from reporting.
@available(System 99, *)
internal func _decodeCommonDirectoryFields(
  _ record: UnsafeRawBufferPointer, _ offsets: _DirectoryFieldOffsets
) -> _CommonDirectoryFields? {
  guard let base = record.baseAddress else { return nil }

  let reportedLength = Int(
    record.loadUnaligned(fromByteOffset: offsets.fileNameLength, as: DWORD.self))
  let nameLength = _clampedWideLength(
    in: record, offset: offsets.fileName, byteCount: reportedLength)
  guard let name = _decodeWideComponent(
    base: base.advanced(by: offsets.fileName), byteCount: nameLength)
  else { return nil }

  // `LARGE_INTEGER` is a union whose `QuadPart` is a 64-bit integer at offset
  // zero, so every one of these members is read directly as `Int64`.
  return _CommonDirectoryFields(
    name: name,
    fileIndex: record.loadUnaligned(
      fromByteOffset: offsets.fileIndex, as: DWORD.self),
    attributes: FileAttributes(rawValue: record.loadUnaligned(
      fromByteOffset: offsets.fileAttributes, as: DWORD.self)),
    size: record.loadUnaligned(
      fromByteOffset: offsets.endOfFile, as: Int64.self),
    allocationSize: record.loadUnaligned(
      fromByteOffset: offsets.allocationSize, as: Int64.self),
    creationTime: FileTime(rawValue: record.loadUnaligned(
      fromByteOffset: offsets.creationTime, as: Int64.self)),
    lastAccessTime: FileTime(rawValue: record.loadUnaligned(
      fromByteOffset: offsets.lastAccessTime, as: Int64.self)),
    lastWriteTime: FileTime(rawValue: record.loadUnaligned(
      fromByteOffset: offsets.lastWriteTime, as: Int64.self)),
    changeTime: FileTime(rawValue: record.loadUnaligned(
      fromByteOffset: offsets.changeTime, as: Int64.self)),
    extendedAttributesSize: record.loadUnaligned(
      fromByteOffset: offsets.eaSize, as: DWORD.self))
}

@available(System 99, *)
@usableFromInline
internal func _decodeFullDirectoryEntry(
  _ record: UnsafeRawBufferPointer
) -> FileFullDirectoryEntry? {
  typealias Raw = FILE_FULL_DIR_INFO
  let offsets = _DirectoryFieldOffsets(
    fileIndex: MemoryLayout<Raw>.offset(of: \.FileIndex)!,
    creationTime: MemoryLayout<Raw>.offset(of: \.CreationTime)!,
    lastAccessTime: MemoryLayout<Raw>.offset(of: \.LastAccessTime)!,
    lastWriteTime: MemoryLayout<Raw>.offset(of: \.LastWriteTime)!,
    changeTime: MemoryLayout<Raw>.offset(of: \.ChangeTime)!,
    endOfFile: MemoryLayout<Raw>.offset(of: \.EndOfFile)!,
    allocationSize: MemoryLayout<Raw>.offset(of: \.AllocationSize)!,
    fileAttributes: MemoryLayout<Raw>.offset(of: \.FileAttributes)!,
    fileNameLength: MemoryLayout<Raw>.offset(of: \.FileNameLength)!,
    eaSize: MemoryLayout<Raw>.offset(of: \.EaSize)!,
    fileName: MemoryLayout<Raw>.offset(of: \.FileName)!)

  guard let common = _decodeCommonDirectoryFields(record, offsets) else {
    return nil
  }
  return FileFullDirectoryEntry(
    name: common.name,
    fileIndex: common.fileIndex,
    attributes: common.attributes,
    size: common.size,
    allocationSize: common.allocationSize,
    creationTime: common.creationTime,
    lastAccessTime: common.lastAccessTime,
    lastWriteTime: common.lastWriteTime,
    changeTime: common.changeTime,
    extendedAttributesSize: common.extendedAttributesSize)
}

@available(System 99, *)
@usableFromInline
internal func _decodeIDBothDirectoryEntry(
  _ record: UnsafeRawBufferPointer
) -> FileIDBothDirectoryEntry? {
  typealias Raw = FILE_ID_BOTH_DIR_INFO
  let offsets = _DirectoryFieldOffsets(
    fileIndex: MemoryLayout<Raw>.offset(of: \.FileIndex)!,
    creationTime: MemoryLayout<Raw>.offset(of: \.CreationTime)!,
    lastAccessTime: MemoryLayout<Raw>.offset(of: \.LastAccessTime)!,
    lastWriteTime: MemoryLayout<Raw>.offset(of: \.LastWriteTime)!,
    changeTime: MemoryLayout<Raw>.offset(of: \.ChangeTime)!,
    endOfFile: MemoryLayout<Raw>.offset(of: \.EndOfFile)!,
    allocationSize: MemoryLayout<Raw>.offset(of: \.AllocationSize)!,
    fileAttributes: MemoryLayout<Raw>.offset(of: \.FileAttributes)!,
    fileNameLength: MemoryLayout<Raw>.offset(of: \.FileNameLength)!,
    eaSize: MemoryLayout<Raw>.offset(of: \.EaSize)!,
    fileName: MemoryLayout<Raw>.offset(of: \.FileName)!)

  guard let base = record.baseAddress,
        let common = _decodeCommonDirectoryFields(record, offsets)
  else { return nil }

  let shortNameOffset = MemoryLayout<Raw>.offset(of: \.ShortName)!
  // `ShortName` is a fixed `WCHAR[12]`, so it bounds itself; the reported
  // length is clamped to it as well as to the record. Windows documents the
  // length in bytes and NUL-pads the remainder, and `_decodeWideString` stops
  // at the first NUL, so a file system that reports code units instead still
  // decodes correctly.
  let shortNameCapacity = 12 * MemoryLayout<WCHAR>.stride
  // `CCHAR` is a signed `char`; a negative length clamps to zero below.
  let reportedShortLength = Int(
    record.loadUnaligned(
      fromByteOffset: MemoryLayout<Raw>.offset(of: \.ShortNameLength)!,
      as: CChar.self))
  let shortNameLength = _clampedWideLength(
    in: record,
    offset: shortNameOffset,
    byteCount: Swift.min(reportedShortLength, shortNameCapacity))
  let shortName = _decodeWideString(
    base: base.advanced(by: shortNameOffset), byteCount: shortNameLength)

  return FileIDBothDirectoryEntry(
    name: common.name,
    fileIndex: common.fileIndex,
    attributes: common.attributes,
    size: common.size,
    allocationSize: common.allocationSize,
    creationTime: common.creationTime,
    lastAccessTime: common.lastAccessTime,
    lastWriteTime: common.lastWriteTime,
    changeTime: common.changeTime,
    extendedAttributesSize: common.extendedAttributesSize,
    fileID: record.loadUnaligned(
      fromByteOffset: MemoryLayout<Raw>.offset(of: \.FileId)!, as: Int64.self),
    shortName: shortName.isEmpty ? nil : shortName)
}

@available(System 99, *)
@usableFromInline
internal func _decodeIDExtendedDirectoryEntry(
  _ record: UnsafeRawBufferPointer
) -> FileIDExtendedDirectoryEntry? {
  typealias Raw = FILE_ID_EXTD_DIR_INFO
  let offsets = _DirectoryFieldOffsets(
    fileIndex: MemoryLayout<Raw>.offset(of: \.FileIndex)!,
    creationTime: MemoryLayout<Raw>.offset(of: \.CreationTime)!,
    lastAccessTime: MemoryLayout<Raw>.offset(of: \.LastAccessTime)!,
    lastWriteTime: MemoryLayout<Raw>.offset(of: \.LastWriteTime)!,
    changeTime: MemoryLayout<Raw>.offset(of: \.ChangeTime)!,
    endOfFile: MemoryLayout<Raw>.offset(of: \.EndOfFile)!,
    allocationSize: MemoryLayout<Raw>.offset(of: \.AllocationSize)!,
    fileAttributes: MemoryLayout<Raw>.offset(of: \.FileAttributes)!,
    fileNameLength: MemoryLayout<Raw>.offset(of: \.FileNameLength)!,
    eaSize: MemoryLayout<Raw>.offset(of: \.EaSize)!,
    fileName: MemoryLayout<Raw>.offset(of: \.FileName)!)

  guard let common = _decodeCommonDirectoryFields(record, offsets) else {
    return nil
  }

  let tag = record.loadUnaligned(
    fromByteOffset: MemoryLayout<Raw>.offset(of: \.ReparsePointTag)!,
    as: DWORD.self)

  // Copied byte by byte rather than loaded as a `FILE_ID_128`, matching
  // `FileID128`'s own decoding. The identifier lies inside the fixed part, so
  // the record is known to be long enough to hold it.
  var identifier = FILE_ID_128()
  let idOffset = MemoryLayout<Raw>.offset(of: \.FileId)!
  withUnsafeMutableBytes(of: &identifier) { destination in
    destination.copyMemory(from: UnsafeRawBufferPointer(
      rebasing: record[idOffset ..< idOffset + destination.count]))
  }

  return FileIDExtendedDirectoryEntry(
    name: common.name,
    fileIndex: common.fileIndex,
    attributes: common.attributes,
    size: common.size,
    allocationSize: common.allocationSize,
    creationTime: common.creationTime,
    lastAccessTime: common.lastAccessTime,
    lastWriteTime: common.lastWriteTime,
    changeTime: common.changeTime,
    extendedAttributesSize: common.extendedAttributesSize,
    fileID: FileID128(rawValue: identifier),
    // The tag is only defined for a reparse point, matching
    // `FileAttributeTagInfo.reparseTag`.
    reparseTag: common.attributes.contains(.reparsePoint)
      ? ReparseTag(rawValue: tag)
      : nil)
}

#endif // os(Windows)
