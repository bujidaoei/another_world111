"""Map the PE only as a resource file; never execute its entry point or DLL init."""
from pathlib import Path
import ctypes
from ctypes import wintypes
import hashlib
import json

binary = Path('D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf/src/bin/godot.windows.editor.x86_64.exe')
evidence = Path(__file__).resolve().parent
kernel = ctypes.WinDLL('kernel32', use_last_error=True)
kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
kernel.LoadLibraryExW.restype = wintypes.HMODULE
kernel.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
kernel.FindResourceW.restype = wintypes.HANDLE
kernel.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
kernel.SizeofResource.restype = wintypes.DWORD
kernel.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
kernel.LoadResource.restype = wintypes.HANDLE
kernel.LockResource.argtypes = [wintypes.HANDLE]
kernel.LockResource.restype = ctypes.c_void_p
kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
kernel.FreeLibrary.restype = wintypes.BOOL
flags = 0x00000002 | 0x00000020  # LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE
module = kernel.LoadLibraryExW(str(binary), None, flags)
if not module:
    raise ctypes.WinError(ctypes.get_last_error())
records = []
try:
    for resource_id in (1, 2, 3):
        resource = kernel.FindResourceW(module, ctypes.c_void_p(resource_id), ctypes.c_void_p(24))
        if not resource:
            records.append({'resource_id': resource_id, 'exists': False, 'win32_error': ctypes.get_last_error()})
            continue
        size = kernel.SizeofResource(module, resource)
        if not 0 < size < 65_536:
            raise RuntimeError('Unexpected manifest resource size')
        data = ctypes.string_at(kernel.LockResource(kernel.LoadResource(module, resource)), size)
        output = evidence / f'pe-manifest-{resource_id}.xml'
        output.write_bytes(data)
        records.append({'resource_id': resource_id, 'exists': True, 'bytes': size, 'sha256': hashlib.sha256(data).hexdigest(), 'path': str(output)})
finally:
    kernel.FreeLibrary(module)
(evidence / 'pe-manifests.json').write_text(json.dumps({'binary': str(binary), 'load_flags': flags, 'engine_entry_point_executed': False, 'GPU_or_Main_or_GDB_executed': False, 'resources': records}, indent=2), encoding='utf-8')
print(json.dumps(records))
