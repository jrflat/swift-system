# A `Win32` Namespace and `Win32.Error` for Swift System

* Proposal: [SYS-0009](0009-win32-namespace-and-error.md)
* Author: [Jonathan Flat](https://github.com/jrflat)
* Review Manager: TBD
* Status: **Draft**
* Implementation: TBD
* Review: TBD

#### Revision history

* **v1** Initial version.

## Introduction

System's file system APIs are POSIX-shaped, and on Windows they are built mostly on the Universal C Runtime's POSIX compatibility layer. That layer is a portability shim, not a model of the operating system. This proposal adds `Win32`, a namespace for Windows-native file system APIs, and `Win32.Error`, the error type those APIs report.

Later proposals in this series nest their types in the namespace and throw the error. See **Future directions** for the rest of the roadmap.

## Motivation

### Windows API layers

Windows exposes file system functionality at several layers, and it matters which one System wraps:

| Layer | Examples | Support this in System? |
| --- | --- | --- |
| Kernel-mode file system interfaces | IRPs, `FltMgr` minifilters, `FsRtl*` | No. Driver-only. |
| NT Native API (`ntdll.dll`) | `NtCreateFile`, `NtQueryInformationFile` | No. Only partly documented, and not stability-committed. |
| **Win32 base API** (`kernel32`/`kernelbase`) | `CreateFileW`, `GetFileInformationByHandleEx` | **Yes** |
| C runtime (UCRT) | `_open_osfhandle`, `_get_osfhandle`, `_read`, `_close` | Yes. This is how `FileDescriptor` works today. |
| Shell, COM, WinRT, .NET | `IFileOperation`, `Windows.Storage` | No. Different app models. |

Win32 is the documented, stable, ABI-committed system interface for desktop Windows, and System already reaches it. System's Windows adapters implement `open` by calling `CreateFileW` directly rather than `_wopen`, then convert the handle to a descriptor with `_open_osfhandle`. What System lacks is a place to name the Win32 layer in its public APIs.

### System has no home for Windows-native APIs

The library already treats POSIX and Windows file metadata as disjoint surfaces. `UserID`, `GroupID`, `DeviceID`, and `Inode` are declared entirely inside `#if !os(Windows)`. [SYS-0006](0006-system-stat.md) proposes `Stat` for Unix-like platforms only, where we argue in its **Alternatives considered**:

> Rather than forcing Windows file metadata semantics into a cross-platform `Stat` type, we should instead create Windows-specific types that give developers full access to platform-native file metadata.

Those Windows-specific types need somewhere to live, and System has a shipped precedent for the shape. `Mach` is a caseless `enum` that serves purely as a namespace for a family of platform-specific types:

```swift
@available(System 1.4.0, *)
@frozen
public enum Mach {
  public struct Port<RightType: MachPortRight>: ~Copyable { ... }
  public enum PortRightError: Error { ... }
  // ...
}
```

A `Win32` namespace follows that precedent.

### `Errno` can't express Windows failures

Every Windows failure in System currently goes through the internal `Errno(windowsError:)`, which delegates to `_mapWindowsErrorToErrno`. That function approximates the Microsoft C runtime's `_dosmaperr` table, with a few additions. Its purpose is to make the POSIX shim behave: when `FileDescriptor.read` fails, something has to go in `errno`, and `_dosmaperr` is what the CRT would have put there. `Errno` is fit for that purpose, but unfit for reporting errors from a Win32-native API.

**It folds several thousand codes onto sixteen.** The table names about fifty error codes and covers fewer than a hundred in total. `winerror.h` defines several thousand. Every code the table does not recognize returns `EINVAL`, so the failure reason is completely ambiguous.

**Its ranges conflate unrelated failures, and the codes a Win32-native API produces are mostly in the unmapped tail.** Everything from code 19 through 36 becomes `EACCES`:

| Code | Meaning | Maps to |
| --- | --- | --- |
| `ERROR_NOT_READY` (21) | The device is not ready | `EACCES` |
| `ERROR_CRC` (23) | Cyclic redundancy check failed | `EACCES` |
| `ERROR_WRITE_FAULT` (29) | Write fault on the device | `EACCES` |
| `ERROR_SHARING_VIOLATION` (32) | Another process holds an incompatible open | `EACCES` |
| `ERROR_LOCK_VIOLATION` (33) | A byte-range lock blocked the access | `EACCES` |
| `ERROR_NOT_SUPPORTED` (50) | The volume or device does not support the request | `EINVAL` |
| `ERROR_FILE_TOO_LARGE` (223) | Exceeds a file system limit | `EINVAL`, not `EFBIG` |
| `ERROR_MORE_DATA` (234) | The buffer was too small; retry with a larger one | `EINVAL` |
| `ERROR_DELETE_PENDING` (303) | The file is marked for deletion and can't be reopened | `EINVAL` |

A media failure, a device that's not ready, and a sharing violation are three different problems with three different responses, and all of them are indistinguishable from a genuine `ERROR_ACCESS_DENIED`. `ERROR_SHARING_VIOLATION` matters most to Windows callers, because it's retryable and has no POSIX analog. Further down, `ERROR_MORE_DATA` is a retry instruction rather than a failure, and a caller that can't distinguish it from `EINVAL` can't write the grow-and-retry loop that Windows' variable-length query APIs require. `ERROR_NO_MORE_FILES` is likewise an enumeration termination sentinel rather than a failure, but it maps to `ENOENT`.

None of this is a defect in `_mapWindowsErrorToErrno`. The shim's job is to match what the C runtime does, and it does. The problem is that the destination type has nowhere to put the information.

## Proposed solution

Add `Win32`, a namespace available on Windows and scoped to the Win32 layer, and `Win32.Error`, the error currency for everything in it. Also provide a public `Errno(approximating: Win32.Error)` conversion for callers who want a POSIX approximation, and document that it's lossy.

```swift
#if os(Windows)
do {
  // `Win32.FileHandle` is proposed separately, in SYS-0010.
  let handle = try Win32.FileHandle.open(path, access: .genericWrite)
  try handle.close()
} catch Win32.Error.sharingViolation {
  // Retryable: another process has the file open with an incompatible share mode.
} catch let error {
  log("open failed: \(error)")                   // localized system message
  log("open failed: \(error.debugDescription)")  // ERROR_ACCESS_DENIED (5, 0x5)
  let posix = Errno(approximating: error)        // an explicitly lossy conversion
}
#endif
```

## Detailed design

Wrapper constants and functions introduced here are `@_alwaysEmitIntoClient`. All APIs carry the availability of the System release that introduces them.

### The `Win32` namespace

```swift
#if os(Windows)
/// A namespace for Win32 APIs on Windows.
///
/// The types and functions nested here wrap the Win32 base API, the
/// documented, ABI-stable interface exported by `kernel32.dll` and
/// `kernelbase.dll`.
@frozen
public enum Win32 {}
#endif
```

A caseless, `@frozen` `enum` is the right mechanism here. `Win32` names the layer precisely and matches the vocabulary of the Windows SDK and Microsoft's documentation.

### `Win32.Error`

```swift
extension Win32 {
  /// A Windows system error code.
  ///
  /// This represents a value reported by `GetLastError`.
  @frozen
  public struct Error: RawRepresentable, Swift.Error, Sendable, Hashable, Codable {
    /// The raw C error code.
    public let rawValue: DWORD

    /// Creates a strongly-typed error from a raw C error code.
    public init(rawValue: DWORD)

    /// Creates a strongly-typed error from a raw C error code.
    public init(_ rawValue: DWORD)

    /// The operation completed successfully.
    ///
    /// The corresponding C constant is `ERROR_SUCCESS`.
    public static var success: Error { get }

    // ... a curated set of named codes, including:
    public static var fileNotFound: Error { get }           // ERROR_FILE_NOT_FOUND
    public static var pathNotFound: Error { get }           // ERROR_PATH_NOT_FOUND
    public static var accessDenied: Error { get }           // ERROR_ACCESS_DENIED
    public static var invalidHandle: Error { get }          // ERROR_INVALID_HANDLE
    public static var noMoreFiles: Error { get }            // ERROR_NO_MORE_FILES
    public static var deviceNotReady: Error { get }         // ERROR_NOT_READY
    public static var cyclicRedundancyCheck: Error { get }  // ERROR_CRC
    public static var writeFault: Error { get }             // ERROR_WRITE_FAULT
    public static var sharingViolation: Error { get }       // ERROR_SHARING_VIOLATION
    public static var lockViolation: Error { get }          // ERROR_LOCK_VIOLATION
    public static var notLocked: Error { get }              // ERROR_NOT_LOCKED
    public static var negativeSeek: Error { get }           // ERROR_NEGATIVE_SEEK
    public static var endOfFile: Error { get }              // ERROR_HANDLE_EOF
    public static var notSupported: Error { get }           // ERROR_NOT_SUPPORTED
    public static var fileExists: Error { get }             // ERROR_FILE_EXISTS
    public static var invalidParameter: Error { get }       // ERROR_INVALID_PARAMETER
    public static var insufficientBuffer: Error { get }     // ERROR_INSUFFICIENT_BUFFER
    public static var alreadyExists: Error { get }          // ERROR_ALREADY_EXISTS
    public static var fileTooLarge: Error { get }           // ERROR_FILE_TOO_LARGE
    public static var diskFull: Error { get }               // ERROR_DISK_FULL
    public static var moreData: Error { get }               // ERROR_MORE_DATA
    public static var invalidDirectoryName: Error { get }   // ERROR_DIRECTORY
    public static var deletePending: Error { get }          // ERROR_DELETE_PENDING
    public static var operationAborted: Error { get }       // ERROR_OPERATION_ABORTED
    public static var ioPending: Error { get }              // ERROR_IO_PENDING
    public static var notReparsePoint: Error { get }        // ERROR_NOT_A_REPARSE_POINT
  }
}

extension Win32.Error: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String { get }
  public var debugDescription: String { get }
}

extension Win32.Error {
  public static func ~= (_ lhs: Win32.Error, _ rhs: Swift.Error) -> Bool
}
```

The named constants are not exhaustive. However, codes that a caller might reasonably check for should be supported, especially codes that System's Windows APIs are documented to return. `rawValue` covers everything else. A `struct` over `DWORD` keeps unknown codes representable and round-trippable, which is required for a type modeling an error space of several thousand values that every driver and filter can extend.

### `description` and `debugDescription`

Like `Errno`, `Win32.Error` should provide a human-readable `description` using `FormatMessageW` with `FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_IGNORE_INSERTS`. Like `strerror`, the message will be localized to the system or thread locale, so it's suitable for display or logging, but not programmatic matching or tests. Note that the call also allocates a buffer that must be released with `LocalFree`, so `description` should be avoided in hot paths. These system messages end with a trailing `\r\n`, which `description` must strip. It must also fall back to a numeric rendering when `FormatMessageW` fails.

`debugDescription` gives the symbolic constant with the decimal and hexadecimal value, such as `ERROR_SHARING_VIOLATION (32, 0x20)`, and the numeric form alone for codes that have no name. It's locale-independent and suitable for tests or structured logs.

### Capturing the last error

`GetLastError` is thread-local and volatile. The next Win32 call on the thread clobbers it, and so can an ARC release that runs a `deinit` between the failing call and the error read. Every wrapper in the namespace must capture the code into a `Win32.Error` immediately at the failure site.

Some Win32 functions can succeed while leaving a stale error in place. A System wrapper that reads `GetLastError` after such a function must first call `SetLastError(ERROR_SUCCESS)` so that users don't have to.

> Note: A Win32 function can also fail while `GetLastError` reports `ERROR_SUCCESS`. Wrappers report the error directly from the system, so a `throws(Win32.Error)` API can throw `.success`.

### Success with a note

Some Win32 calls succeed and set a last error that carries information. A `throws` signature can't express "succeeded, with extra information", so `Win32.Error` does not try. APIs in the namespace that can produce this extra information must surface it in the return type instead. A concrete case is `CreateFileW` with `OPEN_ALWAYS` or `CREATE_ALWAYS`, which returns a valid handle and sets `ERROR_ALREADY_EXISTS` to report that the file already existed. See [SYS-0010](0010-win32-filehandle.md).

### Interoperating with `Errno`

The conversion to `Errno` is lossy:

```swift
extension Errno {
  /// The closest POSIX equivalent of a Windows system error.
  ///
  /// This mapping is lossy. It approximates the C runtime's `_dosmaperr`
  /// behavior, which folds Windows' several thousand system error codes onto
  /// sixteen `Errno` values. Codes it does not recognize become
  /// ``Errno/invalidArgument``. Prefer handling ``Win32/Error`` directly.
  public init(approximating error: Win32.Error)
}
```

This gives the existing internal `Errno(windowsError:)` a public spelling. Its behavior does not change, because the POSIX shim still needs the behavior, but the lossiness becomes part of the contract instead of an implementation detail. The `approximating:` label carries that warning at the call site.

## Source compatibility

This proposal is additive and source-compatible with existing code.

## ABI compatibility

This proposal is additive and ABI-compatible with existing code.

## Implications on adoption

`Win32` and everything in it sits behind `#if os(Windows)`, so cross-platform callers must guard their uses. This is intentional so the platform dependency is visible at the use site rather than hidden behind a portable-looking type with unportable behavior.

## Future directions

### The `Win32` file system roadmap

This proposal is the foundation for a series of others. Each is mostly reviewable on its own, but depends on the ones above it for the final shape:

| Stage | Proposal |
| --- | --- |
| `Win32` namespace, `Win32.Error` | This proposal |
| `Win32.FileHandle`, opening and closing, `FileDescriptor` bridging | [SYS-0010](0010-win32-filehandle.md) |
| Reading, writing, seeking, flushing, resizing, and locking | [SYS-0011](0011-win32-file-io.md) |
| Volume and path information for a handle | [SYS-0012](0012-win32-volume-and-path-info.md) |
| Querying file information | Future |
| Setting file information | Future |

**Querying file information.** `GetFileInformationByHandle` and `GetFileInformationByHandleEx` provide file metadata on Windows: attributes, file identifiers, alignment, compression, remote protocol details, alternate data streams, and directory enumeration. A future proposal should nest those information classes and their associated types in `Win32`.

**Setting file information.** `SetFileInformationByHandle` is the natural companion, and reaches semantics that have no `FileDescriptor` spelling at all, notably `FILE_DISPOSITION_POSIX_SEMANTICS` and `FILE_RENAME_POSIX_SEMANTICS`. It should follow once the query side has settled the shape of the information-class types.

**Beyond the file system.** Security descriptors (`GetSecurityInfo`, `SetSecurityInfo`, ACLs, and SIDs) are the Windows analog of `FilePermissions` and `UserID`, and are large enough to be their own effort.

### `Win32.HResult`

COM-shaped APIs in the Win32 surface (the `PathCch*` family in particular) report an `HRESULT` rather than a system error code, and System's Windows path canonicalization already flattens one with a private helper. The namespace will eventually need a public story for this, most likely a minimal `Win32.HResult` wrapper with a `var win32Error: Win32.Error?` that extracts the code only when the facility is `FACILITY_WIN32`. None of the proposals above need to surface it publicly, so it's left out for now.

## Alternatives considered

### Throw `Errno` from Win32 APIs too

Report failures from the new Win32 APIs as `Errno`, converting through the existing mapping table. This would be consistent with the rest of System and would avoid leaving Windows with two error types.

Rejected for the reasons in **`Errno` can't express Windows failures**:

* `_mapWindowsErrorToErrno` folds several thousand codes onto sixteen `Errno` values.
* It makes ranges of unrelated codes indistinguishable.
* The codes a Win32-native API produces are mostly in the unmapped tail.

### Extend `_mapWindowsErrorToErrno` instead of adding a type

Give the mapping table more entries and finer distinctions, so that `Errno` remains System's only error type on every platform.

Rejected because:

* The destination is still `Errno`, which has no cases for e.g. sharing violations, pending deletes, or in-progress overlapped I/O, so a better table still couldn't express them.
* Changing the table would change the `errno` values that existing `FileDescriptor` operations report, which would be a breaking behavior change. The shim should keep matching the C runtime.

### Name the namespace `Windows`

Name the namespace for the platform rather than the API layer. This may be safer if System later wraps something that's not Win32.

Rejected because:

* It's more vague, and reads as a synonym for `os(Windows)`.
* The APIs it would future-proof against (the NT Native API, the Shell, WinRT) are explicitly excluded from this proposal.

### No namespace, prefixed top-level names

Spell the types `Win32Error`, `Win32FileHandle`, and so on, with no enclosing type.

Rejected because:

* A namespace is the canonical way to organize and document which of Windows' several overlapping API layers is being wrapped.
* `Mach` and `Mach.Port` already provide precedent in System.

### Name the error type `Win32.ErrorCode`

`ErrorCode` is more literal, since Windows calls these "system error codes", and it would avoid shadowing `Swift.Error` inside the namespace.

Rejected because it's verbose, and including "Code" in the name of an `Error` type is unusual.

### An `enum` with cases instead of a `struct`

Give `Win32.Error` a case per named code, making a `switch` over it exhaustive.

Rejected because an `enum` can't represent a code the library has not enumerated, and the Windows error space is open-ended.

### A public `Win32.Error.current`

A `GetLastError` wrapper, with a setter for `SetLastError`, would let callers read and clear the last error themselves.

Rejected because:

* Such an accessor can't be made correct by construction. Swift may insert an ARC release between the failing call and the read, and the caller's own intervening work could clobber the value, too. `Errno.current` is internal for the same reason.
* Callers using raw Win32 functions already have `GetLastError` and `SetLastError`, and can wrap a result with `Win32.Error.init(_:)`.

## Appendix

### Swift API to C mappings

| Swift | C |
| --- | --- |
| `Win32.Error` | `DWORD` system error code |
| `Win32.Error.description` | `FormatMessageW` with `FORMAT_MESSAGE_FROM_SYSTEM` |
| `Errno.init(approximating:)` | `_dosmaperr` (as `_mapWindowsErrorToErrno`) |
