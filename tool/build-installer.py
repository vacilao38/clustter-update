"""Package a verified Flutter Windows build into a per-user Clustter installer."""
import argparse
import ctypes
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


def product_version(exe: Path) -> str:
    api = ctypes.windll.version
    size = api.GetFileVersionInfoSizeW(str(exe), None)
    if not size:
        raise ValueError("Executable has no Windows version resource")
    data = ctypes.create_string_buffer(size)
    if not api.GetFileVersionInfoW(str(exe), 0, size, data):
        raise ValueError("Cannot read Windows version resource")
    pointer, length = ctypes.c_void_p(), ctypes.c_uint()
    # Flutter writes ProductVersion in the US English Unicode resource table.
    if not api.VerQueryValueW(data, "\\StringFileInfo\\040904e4\\ProductVersion", ctypes.byref(pointer), ctypes.byref(length)):
        raise ValueError("Executable has no Flutter ProductVersion")
    return ctypes.wstring_at(pointer, length.value).rstrip("\0")


def escape(text: str) -> str:
    return text.replace("$", "$$").replace('"', '$\\"')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--crt", type=Path)
    parser.add_argument("--test", action="store_true", help="Isolated registry id; no shortcuts")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    project = args.project.resolve()
    pubspec = (project / "pubspec.yaml").read_text(encoding="utf-8")
    app_id = re.search(r"(?m)^name:\s*([a-z][a-z0-9_]*)\s*$", pubspec)[1]
    match = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec)
    if not match or not re.fullmatch(r"[A-Za-z][A-Za-z0-9 ]{1,40}", args.name):
        raise ValueError("Stable pubspec version+build and a simple app name are required")
    version, build = match.groups()
    release = project / "build/windows/x64/runner/Release"
    exe = release / f"{app_id}.exe"
    if product_version(exe) != f"{version}+{build}":
        raise ValueError(f"Stale Windows build: recompile {app_id} {version}+{build}")
    if not (release / "flutter_windows.dll").is_file() or not (release / "data/flutter_assets").is_dir():
        raise ValueError("Incomplete Flutter Windows release")
    compiler = (args.compiler or root / ".tools/nsis-3.13/makensis.exe").resolve()
    if not compiler.is_file():
        raise ValueError("Provide the official NSIS compiler using --compiler")
    crt = args.crt
    if crt is None:
        candidates = list(Path("C:/Program Files/Microsoft Visual Studio").glob("*/Community/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT"))
        if not candidates:
            raise ValueError("Provide the installed toolchain redistributable CRT using --crt")
        crt = sorted(candidates)[-1]
    if not (crt / "vcruntime140.dll").is_file():
        raise ValueError("Incomplete redistributable C++ runtime")
    local = root / ".local/installers"
    local.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f"{app_id}-", dir=local))
    payload = stage / "payload"
    shutil.copytree(release, payload)
    for dll in crt.glob("*.dll"):
        shutil.copy2(dll, payload / dll.name)
    if app_id == "folk" and not all((payload / n).is_file() for n in ["ffmpeg.exe", "ffprobe.exe", "whisper_ggml.dll", "data/flutter_assets/assets/models/ggml-base-q5_1.bin"]):
        raise ValueError("Folk requires its bundled models and FFmpeg runtime")
    if any(f.suffix.lower() in {".keystore", ".jks", ".sqlite", ".db"} or f.name.startswith(".env") for f in payload.rglob("*") if f.is_file()):
        raise ValueError("Unexpected credentials/user database in Windows payload")
    (payload / "LEIA-ME-INSTALACAO.txt").write_text(
        f"{args.name} {version} · Clustter cores\n\nInstalação por usuário. Abra pelo menu Iniciar.\n"
        "O protocolo Update avisa no aplicativo e abre o site para baixar novas versões.\n"
        "Instale a nova versão no mesmo local. Feche o app e salve seu trabalho antes.\n"
        "Projetos e preferências ficam no perfil do usuário e são preservados na atualização/desinstalação.\n"
        f"https://vacilao38.github.io/clustter-cores-downloads/#{app_id}\n", encoding="utf-8")
    output_dir = project / f"dist/{version}"
    output_dir.mkdir(parents=True, exist_ok=True)
    suffix = "-Test" if args.test else ""
    output = output_dir / f"{args.name}-{version}-Windows-x64-Setup{suffix}.exe"
    uninstall = stage / "uninstall-files.nsh"
    files = sorted(f.relative_to(payload) for f in payload.rglob("*") if f.is_file())
    dirs = sorted((f.relative_to(payload) for f in payload.rglob("*") if f.is_dir()), key=lambda p: len(p.parts), reverse=True)
    uninstall.write_text("\n".join(
        [f'Delete "$INSTDIR\\{escape(str(f))}"' for f in files] +
        [f'RMDir "$INSTDIR\\{escape(str(f))}"' for f in dirs]), encoding="utf-8")
    defines = {"APP_ID": app_id, "REG_ID": f"UpdateTest.{app_id}" if args.test else app_id,
        "APP_NAME": args.name, "APP_EXE": exe.name, "APP_VERSION": version,
        "NUMERIC_VERSION": f"{version}.{build}", "OUTPUT": str(output),
        "PAYLOAD": str(payload), "UNINSTALL_FILES": str(uninstall)}
    config = stage / "installer.nsi"
    config.write_text("; -*- coding: utf-8 -*-\n" +
        "\n".join(f'!define {k} "{escape(v)}"' for k, v in defines.items()) +
        ("\n!define TEST_BUILD\n" if args.test else "\n") +
        f'!include "{escape(str(root / "tool/windows-installer.nsi"))}"\n', encoding="utf-8")
    subprocess.run([str(compiler), "/V2", str(config)], check=True, cwd=stage)
    result = {"app": app_id, "version": version, "build": int(build), "file": output.name,
        "bytes": output.stat().st_size, "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "testBuild": args.test, "payloadFiles": len(files)}
    (output_dir / f"installer{suffix}.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
