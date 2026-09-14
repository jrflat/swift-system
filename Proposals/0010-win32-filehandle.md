# `Win32.FileHandle` for Swift System

* Proposal: [SYS-0010](0010-win32-filehandle.md)
* Author: [Jonathan Flat](https://github.com/jrflat)
* Review Manager: TBD
* Status: **Draft**
* Implementation: TBD
* Review: TBD
* Depends on: [SYS-0009](0009-win32-namespace-and-error.md)

#### Revision history

* **v1** Initial version.

## Introduction

This proposal adds `Win32.FileHandle` and `Win32.DirectoryHandle`, noncopyable wrappers over the Windows `HANDLE`, along with opening, closing, duplication, inheritance control, and bridges to and from `FileDescriptor`. It builds on the `Win32` namespace and `Win32.Error` introduced in [SYS-0009](0009-win32-namespace-and-error.md).

## Motivation

A `HANDLE` is Windows' canonical representation of an open file, and wrapping it would let System model that object directly. This type would express the full capabilities of `CreateFileW`, name operations that exist only for a `HANDLE`, and document Win32 semantics accurately.

System provides `FileDescriptor` today, but it doesn't remove the need for `HANDLE`-specific APIs. `FileDescriptor` is a POSIX abstraction, and on Windows it's a C runtime file descriptor layered over the handle. System's Windows adapters recover the handle with `_get_osfhandle` when necessary. That works for a POSIX shim, but it has several consequences:

### Directories can't be opened

`CreateFileW` returns a handle to a directory only if it's passed `FILE_FLAG_BACKUP_SEMANTICS`. Without that flag, the call fails. `OpenOptions` doesn't support it, and System's `open` adapter never sets the flag.

So `FileDescriptor.open(someDirectory, .readOnly)` succeeds on Linux and Darwin but fails on Windows, and no option a caller can pass changes that. Every Windows API that takes a directory handle, including enumeration, change notification, and per-directory case sensitivity, is unreachable from System today.

### `OpenOptions` supports a fraction of `CreateFileW`

System's `open` adapter calls `CreateFileW`, wraps the result with `_open_osfhandle`, and hardcodes `FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE` on every open. That default is correct for making System on Windows behave like POSIX when an open file is deleted or renamed, but it isn't configurable. A caller can't request exclusive access, which on Windows is the only mechanism for mandatory sharing control and has no POSIX `open` equivalent.

The rest of the mapping is similarly narrow. The adapter maps `_O_CREAT`, `_O_EXCL`, and `_O_TRUNC` onto a creation disposition, maps the access mode onto `GENERIC_READ` and `GENERIC_WRITE`, and passes through `_O_NOINHERIT`, `_O_SEQUENTIAL`, `_O_RANDOM`, `_O_TEMPORARY`, and `_O_SHORT_LIVED`. Since `OpenOptions` is limited to its `CInt` of `oflag` bits, that is the entire surface. It has no way to express:

* Handle flags such as `FILE_FLAG_BACKUP_SEMANTICS`, `FILE_FLAG_OVERLAPPED`, `FILE_FLAG_NO_BUFFERING`, `FILE_FLAG_WRITE_THROUGH`, `FILE_FLAG_OPEN_REPARSE_POINT`, and `FILE_FLAG_POSIX_SEMANTICS`.
* A security descriptor for a newly created file.
* Fine-grained access rights, such as `FILE_READ_ATTRIBUTES`, which opens a file for metadata access only. Those opens can succeed in cases where a read open would be denied.

### The descriptor is not the object

A C runtime descriptor is a second index over the handle and carries state of its own, including a translation mode. In text mode, the runtime rewrites bytes in transit, expanding `\n` to `\r\n` on write and collapsing it on read. Anything built on a descriptor inherits a translation setting that is invisible in System's APIs.

Every Windows-native operation in System also has to convert back to a handle first. Each pays a table lookup, and each needs a failure path for the case where the `CInt` maps to no handle at all. System's adapters report `EBADF` when `_get_osfhandle` returns `INVALID_HANDLE_VALUE`, but those paths rarely run since `_get_osfhandle` on an invalid descriptor terminates the process by default. The `pread`, `pwrite`, and `ftruncate` implementations crash on Windows where Linux and Darwin throw (see **Bridging with `FileDescriptor`**). On a handle-based API, neither the lookup nor the hazard exists.

The conversion also leaks Windows semantics into portable-looking APIs. For example, `FileDescriptor.read(fromAbsoluteOffset:into:)` on Windows calls `_get_osfhandle`, checks the result, then calls `ReadFile` with an `OVERLAPPED` carrying the offset. However, passing an `OVERLAPPED` on a synchronous handle reads from the given offset *and* updates the file pointer, unlike POSIX `pread`. `FileDescriptor` should document that deviation, but a dedicated `Win32` type eliminates the POSIX contradiction entirely. See [SYS-0011](0011-win32-file-io.md).

### Handle lifetime operations have no spelling

`OpenOptions.closeOnExec` maps to `_O_NOINHERIT`, so the adapter does set `bInheritHandle` at creation time, but `DuplicateHandle` and `SetHandleInformation` have no true `FileDescriptor` equivalent. There is no way to duplicate a handle with a chosen access mask or inheritability, and no way to make an already-open handle inheritable before spawning a child process.

### A copied handle is a use-after-close hazard

`FileDescriptor` is a copyable value with a non-consuming `close()`. Copy it, close one copy, and the other still compiles and still names a number. Windows recycles handle values, so a stale copy may name a different kernel object and lead to I/O on the wrong file.

`FileDescriptor` keeps the copyable model because it's shipped ABI on Apple platforms and predates `~Copyable`. Neither constraint applies to new Windows API, so we should pursue an owning, noncopyable type instead. A double close or use after close then becomes a compile error, a dropped handle is closed rather than leaked, and every signature says clearly whether it borrows or consumes.

## Proposed solution

Add `Win32.FileHandle` and `Win32.DirectoryHandle`, `~Copyable` types that own their handle and close it with a `consuming func close()`. Give them a `CreateFileW` wrapper whose parameters model Win32's own argument structure rather than POSIX `oflag` bits.

```swift
#if os(Windows)
// Open a directory. `FILE_FLAG_BACKUP_SEMANTICS` is applied automatically.
// `dir` has no read or write surface, and closes at the end of this scope.
let dir = try Win32.DirectoryHandle.open("C:\\Users\\me\\Documents")

// Ask for exclusive access (no sharing).
let exclusive = try Win32.FileHandle.open(
  path, access: [.genericRead, .genericWrite], shareMode: []
)
try exclusive.close() // Handles may be closed explicitly for error handling.

// Open for metadata only. This succeeds where a read open would be denied.
let meta = try Win32.FileHandle.open(path, access: .readAttributes)
try meta.close()

// Create if absent, and find out if the file already existed.
let log = try Win32.FileHandle.openOrCreate(logPath, access: .genericWrite)
if !log.existed { try writeHeader(to: log.handle) }
try log.handle.close()
#endif
```

## Detailed design

Wrapper constants and functions introduced here are `@_alwaysEmitIntoClient`. All APIs carry the availability of the System release that introduces them. These APIs only support synchronous handles and reject `FILE_FLAG_OVERLAPPED` on open; see **No `.overlapped`**.

### `Win32.FileHandle` and `Win32.DirectoryHandle`

```swift
extension Win32 {
  /// An open file, device, or pipe.
  ///
  /// This type owns its handle. Call ``close()`` to close it and report any
  /// error. Otherwise, `deinit` closes the handle at the end of its scope and
  /// discards the error.
  ///
  /// The corresponding C type is `HANDLE`.
  @frozen @safe
  public struct FileHandle: ~Copyable, Sendable {
    /// Adopts a raw handle, taking ownership of it.
    ///
    /// Returns `nil` if `raw` is `NULL` or `INVALID_HANDLE_VALUE`.
    @unsafe
    public init?(unsafelyAdopting raw: HANDLE?)

    /// The raw C handle. Valid only while this value is alive.
    @unsafe
    public var unsafeRawHandle: HANDLE { get }

    /// Gives up ownership and returns the raw handle.
    ///
    /// The caller becomes responsible for closing it.
    @unsafe
    public consuming func relinquish() -> HANDLE
    
    /// Closes this handle.
    ///
    /// The corresponding C function is `CloseHandle`.
    public consuming func close() throws(Win32.Error)
  }

  /// An open directory.
  ///
  /// Opening one applies `FILE_FLAG_BACKUP_SEMANTICS`. This type has no
  /// read or write surface, because `ReadFile` and `WriteFile` fail on a
  /// directory handle.
  ///
  /// The corresponding C type is `HANDLE`.
  @frozen @safe
  public struct DirectoryHandle: ~Copyable, Sendable {
    @unsafe
    public init?(unsafelyAdopting raw: HANDLE?)

    @unsafe
    public var unsafeRawHandle: HANDLE { get }

    @unsafe
    public consuming func relinquish() -> HANDLE
    
    public consuming func close() throws(Win32.Error)
  }
}
```

#### Lifetime and error handling

A handle is always closed — the only question is whether the caller sees the error. `close()` reports it, and `deinit` discards it at the end of the handle's scope. On a write-through, delete-on-close, or network-backed handle, a close failure reports a real problem. `deinit` still closes to prevent a throw between the open and the close from leaking the handle. `close()` consumes the handle even when it throws because a failed `CloseHandle` leaves nothing safe to retry: the handle may already be invalid, and Windows may have recycled its value for an unrelated object.

Ownership also removes the need for a scoped form like `closeAfter(_:)` or `withOpen`. An ordinary binding plus an explicit close reproduces the contract a `closeAfter` would document:

```swift
let file = try Win32.FileHandle.open(path, access: .genericRead)
try doWork(file)    // If this throws, `deinit` closes and discards the error.
try file.close()    // Otherwise, any close error is reported here.
```

`unsafeRawHandle` and `relinquish()` are `@unsafe` escape hatches from that model. `unsafeRawHandle` may be used with Win32 functions that borrow a handle and have no System wrapper yet, and `relinquish()` hands ownership to code that will close it.

#### Two invalid sentinels

`CreateFileW` reports failure as `INVALID_HANDLE_VALUE` (`(HANDLE)-1`), while most other handle-producing functions report failure as `NULL`. `init?(unsafelyAdopting:)` is failable so that both are rejected in one place. A non-nil `FileHandle` means a valid `HANDLE`. There is no `.invalid` member, since both sentinels report only that the call failed, and `.invalid` would name a handle on which every operation fails. The parameter is `HANDLE?` to support Win32 functions that return `NULL` but import as returning `HANDLE!`.

> Note: The C runtime has a third sentinel, `_NO_CONSOLE_FILENO` (`(intptr_t)-2`). This is a CRT convention rather than a Win32 one, so it's filtered by ``FileDescriptor/withWin32Handle(_:)`` instead. See **Bridging with `FileDescriptor`**.

#### Conformances

These types conform to `Sendable` and nothing else. `Sendable` is safe on a uniquely owned handle, and Windows permits concurrent use of one handle from multiple threads. `Hashable` may be revisited when noncopyable hashed collections are more widely available.

### Opening

```swift
extension Win32.FileHandle {
  /// Opens or creates a file, device, or pipe.
  ///
  /// - Parameters:
  ///   - path: The path to open.
  ///   - access: The requested access rights. An empty set requests neither
  ///     read nor write access, which allows for querying metadata where a
  ///     read open could be denied.
  ///   - shareMode: How the file may be shared with other opens while this
  ///     handle is alive. The default is `[.read, .write, .delete]`, matching
  ///     POSIX `open` behavior. Pass `[]` for exclusive access, which is what
  ///     `CreateFileW` does for a `dwShareMode` of 0.
  ///   - disposition: Whether to create, open, or truncate.
  ///   - attributes: File attributes to apply when the file is created, or
  ///     when `.createAlways` overwrites an existing one. Otherwise ignored.
  ///     `.normal` requests no attributes and is valid only on its own.
  ///     Overwriting a `.hidden` or `.system` file fails with `.accessDenied`
  ///     unless `attributes` matches those bits.
  ///   - flags: Caching, semantic, and lifetime flags for this handle.
  ///   - inheritable: Whether child processes created with handle inheritance
  ///     enabled receive a copy of this handle. Applies whether the file is
  ///     created or opened.
  ///   - securityDescriptor: The security descriptor to apply when the file
  ///     is created. Ignored when an existing file is opened. This descriptor
  ///     is borrowed, not consumed.
  ///   - templateFile: A handle whose attributes and extended attributes are
  ///     applied to a newly created file. Must have been opened with
  ///     ``Win32/AccessMask/genericRead``. Ignored when an existing file is
  ///     opened. This handle is borrowed, not consumed.
  ///
  /// Throws ``Win32/Error/invalidParameter`` if `flags` contains
  /// `FILE_FLAG_OVERLAPPED`, which ``Win32/FileHandle`` does not support.
  ///
  /// The corresponding C function is `CreateFileW`.
  public static func open(
    _ path: FilePath,
    access: Win32.AccessMask,
    shareMode: Win32.ShareMode = [.read, .write, .delete],
    disposition: Win32.CreationDisposition = .openExisting,
    attributes: Win32.FileAttributes = .normal,
    flags: Win32.FileFlags = [],
    inheritable: Bool = false,
    securityDescriptor: borrowing Win32.SecurityDescriptor? = nil,
    templateFile: borrowing Win32.FileHandle? = nil
  ) throws(Win32.Error) -> Win32.FileHandle

  /// The result of ``openOrCreate(_:access:shareMode:overwriteExisting:attributes:flags:inheritable:securityDescriptor:templateFile:)``.
  @frozen
  public struct OpenOrCreateResult: ~Copyable, Sendable {
    /// The open handle.
    public let handle: Win32.FileHandle

    /// Whether the file already existed.
    public let existed: Bool
  }

  /// Opens a file, creating it if it does not exist, and reports whether it
  /// already existed.
  ///
  /// - Parameters:
  ///   - overwriteExisting: Whether to overwrite the contents of a file that
  ///     already exists. `false` corresponds to `OPEN_ALWAYS`, and `true` to
  ///     `CREATE_ALWAYS`. `CREATE_ALWAYS` also applies `attributes` to an
  ///     existing file.
  ///
  /// All other parameters and errors behave as they do on
  /// ``open(_:access:shareMode:disposition:attributes:flags:inheritable:securityDescriptor:templateFile:)``.
  ///
  /// The corresponding C function is `CreateFileW`.
  public static func openOrCreate(
    _ path: FilePath,
    access: Win32.AccessMask,
    shareMode: Win32.ShareMode = [.read, .write, .delete],
    overwriteExisting: Bool = false,
    attributes: Win32.FileAttributes = .normal,
    flags: Win32.FileFlags = [],
    inheritable: Bool = false,
    securityDescriptor: borrowing Win32.SecurityDescriptor? = nil,
    templateFile: borrowing Win32.FileHandle? = nil
  ) throws(Win32.Error) -> OpenOrCreateResult
}
```

Notes on the signature:

* **`shareMode` defaults to read, write, and delete.** That is not the Windows default, but it matches what callers coming from POSIX expect, and what System's existing `open` adapter already hardcodes.
* **`disposition` is a single choice, not an option set.** `CREATE_NEW`, `CREATE_ALWAYS`, `OPEN_EXISTING`, `OPEN_ALWAYS`, and `TRUNCATE_EXISTING` are mutually exclusive. `OpenOptions` conflates creation and truncation into a bitmask because POSIX `open` does. Win32 does not.
* **`attributes` and `flags` are separate parameters.** `CreateFileW` takes them OR'd together into a single `dwFlagsAndAttributes`. Attributes are properties of the file, and flags are properties of this handle. The wrapper combines them.
* **`inheritable` and `securityDescriptor` replace a raw `SECURITY_ATTRIBUTES` pointer.** The wrapper builds the struct from these two fields plus the boilerplate `nLength` field.
* **`securityDescriptor` and `templateFile` borrow an optional binding.** Both are `borrowing` parameters of noncopyable optional type, so the borrow only happens when the argument is already typed `Win32.SecurityDescriptor?` or `Win32.FileHandle?`. Passing a non-optional variable fails to compile with a request to add `consume`, which destroys the descriptor or closes the template handle. An inline call result is consumed without a diagnostic since nothing else holds it. See **Future directions** for the language features that would remove this wrinkle.
* **`openOrCreate` reports file existence in the return type.** With `OPEN_ALWAYS` or `CREATE_ALWAYS`, `CreateFileW` returns a valid handle for an existing file and sets the last error to `ERROR_ALREADY_EXISTS`. We shouldn't throw this error on success, so `openOrCreate` reports it via `OpenOrCreateResult.existed`.
  - Note: the implementation must first call `SetLastError(ERROR_SUCCESS)`, per [SYS-0009](0009-win32-namespace-and-error.md), so that a stale error is never misread as "already existed".
  - Note: `.openAlways` and `.createAlways` remain reachable through `open`, where they discard `existed`.

### Opening a directory

```swift
extension Win32.DirectoryHandle {
  /// Opens a directory.
  ///
  /// `FILE_FLAG_BACKUP_SEMANTICS` is added to `flags` automatically. Without
  /// that flag, `CreateFileW` fails on a directory.
  ///
  /// Throws ``Win32/Error/invalidParameter`` if `flags` contains
  /// `FILE_FLAG_OVERLAPPED`, which ``Win32/DirectoryHandle`` does not support.
  ///
  /// Throws ``Win32/Error/invalidDirectoryName`` if `path` is not a directory,
  /// after closing the handle it opened.
  ///
  /// The corresponding C function is `CreateFileW`.
  public static func open(
    _ path: FilePath,
    access: Win32.AccessMask = .listDirectory,
    shareMode: Win32.ShareMode = [.read, .write, .delete],
    flags: Win32.FileFlags = [],
    inheritable: Bool = false
  ) throws(Win32.Error) -> Win32.DirectoryHandle
}
```

Developers may be unaware that `FILE_FLAG_BACKUP_SEMANTICS` is required to open a directory. A separate `DirectoryHandle` type makes this common use case reachable without that knowledge. The type also removes the read and write surface that `ReadFile` and `WriteFile` reject at runtime.

`DirectoryHandle` has no `disposition`, `attributes`, `securityDescriptor`, or `templateFile` parameter. Creating a directory requires `CreateDirectoryW`, not `CreateFileW`, and should be considered in a future proposal.

`FILE_FLAG_BACKUP_SEMANTICS` allows a directory to be opened, but does not require the returned handle to be a directory. `open` verifies the result: after `CreateFileW` succeeds, it calls `GetFileInformationByHandle` to confirm the object is a directory, and throws `.invalidDirectoryName` otherwise. Without that check, a regular-file path would yield a `DirectoryHandle` that fails every directory operation.

### Path handling

`open` will canonicalize `path` similar to how `FileDescriptor.open` does on Windows: `GetFullPathNameW` to resolve the path against the current directory and collapse dot segments, then `PathAllocCanonicalize` with `PATHCCH_ALLOW_LONG_PATHS` to apply the `\\?\` prefix when the result exceeds `MAX_PATH`. However, `open` will leave both `\\.\` and `\\?\` paths untouched, whereas `FileDescriptor` only does so for `\\.\`. (The `\\?\` prefix means "pass this path through verbatim", so canonicalizing it would defeat its purpose.)

A failed `PathAllocCanonicalize` reports an `HRESULT`, but `open` throws `Win32.Error`, so System will convert the `FACILITY_WIN32` errors internally. A public `Win32.HResult` remains future work as described in [SYS-0009](0009-win32-namespace-and-error.md).

### Supporting types for `open`

| Type | Wraps | Notable members |
| --- | --- | --- |
| `Win32.AccessMask` | `DWORD` `OptionSet` | `.genericRead`, `.genericWrite`, `.readData`, `.listDirectory`, `.readAttributes`, `.delete`, see below |
| `Win32.ShareMode` | `DWORD` `OptionSet` | `.read`, `.write`, `.delete` |
| `Win32.CreationDisposition` | `DWORD` `RawRepresentable` | `.createNew`, `.createAlways`, `.openExisting`, `.openAlways`, `.truncateExisting` |
| `Win32.FileFlags` | `DWORD` `OptionSet` | `.backupSemantics`, `.noBuffering`, `.writeThrough`, `.sequentialScan`, `.randomAccess`, `.deleteOnClose`, `.openReparsePoint`, `.posixSemantics`, `.openNoRecall`, `.sessionAware` |
| `Win32.FileAttributes` | `DWORD` `OptionSet` | `.normal`, `.readOnly`, `.hidden`, `.system`, `.archive`, `.temporary`, `.offline`, `.encrypted` |
| `Win32.SecurityDescriptor` | `PSECURITY_DESCRIPTOR` | `init(sddl:)`, see below |

These option-set and raw-value types conform to `Sendable`, `Hashable`, and `Codable`, matching `OpenOptions` and `FileDescriptor.SeekOrigin`.

`Win32.FileAttributes` is introduced here because `CreateFileW` requires it. Only the subset above is meaningful at creation time. A future proposal covering file information queries should extend this type to the full set of reported values.

#### `Win32.AccessMask`

`Win32.AccessMask` covers the rights `CreateFileW` accepts in `dwDesiredAccess`. The generic rights are `.genericRead`, `.genericWrite`, `.genericExecute`, and `.genericAll`. The standard rights are `.delete`, `.readControl`, `.writeDAC`, `.writeOwner`, and `.synchronize`.

The specific rights occupy the low 16 bits, and Windows gives four of them a second name for directories. Both spellings are vended by `AccessMask`:

| Value | File spelling | Directory spelling |
| --- | --- | --- |
| `0x1` | `.readData` | `.listDirectory` |
| `0x2` | `.writeData` | `.addFile` |
| `0x4` | `.appendData` | `.addSubdirectory` |
| `0x20` | `.execute` | `.traverse` |

Each pair of spellings names one bit, so `mask.contains(.listDirectory)` is true of any mask holding `.readData`; vending both names trades that ambiguity for a faithful mapping of the underlying type.

The remaining specific rights have one name each: `.readExtendedAttributes` (`0x8`), `.writeExtendedAttributes` (`0x10`), `.deleteChild` (`0x40`, meaningful only on a directory), `.readAttributes` (`0x80`), and `.writeAttributes` (`0x100`).

`.maximumAllowed` doesn't name a right at all. It asks the system to grant every right the access check finds the caller entitled to, and it never appears in a mask reported back.

#### No `.overlapped`

`Win32.FileFlags` vends `.overlapped` as an unavailable member so the restriction is discoverable:

```swift
@available(*, unavailable, message: "Overlapped handles are not supported")
public static var overlapped: FileFlags { get }
```

`FileFlags(rawValue:)` can still carry the bit, so all three opening entry points reject it with a synthesized ``Win32/Error/invalidParameter`` before calling `CreateFileW`. None of the synchronous I/O in [SYS-0011](0011-win32-file-io.md) survives an overlapped handle: a transfer can report itself complete while the kernel is still writing into the span's memory, or a call can return `ERROR_IO_PENDING` immediately while the work completes later. A future asynchronous handle API should instead apply the flag implicitly and withhold the operations that fail, like ``Win32/DirectoryHandle`` does with `FILE_FLAG_BACKUP_SEMANTICS`.

``init?(unsafelyAdopting:)`` does not check for the flag. Although detecting an overlapped handle is possible via `NtQueryInformationFile`, an unsafe wrapper init is not the place for an expensive syscall. It's the caller's responsibility to keep the invariant, or drive a handle asynchronously through raw Win32 with their own `OVERLAPPED` structures if they wish.

#### `Win32.SecurityDescriptor`

```swift
extension Win32 {
  /// A Windows security descriptor.
  ///
  /// This type owns its storage and releases it with `LocalFree`.
  ///
  /// The corresponding C type is `PSECURITY_DESCRIPTOR`.
  @frozen @safe
  public struct SecurityDescriptor: ~Copyable, Sendable {
    /// Parses a Security Descriptor Definition Language string.
    ///
    /// The corresponding C function is
    /// `ConvertStringSecurityDescriptorToSecurityDescriptorW` with
    /// `SDDL_REVISION_1`.
    public init(sddl: String) throws(Win32.Error)

    /// Adopts a descriptor allocated with `LocalAlloc`, taking ownership.
    ///
    /// Returns `nil` if `raw` is `NULL`.
    @unsafe
    public init?(unsafelyAdopting raw: PSECURITY_DESCRIPTOR?)

    /// The raw C pointer. Valid only while this value is alive.
    @unsafe
    public var unsafeRawPointer: PSECURITY_DESCRIPTOR { get }

    /// Gives up ownership and returns the raw pointer.
    ///
    /// The caller becomes responsible for releasing it with `LocalFree`.
    @unsafe
    public consuming func relinquish() -> PSECURITY_DESCRIPTOR
  }
}
```

`SecurityDescriptor` mirrors the handle types: owning, noncopyable, and `Sendable`. Win32 functions return descriptors in `LocalAlloc` memory that no Swift value owns, so a borrowing wrapper isn't feasible. Without a safe constructor, every use of `securityDescriptor:` would require `@unsafe` adoption, so this proposal provides SDDL parsing to start:

```swift
let sd: Win32.SecurityDescriptor? = try .init(sddl: "D:P(A;;GA;;;SY)(A;;GA;;;BA)")
let file = try Win32.FileHandle.open(
  path, access: .genericWrite, disposition: .createNew, securityDescriptor: sd
)
```

Descriptors from elsewhere, such as `GetSecurityInfo`, can arrive through `init?(unsafelyAdopting:)`, and the typed APIs in **Future directions** can extend the type without changing `open`'s signature.

### Duplication and inheritance

```swift
extension Win32.FileHandle {
  /// Duplicates this handle within the current process.
  ///
  /// - Parameters:
  ///   - access: The duplicate's access rights. `nil` requests the same
  ///     rights this handle has.
  ///   - inheritable: Whether child processes created with handle inheritance
  ///     enabled receive a copy of the duplicate.
  ///
  /// - Returns: A new owned handle. The caller must close it.
  ///
  /// The corresponding C function is `DuplicateHandle`.
  public borrowing func duplicate(
    access: Win32.AccessMask? = nil,
    inheritable: Bool = false
  ) throws(Win32.Error) -> Win32.FileHandle

  /// Whether child processes created with handle inheritance enabled receive
  /// a copy of this handle.
  ///
  /// The corresponding C functions are `GetHandleInformation` and
  /// `SetHandleInformation` with `HANDLE_FLAG_INHERIT`.
  public borrowing func isInheritable() throws(Win32.Error) -> Bool
  public borrowing func setInheritable(_ value: Bool) throws(Win32.Error)
}
```

`Win32.DirectoryHandle` gets the same three members. Its `duplicate` returns a `Win32.DirectoryHandle`.

`duplicate()` covers the common same-process case and mirrors `FileDescriptor.duplicate()`. A `nil` `access` passes `DUPLICATE_SAME_ACCESS`. Duplicating into another process requires a target process handle and is out of scope for this proposal.

### Bridging with `FileDescriptor`

The two types convert in both directions, with different ownership semantics:

```swift
extension FileDescriptor {
  /// Calls `body` with the Win32 handle backing this descriptor.
  ///
  /// The handle is **borrowed** from the C runtime descriptor, which owns it
  /// and closes it when the descriptor is closed. The borrow is valid only for
  /// the duration of the call.
  ///
  /// `body` receives `nil` for an invalid descriptor, or for a valid
  /// descriptor with no underlying handle, which the C runtime reports for
  /// the standard descriptors in a process with no console.
  ///
  /// - Parameter body: A closure that receives the handle backing this
  ///   descriptor, or `nil` if it has none.
  /// - Returns: The return value, if any, of the `body` closure.
  ///
  /// The corresponding C function is `_get_osfhandle`.
  public func withWin32Handle<R: ~Copyable>(
    _ body: (borrowing Win32.FileHandle?) throws -> R
  ) rethrows -> R

  /// Wraps a Win32 handle in a C runtime file descriptor, **consuming**
  /// the handle.
  ///
  /// On success, the returned descriptor owns the handle, and closing the
  /// descriptor closes it. On failure, this initializer closes the handle
  /// before throwing.
  ///
  /// - Parameters:
  ///   - handle: The handle to wrap.
  ///   - translation: The descriptor's translation mode. Defaults to
  ///     `.binary`, which passes bytes through unchanged.
  ///   - append: Whether every write seeks to the end of the file first.
  ///
  /// - Note: The descriptor's access is that of the underlying handle.
  ///
  /// The corresponding C function is `_open_osfhandle`.
  public init(
    adopting handle: consuming Win32.FileHandle,
    translation: TranslationMode = .binary,
    append: Bool = false
  ) throws(Errno)

  /// The C runtime's translation mode for a file descriptor.
  @frozen
  public struct TranslationMode: RawRepresentable, Sendable, Hashable, Codable {
    /// The raw C flag.
    public var rawValue: CInt

    /// Creates a strongly-typed translation mode from a raw C flag.
    public init(rawValue: CInt)

    /// Bytes pass through unchanged.
    ///
    /// The corresponding C constant is `_O_BINARY`.
    public static var binary: TranslationMode { get }

    /// Expands `\n` to `\r\n` on write and collapses it on read.
    ///
    /// The corresponding C constant is `_O_TEXT`.
    public static var text: TranslationMode { get }

    /// Translates in Unicode mode.
    ///
    /// Writes UTF-16, and on read, uses the byte order mark to choose UTF-8
    /// or UTF-16LE, falling back to ANSI when there is none.
    ///
    /// - Warning: Reading or writing an odd number of bytes in this mode is a
    ///   C runtime parameter validation error, which terminates the process
    ///   by default.
    ///
    /// The corresponding C constant is `_O_WTEXT`.
    public static var wideText: TranslationMode { get }
  }
}
```

`withWin32Handle(_:)` is a closure so the scope of the borrow is visible at the call site. A `yielding borrow` property could be added once that feature stabilizes. Both sentinels, `INVALID_HANDLE_VALUE` and `_NO_CONSOLE_FILENO`, are returned as `nil`. The implementation brackets the call with a no-op `_set_thread_local_invalid_parameter_handler`, since `_get_osfhandle` on an invalid descriptor otherwise invokes the C runtime's invalid parameter handler, which terminates the process by default.

`init(adopting:)` consumes its handle and does not return ownership on failure. It throws `Errno` because it lives on `FileDescriptor`. The `translation` and `append` parameters cover every `_open_osfhandle` flag except the implicit `_O_RDONLY`, which is `0x0000` on Windows. The C runtime's `_read` and `_write` call `ReadFile` and `WriteFile` with a null `lpOverlapped`, so an overlapped handle would carry the same hazard as **No `.overlapped`** describes.

`Win32.DirectoryHandle` has no bridge: `_open_osfhandle` on a directory handle produces a descriptor that fails every C runtime operation.

## Source compatibility

This proposal is additive and source-compatible with existing code.

## ABI compatibility

This proposal is additive and ABI-compatible with existing code.

## Implications on adoption

`Win32.FileHandle`, `Win32.DirectoryHandle`, and the `FileDescriptor`-bridging APIs sit behind `#if os(Windows)`, so cross-platform callers must guard their uses.

## Future directions

* **Reading and writing.** [SYS-0011](0011-win32-file-io.md).
* **Volume and path information.** [SYS-0012](0012-win32-volume-and-path-info.md).
* **Querying and setting file information.** `GetFileInformationByHandleEx` and `SetFileInformationByHandle`, and the information classes they take. See the roadmap in [SYS-0009](0009-win32-namespace-and-error.md).
* **Directory operations.** `Win32.DirectoryHandle` is the entry point for enumeration with `FileIdBothDirectoryInfo`, change notification with `ReadDirectoryChangesW`, and per-directory case sensitivity. Creation with `CreateDirectoryW` belongs there too.
* **Named pipes.** `Win32.FileHandle.open` connects to an existing pipe today, but creating one requires `CreateNamedPipeW` and its pipe mode, instance count, and timeout parameters, or `CreatePipe` for an anonymous pair. `Win32.AccessMask` withholds `FILE_CREATE_PIPE_INSTANCE`, a third spelling of `0x4`, until then.
* **Asynchronous I/O.** An overlapped handle should have its own type that applies `FILE_FLAG_OVERLAPPED` implicitly. Completion ports, cancellation, and the relationship to the `IORing` work deserve their own design.
* **A cross-platform `FileInfo`.** [SYS-0006](0006-system-stat.md) future directions describe an ergonomic metadata abstraction over `Stat` and the Windows types, and this series builds the underlying Windows types.
* **Standard handles.** `GetStdHandle` is the Win32 analog of ``FileDescriptor/standardInput`` and friends.
* **Borrowing `securityDescriptor` and `templateFile` without an annotation.** `Ref<Win32.SecurityDescriptor>?` and `Ref<Win32.FileHandle>?` ([SE-0519](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0519-ref-mutableref-types.md)) would let callers pass a non-optional value directly, and `Optional.ref` ([SE-0532](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0532-optional-noncopyable-improvements.md)) would let the implementation inspect the parameter with `if let` rather than a `switch`. Both require a newer toolchain than System currently supports.
* **Security descriptors.** `Win32.SecurityDescriptor` initially covers only SDDL parsing and could be extended: reading a descriptor with `GetSecurityInfo`, applying one with `SetSecurityInfo`, rendering one to SDDL with `ConvertSecurityDescriptorToStringSecurityDescriptorW`, and typed ACL and SID APIs. All of these allocate with `LocalAlloc`, so they fit the existing `deinit`; an API that frees another way, such as `CreatePrivateObjectSecurity`, would need a different type.

## Alternatives considered

### A copyable value type with a manual `close()`

Model `Win32.FileHandle` on `FileDescriptor`: a `@frozen` copyable struct conforming to `RawRepresentable` and `Hashable`, with a non-consuming `close()`. This matches System's house style and allows handles in ordinary collections.

Rejected because:

* Double close, use after close, and leaks all stay expressible, as **A copied handle is a use-after-close hazard** describes.
* The decision is asymmetric. A copyable borrowed view can be added to a noncopyable type later, but ownership cannot be added to a copyable type at all.

### A `class` with a closing `deinit`

Make `Win32.FileHandle` a `class` whose `deinit` closes the handle, preventing leaks without a noncopyable type.

Rejected because:

* It adds ARC and an allocation to a type that is morally a machine word. A `~Copyable` struct prevents leaks with neither cost, and on the explicit-close path the optimizer produces the same function as the copyable design.
* Every copy of the reference gains the ability to close.

### A `deinit` that traps on leak

As prior art, NIO's `SystemFileHandle` calls `fatalError` when a handle is dropped without being closed or detached, and never closes implicitly.

Rejected because turning a leaked handle into a process abort is a policy that an application could choose but a low-level library like System should not impose here.

### Scoped `withOpen` and `closeAfter` entry points

`withOpen(path, access:...) { file in }` and a `consuming func closeAfter(_:)` would make the close impossible to forget, as `FileDescriptor.closeAfter(_:)` does today.

Rejected because:

* Noncopyable ownership already guarantees that, so the scoped forms only add more API surface (up to four large declarations restating `open`'s nine-parameter list and doc comment).
* They give up typed throws. A scoped form merges the failures of `CreateFileW`, the body, and `CloseHandle` into one type, so it could only be spelled `throws`. Individual statements let each call throw its own type. Swift has no error union to recover it, and a wrapper enum forces every caller to destructure. Pinning the body to `throws(Win32.Error)` behind a disfavored general overload comes closest, but it would only match a body that can't throw at all.

### Extend `FileDescriptor` instead

Add the missing `CreateFileW` capabilities, such as share modes and handle flags, to `OpenOptions` on Windows.

Rejected because:

* It gives Windows-only meanings to portable `OpenOptions` members, on a type documented and used as a cross-platform POSIX file descriptor.
* It leaves out handle duplication and overlapped I/O no matter which options are added.
* It can't fix the `pread` deviation, where matching POSIX semantics would take three calls (seek, read, restore) and not be atomic against other users of the handle.

### Enable `OpenOptions.directory` on Windows

Lifting the `#if !os(Windows)` on `OpenOptions.directory` is implementable: set `FILE_FLAG_BACKUP_SEMANTICS`, then fail with `ENOTDIR` if the resulting handle lacks `FILE_ATTRIBUTE_DIRECTORY`. Setting the flag on every open would fix portability more broadly.

Rejected because:

* The POSIX and Windows semantics are inverted. `O_DIRECTORY` restricts `open` to directories, while `FILE_FLAG_BACKUP_SEMANTICS` lets `CreateFileW` open directories it would otherwise refuse. One spelling would mean opposite things on either side of an `#if`.
* Setting the flag on every open would override file security checks for a process holding `SE_BACKUP_NAME` or `SE_RESTORE_NAME`.
* The useful directory operations on Windows require a `HANDLE` anyway.

### One handle type with a `.backupSemantics` flag

Keep a single `Win32.FileHandle` and let callers pass `flags: .backupSemantics` to open a directory. One fewer type, and perfectly faithful to `CreateFileW`.

Rejected for the reasons in **Opening a directory**:

* A separate type makes the directory case reachable without knowing about the flag.
* It removes a read and write surface that fails at runtime on a directory handle.

### Put the bridge entirely on `Win32.FileHandle`

Spell the conversions `Win32.FileHandle.init?(borrowing: FileDescriptor)` and `Win32.FileHandle.fileDescriptor(translation:append:)`, so every Windows-only declaration stays inside the namespace.

Rejected because:

* The two directions have different ownership, and the spellings should show it. The borrow direction cannot be an initializer at all, since the result would be an owning value that closes a handle it does not own. The reverse transfers ownership and can fail, so it should not read like an accessor, whereas an initializer on the destination type states the transfer plainly.
* `TranslationMode` is C runtime state, so `FileDescriptor` gains an extension either way.

### A general `Win32.Handle` protocol

Windows `HANDLE` is polymorphic across object types, so a `~Copyable` protocol with `close()`, `duplicate()`, and the inheritance members is tempting.

Rejected for now because:

* It would deduplicate four members across two types at the cost of a public protocol.
* The lifetime operations may not lift cleanly to a third kind anyway, since a search handle from `FindFirstFileW` closes with `FindClose` rather than `CloseHandle`. A protocol can be added later if a third handle type appears.

### Return a result struct from a single `open`

`open` would return `OpenOrCreateResult` for every disposition, and `openOrCreate` would not exist, de-duplicating the parameter list and doc comment across two declarations.

Rejected because it taxes every caller with a `.handle` access, when only the minority that passes `.openAlways` or `.createAlways` cares whether the file existed.

## Appendix

### Swift API to C mappings

| Swift | C |
| --- | --- |
| `Win32.FileHandle`, `Win32.DirectoryHandle` | `HANDLE` |
| `Win32.SecurityDescriptor` | `PSECURITY_DESCRIPTOR` |
| `Win32.SecurityDescriptor.init(sddl:)` | `ConvertStringSecurityDescriptorToSecurityDescriptorW` with `SDDL_REVISION_1` |
| `Win32.SecurityDescriptor.deinit` | `LocalFree` |
| `Win32.FileHandle.open(_:access:shareMode:disposition:attributes:flags:inheritable:securityDescriptor:templateFile:)` | `CreateFileW` |
| `Win32.FileHandle.openOrCreate(_:access:shareMode:overwriteExisting:attributes:flags:inheritable:securityDescriptor:templateFile:)` | `CreateFileW` with `OPEN_ALWAYS`, or `CREATE_ALWAYS` when `overwriteExisting` |
| `OpenOrCreateResult.existed` | `ERROR_ALREADY_EXISTS` after a successful `OPEN_ALWAYS` or `CREATE_ALWAYS` |
| `Win32.DirectoryHandle.open(_:access:shareMode:flags:inheritable:)` | `CreateFileW` with `FILE_FLAG_BACKUP_SEMANTICS` |
| `Win32.FileHandle.close()` | `CloseHandle` |
| `Win32.FileHandle.deinit` | `CloseHandle`, error discarded |
| `Win32.FileHandle.relinquish()` | none; gives up ownership of the `HANDLE` |
| `Win32.FileHandle.duplicate(access:inheritable:)` | `DuplicateHandle` |
| `Win32.FileHandle.isInheritable()` | `GetHandleInformation` with `HANDLE_FLAG_INHERIT` |
| `Win32.FileHandle.setInheritable(_:)` | `SetHandleInformation` with `HANDLE_FLAG_INHERIT` |
| `Win32.AccessMask` | `dwDesiredAccess` |
| `Win32.ShareMode` | `dwShareMode` |
| `Win32.CreationDisposition` | `dwCreationDisposition` |
| `Win32.FileFlags` and `Win32.FileAttributes` | `dwFlagsAndAttributes` |
| `inheritable:` and `securityDescriptor:` | `lpSecurityAttributes` (`SECURITY_ATTRIBUTES`) |
| `templateFile:` | `hTemplateFile` |
| `FileDescriptor.withWin32Handle(_:)` | `_get_osfhandle`, guarded by `_set_thread_local_invalid_parameter_handler` |
| `FileDescriptor.init(adopting:translation:append:)` | `_open_osfhandle` |
| `FileDescriptor.TranslationMode` | `_O_BINARY`, `_O_TEXT`, `_O_WTEXT` |
