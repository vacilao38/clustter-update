"""Publish only verified installer/APK artifacts to the selected distribution repo.

Credentials are obtained from the existing Git helper in memory. No token is
written to disk, arguments, logs, assets or source repositories.
"""
import argparse
import hashlib
import http.client
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = "vacilao38/clustter-cores-downloads"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--publish", action="store_true", help="Make the verified release public after uploading")
    args = parser.parse_args()
    project = args.project.resolve()
    pubspec = (project / "pubspec.yaml").read_text(encoding="utf-8")
    app_id = re.search(r"(?m)^name:\s*([a-z][a-z0-9_]*)\s*$", pubspec)[1]
    version = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$", pubspec)[1]
    if app_id not in {"folk", "lake", "chain", "noon", "pile"}:
        raise ValueError("New catalog products require explicit publication authorization and tooling registration")
    folder = project / f"dist/{version}"
    installer = json.loads((folder / "installer.json").read_text(encoding="utf-8"))
    android = json.loads((folder / "android.json").read_text(encoding="utf-8"))
    if (installer["testBuild"] or installer["version"] != version
            or android["version"] != version or not android["verified"]
            or not android.get("internetPermission")):
        raise ValueError("Only verified release artifacts can be distributed")
    expected = [installer, *android["assets"]]
    files = []
    for asset in expected:
        file = folder / asset["file"]
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        if file.stat().st_size != asset["bytes"] or digest != asset["sha256"]:
            raise ValueError("Artifact changed after verification")
        files.append(file)
    checksums = folder / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{a['sha256']}  {a['file']}\n" for a in expected), encoding="utf-8")
    files.append(checksums)
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    credential = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n", env=env,
        text=True, capture_output=True, check=True).stdout
    token = dict(line.split("=", 1) for line in credential.splitlines() if "=" in line)["password"]
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Clustter-release"}

    def api(method, path, data=None, missing=False):
        request = urllib.request.Request("https://api.github.com" + path,
            data=None if data is None else json.dumps(data).encode(), method=method,
            headers=dict(headers, **({"Content-Type": "application/json"} if data is not None else {})))
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            raise RuntimeError(f"GitHub {method} failed with HTTP {error.code}") from None

    tag = f"{app_id}-v{version}"
    release = api("GET", f"/repos/{REPO}/releases/tags/{tag}", missing=True)
    body = (f"{args.name} {version} para Windows x64 e Android 7+.\n\n"
        "- Protocolo Update: avisa dentro do aplicativo quando existir versão publicada superior e abre a página oficial para download.\n"
        "- Windows: instalador .exe por usuário, atalho no menu Iniciar e desinstalador; atualizações preservam projetos e preferências.\n"
        "- Android: APKs ARM64, ARM32 e x64 com o mesmo certificado das versões anteriores. Instale por cima, sem desinstalar nem limpar dados.\n\n"
        "Os avisos começam nesta versão: instalações antigas precisam desta primeira atualização manual. Não há instalação automática nem notificação com o aplicativo fechado. "
        "A consulta usa só metadados do catálogo público, sem enviar arquivos/projetos. Mantenha backups dos seus trabalhos.\n\n"
        "Instaladores/APKs compilados, versões, certificados, arquiteturas e hashes conferidos. Testes automatizados aprovados; uso em Android físico permanece pendente. "
        "Instalador Windows sem certificado de editor verificado; APKs preservam a assinatura pessoal de desenvolvimento. Veja requisitos e limites de cada app na Clustter.\n\n"
        "Confira SHA256SUMS.txt. Este release não inclui código-fonte privado ou dados de uso.\n\n<!-- clustter-update-release-v1 -->")
    if release is None:
        release = api("POST", f"/repos/{REPO}/releases", {"tag_name": tag, "name": f"{args.name} {version} · Update e instalador Windows",
            "body": body, "draft": True, "prerelease": False, "make_latest": "false"})
    if "<!-- clustter-update-release-v1 -->" not in (release.get("body") or ""):
        raise ValueError("Existing release wasn't created by this operation; preserve it")
    known = {asset["name"]: asset for asset in release["assets"]}
    for file in files:
        digest = "sha256:" + hashlib.sha256(file.read_bytes()).hexdigest()
        asset = known.get(file.name)
        if asset is not None:
            if asset.get("digest") != digest or asset["size"] != file.stat().st_size:
                raise ValueError("Existing asset differs; never overwrite a published installer")
        else:
            if not release["draft"]:
                raise ValueError("Do not mutate an already public release")
            conn = http.client.HTTPSConnection("uploads.github.com", timeout=180)
            try:
                upload_path = f"/repos/{REPO}/releases/{release['id']}/assets?name=" + urllib.parse.quote(file.name)
                conn.putrequest("POST", upload_path)
                for key, value in headers.items(): conn.putheader(key, value)
                conn.putheader("Content-Type", "application/octet-stream")
                conn.putheader("Content-Length", str(file.stat().st_size)); conn.endheaders()
                with file.open("rb") as stream:
                    while chunk := stream.read(1024 * 1024): conn.send(chunk)
                response = conn.getresponse()
                if response.status != 201:
                    raise RuntimeError(f"Asset upload failed with HTTP {response.status}")
                asset = json.load(response)
            finally:
                conn.close()
            if asset.get("digest") != digest or asset["size"] != file.stat().st_size:
                raise ValueError("Remote asset digest mismatch")
        print(json.dumps({"asset": file.name, "bytes": asset["size"], "verified": True}), flush=True)
    if args.publish and release["draft"]:
        release = api("PATCH", f"/repos/{REPO}/releases/{release['id']}", {"draft": False, "make_latest": "false"})
    result = {"app": app_id, "version": version, "release": release["html_url"], "draft": release["draft"], "verifiedAssets": len(files)}
    (folder / "publication.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
