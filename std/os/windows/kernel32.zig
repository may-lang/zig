use @import("index.zig");

pub extern "kernel32" stdcallcc fn CloseHandle(hObject: HANDLE) BOOL;

pub extern "kernel32" stdcallcc fn CreateDirectoryA(
    lpPathName: LPCSTR,
    lpSecurityAttributes: ?*SECURITY_ATTRIBUTES,
) BOOL;

pub extern "kernel32" stdcallcc fn CreateFileA(
    lpFileName: LPCSTR,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?LPSECURITY_ATTRIBUTES,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) HANDLE;

pub extern "kernel32" stdcallcc fn CreatePipe(
    hReadPipe: *HANDLE,
    hWritePipe: *HANDLE,
    lpPipeAttributes: *const SECURITY_ATTRIBUTES,
    nSize: DWORD,
) BOOL;

pub extern "kernel32" stdcallcc fn CreateProcessA(
    lpApplicationName: ?LPCSTR,
    lpCommandLine: LPSTR,
    lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    bInheritHandles: BOOL,
    dwCreationFlags: DWORD,
    lpEnvironment: ?*c_void,
    lpCurrentDirectory: ?LPCSTR,
    lpStartupInfo: *STARTUPINFOA,
    lpProcessInformation: *PROCESS_INFORMATION,
) BOOL;

pub extern "kernel32" stdcallcc fn CreateSymbolicLinkA(
    lpSymlinkFileName: LPCSTR,
    lpTargetFileName: LPCSTR,
    dwFlags: DWORD,
) BOOLEAN;

pub extern "kernel32" stdcallcc fn CreateIoCompletionPort(FileHandle: HANDLE, ExistingCompletionPort: ?HANDLE, CompletionKey: ULONG_PTR, NumberOfConcurrentThreads: DWORD) ?HANDLE;

pub extern "kernel32" stdcallcc fn CreateThread(lpThreadAttributes: ?LPSECURITY_ATTRIBUTES, dwStackSize: SIZE_T, lpStartAddress: LPTHREAD_START_ROUTINE, lpParameter: ?LPVOID, dwCreationFlags: DWORD, lpThreadId: ?LPDWORD) ?HANDLE;

pub extern "kernel32" stdcallcc fn DeleteFileA(lpFileName: LPCSTR) BOOL;

pub extern "kernel32" stdcallcc fn ExitProcess(exit_code: UINT) noreturn;

pub extern "kernel32" stdcallcc fn FindFirstFileA(lpFileName: LPCSTR, lpFindFileData: *WIN32_FIND_DATAA) HANDLE;
pub extern "kernel32" stdcallcc fn FindClose(hFindFile: HANDLE) BOOL;
pub extern "kernel32" stdcallcc fn FindNextFileA(hFindFile: HANDLE, lpFindFileData: *WIN32_FIND_DATAA) BOOL;

pub extern "kernel32" stdcallcc fn FreeEnvironmentStringsA(penv: [*]u8) BOOL;

pub extern "kernel32" stdcallcc fn GetCommandLineA() LPSTR;

pub extern "kernel32" stdcallcc fn GetConsoleMode(in_hConsoleHandle: HANDLE, out_lpMode: *DWORD) BOOL;

pub extern "kernel32" stdcallcc fn GetCurrentDirectoryA(nBufferLength: WORD, lpBuffer: ?LPSTR) DWORD;

pub extern "kernel32" stdcallcc fn GetEnvironmentStringsA() ?[*]u8;

pub extern "kernel32" stdcallcc fn GetEnvironmentVariableA(lpName: LPCSTR, lpBuffer: LPSTR, nSize: DWORD) DWORD;

pub extern "kernel32" stdcallcc fn GetExitCodeProcess(hProcess: HANDLE, lpExitCode: *DWORD) BOOL;

pub extern "kernel32" stdcallcc fn GetFileSizeEx(hFile: HANDLE, lpFileSize: *LARGE_INTEGER) BOOL;

pub extern "kernel32" stdcallcc fn GetFileAttributesA(lpFileName: LPCSTR) DWORD;

pub extern "kernel32" stdcallcc fn GetModuleFileNameA(hModule: ?HMODULE, lpFilename: LPSTR, nSize: DWORD) DWORD;

pub extern "kernel32" stdcallcc fn GetLastError() DWORD;

pub extern "kernel32" stdcallcc fn GetFileInformationByHandleEx(
    in_hFile: HANDLE,
    in_FileInformationClass: FILE_INFO_BY_HANDLE_CLASS,
    out_lpFileInformation: *c_void,
    in_dwBufferSize: DWORD,
) BOOL;

pub extern "kernel32" stdcallcc fn GetFinalPathNameByHandleA(
    hFile: HANDLE,
    lpszFilePath: LPSTR,
    cchFilePath: DWORD,
    dwFlags: DWORD,
) DWORD;

pub extern "kernel32" stdcallcc fn GetProcessHeap() ?HANDLE;
pub extern "kernel32" stdcallcc fn GetQueuedCompletionStatus(CompletionPort: HANDLE, lpNumberOfBytesTransferred: LPDWORD, lpCompletionKey: *ULONG_PTR, lpOverlapped: *?*OVERLAPPED, dwMilliseconds: DWORD) BOOL;

pub extern "kernel32" stdcallcc fn GetSystemInfo(lpSystemInfo: *SYSTEM_INFO) void;
pub extern "kernel32" stdcallcc fn GetSystemTimeAsFileTime(*FILETIME) void;

pub extern "kernel32" stdcallcc fn HeapCreate(flOptions: DWORD, dwInitialSize: SIZE_T, dwMaximumSize: SIZE_T) ?HANDLE;
pub extern "kernel32" stdcallcc fn HeapDestroy(hHeap: HANDLE) BOOL;
pub extern "kernel32" stdcallcc fn HeapReAlloc(hHeap: HANDLE, dwFlags: DWORD, lpMem: *c_void, dwBytes: SIZE_T) ?*c_void;
pub extern "kernel32" stdcallcc fn HeapSize(hHeap: HANDLE, dwFlags: DWORD, lpMem: *const c_void) SIZE_T;
pub extern "kernel32" stdcallcc fn HeapValidate(hHeap: HANDLE, dwFlags: DWORD, lpMem: *const c_void) BOOL;
pub extern "kernel32" stdcallcc fn HeapCompact(hHeap: HANDLE, dwFlags: DWORD) SIZE_T;
pub extern "kernel32" stdcallcc fn HeapSummary(hHeap: HANDLE, dwFlags: DWORD, lpSummary: LPHEAP_SUMMARY) BOOL;

pub extern "kernel32" stdcallcc fn GetStdHandle(in_nStdHandle: DWORD) ?HANDLE;

pub extern "kernel32" stdcallcc fn HeapAlloc(hHeap: HANDLE, dwFlags: DWORD, dwBytes: SIZE_T) ?*c_void;

pub extern "kernel32" stdcallcc fn HeapFree(hHeap: HANDLE, dwFlags: DWORD, lpMem: *c_void) BOOL;

pub extern "kernel32" stdcallcc fn MoveFileExA(
    lpExistingFileName: LPCSTR,
    lpNewFileName: LPCSTR,
    dwFlags: DWORD,
) BOOL;

pub extern "kernel32" stdcallcc fn PostQueuedCompletionStatus(CompletionPort: HANDLE, dwNumberOfBytesTransferred: DWORD, dwCompletionKey: ULONG_PTR, lpOverlapped: ?*OVERLAPPED) BOOL;

pub extern "kernel32" stdcallcc fn QueryPerformanceCounter(lpPerformanceCount: *LARGE_INTEGER) BOOL;

pub extern "kernel32" stdcallcc fn QueryPerformanceFrequency(lpFrequency: *LARGE_INTEGER) BOOL;

pub extern "kernel32" stdcallcc fn ReadFile(
    in_hFile: HANDLE,
    out_lpBuffer: *c_void,
    in_nNumberOfBytesToRead: DWORD,
    out_lpNumberOfBytesRead: *DWORD,
    in_out_lpOverlapped: ?*OVERLAPPED,
) BOOL;

pub extern "kernel32" stdcallcc fn RemoveDirectoryA(lpPathName: LPCSTR) BOOL;

pub extern "kernel32" stdcallcc fn SetFilePointerEx(
    in_fFile: HANDLE,
    in_liDistanceToMove: LARGE_INTEGER,
    out_opt_ldNewFilePointer: ?*LARGE_INTEGER,
    in_dwMoveMethod: DWORD,
) BOOL;

pub extern "kernel32" stdcallcc fn SetHandleInformation(hObject: HANDLE, dwMask: DWORD, dwFlags: DWORD) BOOL;

pub extern "kernel32" stdcallcc fn Sleep(dwMilliseconds: DWORD) void;

pub extern "kernel32" stdcallcc fn TerminateProcess(hProcess: HANDLE, uExitCode: UINT) BOOL;

pub extern "kernel32" stdcallcc fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) DWORD;

pub extern "kernel32" stdcallcc fn WriteFile(
    in_hFile: HANDLE,
    in_lpBuffer: *const c_void,
    in_nNumberOfBytesToWrite: DWORD,
    out_lpNumberOfBytesWritten: ?*DWORD,
    in_out_lpOverlapped: ?*OVERLAPPED,
) BOOL;

//TODO: call unicode versions instead of relying on ANSI code page
pub extern "kernel32" stdcallcc fn LoadLibraryA(lpLibFileName: LPCSTR) ?HMODULE;

pub extern "kernel32" stdcallcc fn FreeLibrary(hModule: HMODULE) BOOL;
