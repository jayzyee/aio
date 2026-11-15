#!/usr/bin/env python3
"""Aoi Linux Bridge — stdlib-only companion for local or remote Linux workspaces.

Binds to 127.0.0.1 by default. In Codespaces cloud mode, the bridge keeps its
credential-bearing service account separate from a low-privilege project runner.
Project commands and Godot receive a clean environment and shared-workspace
access, not the bridge or GitHub credentials. This is defense in depth, not a
complete hostile-code sandbox: network access and the workspace remain exposed
to project code. Public binding requires HTTPS forwarding and a 256-bit secret.
Every API route requires X-Aoi-Token.
"""
from __future__ import annotations
import argparse, base64, binascii, hmac, json, os, re, subprocess, time, shutil, signal, threading, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 3_000_000
MAX_BINARY = 2 * 1024 * 1024
MAX_OUTPUT = 10_000
MAX_TEXT = 120_000
BLOCKED = [
    re.compile(r"(^|[;&| ])\s*(sudo|su|mkfs(?:\.[a-z0-9]+)?|reboot|shutdown|poweroff)\b", re.I),
    re.compile(r"\brm\s+-[^\n]*r[^\n]*f\s+/(?:\s|$)", re.I),
    re.compile(r"\bdd\s+if=", re.I),
    re.compile(r":\s*\(\s*\)\s*\{", re.I),
    re.compile(r"\b(curl|wget)\b[^\n|]*\|\s*(sh|bash)\b", re.I),
]


def atomic_write_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.aoi-tmp-{uuid.uuid4().hex}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)
    try:
        with os.fdopen(descriptor, "wb") as target:
            target.write(data)
            target.flush()
            os.fsync(target.fileno())
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


class Bridge(BaseHTTPRequestHandler):
    server_version = "AoiLinuxBridge/1.0"
    def log_message(self, fmt, *args): print("[AoiBridge] " + fmt % args)
    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data))); self.send_header("Cache-Control", "no-store"); self.end_headers(); self.wfile.write(data)
    def _auth(self):
        token = self.headers.get("X-Aoi-Token", "")
        address = self.client_address[0] if self.client_address else "unknown"
        now = time.monotonic()
        # create_server() installs these in production. Keep direct
        # ThreadingHTTPServer embedding compatible for integrations/tests too.
        # dict.setdefault is atomic under CPython's GIL, so concurrent first
        # requests converge on the same lock and failure map.
        auth_lock = self.server.__dict__.setdefault("auth_lock", threading.Lock())
        auth_failures = self.server.__dict__.setdefault("auth_failures", {})
        with auth_lock:
            state = auth_failures.get(address, {})
            locked_until = float(state.get("locked_until", 0.0))
            if now < locked_until:
                return False
            valid = bool(token) and hmac.compare_digest(token, self.server.token)
            if valid:
                auth_failures.pop(address, None)
                return True
            failures = int(state.get("failures", 0)) + 1
            # Public cloud endpoints get a short per-source lockout after 8
            # bad keys. The bridge token itself is 256-bit random material.
            auth_failures[address] = {
                "failures": failures,
                "locked_until": now + 60.0 if failures >= 8 else 0.0,
                "last_attempt": now,
            }
            # Public forwarded ports must not accumulate an unbounded map of
            # one-off source addresses. Evict the least-recently-failed source.
            if len(auth_failures) > 512:
                oldest = min(auth_failures, key=lambda key: float(auth_failures[key].get("last_attempt", 0.0)))
                auth_failures.pop(oldest, None)
            return False
    def _body(self):
        n = int(self.headers.get("Content-Length", "0"))
        if n < 0 or n > MAX_BODY: raise ValueError("Request body too large")
        data = self.rfile.read(n)
        obj = json.loads(data or b"{}")
        if not isinstance(obj, dict): raise ValueError("JSON body must be an object")
        return obj
    def _path(self, value):
        root = self.server.workspace.resolve()
        value = str(value or ".")
        candidate = (root / value).resolve() if not Path(value).is_absolute() else Path(value).resolve()
        if candidate != root and root not in candidate.parents: raise ValueError("Path is outside the configured workspace")
        return candidate
    def _runner_prefix(self, extra_env=None):
        """Build a clean execution environment for untrusted project code."""
        runner_user = getattr(self.server, "runner_user", "")
        if not runner_user:
            return [], {**os.environ, **(extra_env or {})}
        home = f"/home/{runner_user}"
        clean_env = {
            "PATH": f"/home/vscode/.local/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": home,
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "DISPLAY": os.environ.get("DISPLAY", ":99"),
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "AOI_WORKSPACE": str(self.server.workspace),
            "TMPDIR": "/tmp",
        }
        if extra_env:
            # Only explicit, caller-selected values are copied. The bridge
            # token and Codespaces credentials must never enter project code.
            clean_env.update({str(k): str(v) for k, v in extra_env.items()
                              if str(k) not in {"AOI_BRIDGE_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"}})
        prefix = ["sudo", "-n", "-u", runner_user]
        runner_group = getattr(self.server, "runner_group", "")
        if runner_group:
            prefix += ["-g", runner_group]
        prefix += ["--", "/usr/bin/env", "-i"]
        prefix += [f"{key}={value}" for key, value in clean_env.items()]
        # Keep even the sudo/env launcher process free of bridge and GitHub
        # credentials; env -i below is an additional boundary, not the only one.
        return prefix, clean_env

    def _runner_exec(self, argv, extra_env=None):
        """Launch one program with a clean environment and restrictive umask."""
        prefix, env = self._runner_prefix(extra_env)
        if not getattr(self.server, "runner_user", ""):
            return list(argv), env
        command = prefix + ["/bin/bash", "-c", 'umask 0002; exec "$@"', "aoi-runner-launcher"]
        command += [str(value) for value in argv]
        return command, env

    def _runner_shell(self, command):
        """Run a requested shell command as the isolated project account."""
        prefix, env = self._runner_prefix()
        if not getattr(self.server, "runner_user", ""):
            return ["bash", "-lc", command], env
        return prefix + ["/bin/bash", "-c", 'umask 0002; exec /bin/bash -c "$1"', "aoi-runner-shell", command], env

    def _signal_runner_process_group(self, pid, sig):
        if not getattr(self.server, "runner_user", ""):
            os.killpg(pid, sig)
            return
        signal_name = signal.Signals(sig).name
        command, env = self._runner_exec(["/bin/kill", f"-{signal_name}", "--", f"-{pid}"])
        result = subprocess.run(command, capture_output=True, text=True, timeout=6, env=env)
        if result.returncode != 0:
            raise ProcessLookupError(result.stderr.strip() or "Could not signal the isolated project process")

    def _run_bounded(self, command, cwd, timeout, env=None):
        """Run a command in its own process group and reap all children on timeout."""
        proc = subprocess.Popen(command, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=env, start_new_session=True)
        timed_out = False
        try:
            stdout, stderr = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                self._signal_runner_process_group(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    self._signal_runner_process_group(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = proc.communicate(timeout=3)
        result = subprocess.CompletedProcess(command, 124 if timed_out else proc.returncode, stdout, stderr)
        result.timed_out = timed_out
        return result

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/health":
            if not self._auth(): return self._send(401, {"error":"Unauthorized"})
            executable = self.server.godot_executable
            godot_path = shutil.which(executable) or (executable if Path(executable).is_file() else "")
            godot_version = ""
            godot_available = False
            if godot_path:
                try:
                    command, env = self._runner_exec([godot_path, "--version"])
                    version = subprocess.run(command, capture_output=True, text=True, timeout=6, env=env)
                    godot_version = (version.stdout or version.stderr).strip()[:80]
                    godot_available = version.returncode == 0 and godot_version != ""
                    if not godot_available and godot_version == "":
                        godot_version = "Found but could not be launched"
                except (OSError, subprocess.TimeoutExpired):
                    godot_version = "Found but could not be launched"
            return self._send(200, {"ok":True,"bridge":"Aoi Linux Bridge","workspace":str(self.server.workspace),
                                    "device":{"os":os.name,"platform":__import__("platform").platform()},
                                    "capabilities":{"filesystem":True,"terminal":True,"godot":godot_available,
                                                    "isolated_execution":bool(self.server.runner_user)},
                                    "godot":{"available":godot_available,"executable":godot_path,"version":godot_version}})
        return self._send(404, {"error":"Not found"})
    def do_POST(self):
        if not self._auth(): return self._send(401, {"error":"Unauthorized"})
        try:
            obj = self._body(); route = self.path.split("?", 1)[0]
            if route == "/v1/exec":
                command = str(obj.get("command", ""))
                if not command.strip() or len(command) > 5000: return self._send(400, {"error":"Command must be 1–5000 characters"})
                for pattern in BLOCKED:
                    if pattern.search(command): return self._send(403, {"error":"This command is blocked by the local safety policy"})
                cwd = self._path(obj.get("cwd", "."))
                if not cwd.is_dir(): return self._send(400, {"error":"Working directory does not exist"})
                timeout = max(1, min(int(obj.get("timeout", 30)), 60)); start = time.monotonic()
                try:
                    run_command, run_env = self._runner_shell(command)
                    run = self._run_bounded(run_command, cwd, timeout, run_env)
                    err = run.stderr + ("\nCommand timed out" if run.timed_out else "")
                    return self._send(200, {"ok":run.returncode == 0,"exit_code":run.returncode,"stdout":run.stdout[-MAX_OUTPUT:],"stderr":err[-MAX_OUTPUT:],"duration_ms":int((time.monotonic()-start)*1000),"cwd":str(cwd)})
                except OSError as exc:
                    return self._send(500,{"error":"Could not start the isolated project command: "+str(exc)[:240]})
            if route == "/v1/list":
                path = self._path(obj.get("path", "."));
                if not path.is_dir(): return self._send(400, {"error":"Directory not found"})
                items=[]
                for p in sorted(path.iterdir(), key=lambda x:(not x.is_dir(),x.name.lower()))[:200]:
                    items.append({"name":p.name,"type":"directory" if p.is_dir() else "file","size":p.stat().st_size if p.is_file() else 0})
                return self._send(200,{"ok":True,"path":str(path.relative_to(self.server.workspace)),"items":items})
            if route == "/v1/read":
                path=self._path(obj.get("path"));
                if not path.is_file(): return self._send(404,{"error":"File not found"})
                if path.stat().st_size > MAX_TEXT: return self._send(413,{"error":"File exceeds 120 KB read limit"})
                return self._send(200,{"ok":True,"path":str(path.relative_to(self.server.workspace)),"content":path.read_text(encoding="utf-8",errors="replace")})
            if route == "/v1/write":
                path=self._path(obj.get("path")); content=str(obj.get("content", ""))
                if len(content.encode()) > MAX_TEXT: return self._send(413,{"error":"File exceeds 120 KB write limit"})
                atomic_write_file(path, content.encode("utf-8"))
                return self._send(200,{"ok":True,"path":str(path.relative_to(self.server.workspace)),"bytes":path.stat().st_size})
            if route == "/v1/upload":
                path=self._path(obj.get("path")); encoded=str(obj.get("data", ""))
                if not encoded or len(encoded) > ((MAX_BINARY + 2) // 3) * 4 + 8: return self._send(413,{"error":"Binary upload must be between 1 byte and 2 MB"})
                try: binary=base64.b64decode(encoded, validate=True)
                except (binascii.Error, ValueError): return self._send(400,{"error":"Invalid base64 data"})
                if not binary or len(binary)>MAX_BINARY: return self._send(413,{"error":"Binary upload exceeds 2 MB"})
                atomic_write_file(path, binary)
                return self._send(200,{"ok":True,"path":str(path.relative_to(self.server.workspace)),"bytes":len(binary)})
            if route == "/v1/search":
                query=str(obj.get("query", "")).lower().strip()
                if not query or len(query)>120: return self._send(400,{"error":"Provide a search term"})
                root=self._path(obj.get("path", ".")); matches=[]
                for p in root.rglob("*"):
                    if any(part.startswith(".") or part in {"node_modules",".git",".venv","venv","__pycache__"} for part in p.parts): continue
                    if p.is_file() and p.stat().st_size <= 200_000:
                        try:
                            if query in p.read_text(encoding="utf-8",errors="ignore").lower(): matches.append(str(p.relative_to(self.server.workspace)))
                        except OSError: pass
                    if len(matches)>=50: break
                return self._send(200,{"ok":True,"matches":matches})
            if route == "/v1/godot/projects":
                found=[]; root=self.server.workspace
                for base, dirs, files in os.walk(root):
                    rel_base=Path(base).relative_to(root)
                    dirs[:] = [d for d in dirs if d not in {".git", ".godot", "node_modules", ".venv", "venv", "__pycache__"} and not d.startswith(".")]
                    if len(rel_base.parts) > 5: dirs[:] = []; continue
                    if "project.godot" in files:
                        folder=Path(base)
                        found.append({"name":folder.name,"path":str(folder.relative_to(root)),"project_file":"project.godot","modified":int((folder/"project.godot").stat().st_mtime)})
                        dirs[:] = []
                    if len(found) >= 100: break
                found.sort(key=lambda item:item["name"].lower())
                return self._send(200,{"ok":True,"projects":found,"workspace":str(root)})
            if route == "/v1/godot/create":
                executable=self.server.godot_executable
                if not (shutil.which(executable) or Path(executable).is_file()):
                    return self._send(503,{"error":"Godot is not installed or --godot points to an unavailable executable. Rebuild the cloud workspace so its configured Godot runtime can be installed, then reconnect."})
                raw = str(obj.get("name", "New Godot Project")).replace("\r", " ").replace("\n", " ").strip()
                raw = re.sub(r"\s+", " ", raw)[:80].strip()
                if not raw:
                    return self._send(400, {"error": "Enter a project name before creating the game."})
                # Keep the title safe for Godot's project.cfg string syntax and
                # prevent newlines or path characters from escaping the workspace.
                safe_title = raw.replace('"', "'").replace("\\", "-")
                slug = re.sub(r"[^A-Za-z0-9 _-]", "", safe_title).strip().replace(" ", "_")[:48] or "New_Godot_Project"
                raw_path = str(obj.get("path", slug)).strip().replace("\\", "/")
                path_parts = raw_path.split("/")
                if (not raw_path or raw_path.startswith("/") or len(raw_path) > 180
                        or any(part in {"", ".", ".."} for part in path_parts)
                        or any(":" in part for part in path_parts)):
                    return self._send(400, {"error": "Choose a valid folder inside this cloud workspace."})
                rel = "/".join(path_parts)
                project = self._path(rel)
                if project == self.server.workspace:
                    return self._send(400, {"error": "A project must use its own folder inside the workspace."})
                if project.exists():
                    if project.is_dir() and (project/"project.godot").is_file():
                        return self._send(200,{"ok":True,"existing":True,"name":raw,"path":str(project.relative_to(self.server.workspace)),"project_file":"project.godot"})
                    if not project.is_dir() or any(project.iterdir()):
                        return self._send(409, {"error": "That project folder already contains files but is not an Aoi Godot project. Choose another name or inspect the existing folder."})
                    project.rmdir()

                # Build the starter in a sibling staging directory and rename it
                # into place only after every file has been written. A failed
                # request therefore cannot strand a half-created project that
                # blocks the next retry.
                project.parent.mkdir(parents=True, exist_ok=True)
                staging = project.parent / ("." + project.name + ".aoi-tmp-" + uuid.uuid4().hex[:12])
                try:
                    (staging/"scenes").mkdir(parents=True,exist_ok=False)
                    (staging/"scripts").mkdir(parents=True,exist_ok=True)
                    config = ('; Aoi Studio starter project\nconfig_version=5\n\n[application]\nconfig/name="' + safe_title + '"\n'
                              'run/main_scene="res://scenes/main.tscn"\n'
                              'config/features=PackedStringArray("4.0", "GL Compatibility")\n\n'
                              '[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n\n'
                              '[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
                    (staging/"project.godot").write_text(config,encoding="utf-8")
                    (staging/"scenes"/"main.tscn").write_text('[gd_scene format=3]\n\n[node name="Main" type="Node2D"]\n',encoding="utf-8")
                    goal = str(obj.get("goal", "")).replace("\r", " ").strip()[:8000]
                    (staging/"README.md").write_text("# " + safe_title + "\n\nCreated by Aoi Studio.\n\n## Project goal\n\n" + goal + "\n", encoding="utf-8")
                    state=staging/".aoi_studio"; state.mkdir(exist_ok=True)
                    (state/"project.json").write_text(json.dumps({"created_by":"Aoi Studio","schema":1,"goal":goal},indent=2),encoding="utf-8")
                    staging.replace(project)
                except Exception:
                    shutil.rmtree(staging, ignore_errors=True)
                    raise
                return self._send(200,{"ok":True,"existing":False,"name":raw,"path":str(project.relative_to(self.server.workspace)),"project_file":"project.godot"})
            if route == "/v1/godot/scan":
                project=self._path(obj.get("path", "."))
                if not (project/"project.godot").is_file(): return self._send(400,{"error":"The selected folder does not contain project.godot"})
                items=[]; truncated=False
                for base, dirs, files in os.walk(project):
                    rel_base=Path(base).relative_to(project)
                    dirs[:] = sorted(d for d in dirs if d not in {".git", ".godot", "node_modules", ".venv", "venv", "__pycache__"} and not d.startswith(".") and len(rel_base.parts)<7)
                    for d in dirs: items.append({"path":str((rel_base/d).as_posix()),"name":d,"type":"directory"})
                    for name in sorted(files):
                        if name.startswith(".") or name.endswith(".import"): continue
                        full=Path(base)/name
                        try: size=full.stat().st_size
                        except OSError: size=0
                        items.append({"path":str((rel_base/name).as_posix()),"name":name,"type":"file","size":size})
                        if len(items)>=500: truncated=True; break
                    if len(items)>=500: break
                items.sort(key=lambda item:(item["type"]!="directory",item["path"].lower()))
                return self._send(200,{"ok":True,"path":str(project.relative_to(self.server.workspace)),"name":project.name,"items":items,"truncated":truncated})
            if route == "/v1/godot/run":
                project=self._path(obj.get("path", "."))
                if not (project/"project.godot").is_file(): return self._send(400,{"error":"The selected folder does not contain project.godot"})
                existing=self.server.godot_processes.get(str(project))
                if existing is not None and existing.poll() is None: return self._send(200,{"ok":True,"running":True,"pid":existing.pid,"path":str(project.relative_to(self.server.workspace))})
                executable=self.server.godot_executable
                if not (shutil.which(executable) or Path(executable).is_file()): return self._send(503,{"error":"Godot executable not found. Set --godot to the editor executable."})
                state=project/".aoi_studio"; state.mkdir(exist_ok=True)
                log=state/"run.log"; console=state/"console.log"
                handle=console.open("ab")
                launch_command, launch_env = self._runner_exec([executable,"--path",str(project),"--log-file",str(log)])
                try: proc=subprocess.Popen(launch_command,cwd=str(project),env=launch_env,stdout=handle,stderr=subprocess.STDOUT,start_new_session=True)
                except OSError as exc:
                    handle.close(); return self._send(500,{"error":"Could not launch Godot: "+str(exc)[:250]})
                handle.close()
                self.server.godot_processes[str(project)]=proc
                # Do not report a project as running if Godot exits immediately
                # because of a broken project, import error, or invalid scene.
                time.sleep(0.8)
                if proc.poll() is not None:
                    self.server.godot_processes.pop(str(project), None)
                    details = ""
                    try: details = console.read_text(encoding="utf-8", errors="replace")[-5000:]
                    except OSError: pass
                    return self._send(500,{"ok":False,"running":False,"pid":0,"error":"Godot exited during startup. The project did not reach a running state.","output":details,"log_path":str(log.relative_to(self.server.workspace))})
                return self._send(200,{"ok":True,"running":True,"pid":proc.pid,"path":str(project.relative_to(self.server.workspace)),"log_path":str(log.relative_to(self.server.workspace))})
            if route == "/v1/godot/stop":
                project=self._path(obj.get("path", ".")); proc=self.server.godot_processes.get(str(project))
                if proc is None or proc.poll() is not None:
                    self.server.godot_processes.pop(str(project), None)
                    return self._send(200,{"ok":True,"running":False,"message":"Project is not running"})
                try: self._signal_runner_process_group(proc.pid,signal.SIGTERM)
                except ProcessLookupError:
                    if proc.poll() is None:
                        return self._send(500,{"ok":False,"running":True,"error":"The isolated Godot process could not be signalled. Reconnect the Codespace and retry Stop."})
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try: self._signal_runner_process_group(proc.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                    try: proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        return self._send(500, {"ok": False, "running": True, "error": "Godot did not exit after the forced stop request."})
                self.server.godot_processes.pop(str(project), None)
                return self._send(200,{"ok":True,"running":False,"message":"Godot project stopped"})
            if route == "/v1/godot/status":
                project=self._path(obj.get("path", ".")); proc=self.server.godot_processes.get(str(project))
                running=proc is not None and proc.poll() is None
                if not running and proc is not None:
                    self.server.godot_processes.pop(str(project), None)
                return self._send(200,{"ok":True,"running":running,"pid":proc.pid if running else 0,"path":str(project.relative_to(self.server.workspace))})
            if route == "/v1/godot/test":
                project=self._path(obj.get("path", "."))
                if not (project/"project.godot").is_file(): return self._send(400,{"error":"The selected folder does not contain project.godot"})
                executable=self.server.godot_executable
                if not (shutil.which(executable) or Path(executable).is_file()): return self._send(503,{"error":"Godot executable not found. Set --godot to the editor executable."})
                state=project/".aoi_studio"; state.mkdir(exist_ok=True); log=state/"test.log"
                try:
                    test_script=project/"run_tests.sh"
                    if test_script.is_file():
                        extra_env={"GODOT":executable}
                        command=["/bin/bash",str(test_script)]
                        timeout_seconds=170
                        test_kind="project test suite"
                    else:
                        extra_env={}
                        command=[executable,"--headless","--editor","--path",str(project),"--quit-after","8","--log-file",str(log)]
                        timeout_seconds=90
                        test_kind="Godot headless import check"
                    run_command, run_env = self._runner_exec(command, extra_env)
                    run=self._run_bounded(run_command,project,timeout_seconds,run_env)
                    merged=(run.stdout or "")+("\nSTDERR:\n"+run.stderr if run.stderr else "")
                    if run.timed_out: merged += "\nGodot verification timed out"
                    log.write_text((test_kind+"\n"+merged)[-100000:],encoding="utf-8")
                    return self._send(200,{"ok":run.returncode==0,"exit_code":run.returncode,"output":(test_kind+"\n"+merged)[-16000:],"test_kind":test_kind,"log_path":str(log.relative_to(self.server.workspace))})
                except OSError as exc:
                    return self._send(500,{"error":"Could not start the isolated Godot verification: "+str(exc)[:240]})
            if route == "/v1/godot/logs":
                project=self._path(obj.get("path", ".")); candidates=[project/".aoi_studio"/"run.log",project/".aoi_studio"/"console.log",project/".aoi_studio"/"test.log"]
                chunks=[]
                for file in candidates:
                    if file.is_file():
                        try: chunks.append("--- "+file.name+" ---\n"+file.read_text(encoding="utf-8",errors="replace")[-30000:])
                        except OSError: pass
                return self._send(200,{"ok":True,"logs":"\n\n".join(chunks)[-60000:] or "No Aoi Studio logs yet."})
            if route == "/v1/godot/capture":
                project=self._path(obj.get("path", "."))
                if not (project/"project.godot").is_file(): return self._send(400,{"error":"The selected folder does not contain project.godot"})
                proc=self.server.godot_processes.get(str(project))
                if proc is None or proc.poll() is not None:
                    if proc is not None: self.server.godot_processes.pop(str(project), None)
                    return self._send(409,{"error":"The Godot project is not running. Launch it before capturing a live preview.","running":False,"pid":0})
                state=project/".aoi_studio"/"screenshots"; state.mkdir(parents=True,exist_ok=True)
                target=state/("capture_%d.png" % int(time.time())); captured=False; method=""
                try:
                    import mss
                    with mss.mss() as shot:
                        monitor=shot.monitors[1]; shot_img=shot.grab(monitor)
                        from PIL import Image
                        Image.frombytes("RGB",shot_img.size,shot_img.rgb).save(target)
                        captured=True; method="mss"
                except Exception: pass
                if not captured:
                    for command in (["grim",str(target)],["scrot",str(target)],["gnome-screenshot","-f",str(target)],["import","-window","root",str(target)]):
                        if shutil.which(command[0]):
                            result=subprocess.run(command,capture_output=True,timeout=12)
                            if result.returncode==0 and target.is_file(): captured=True; method=command[0]; break
                if not captured: return self._send(503,{"error":"No desktop screenshot backend found. Rebuild the cloud workspace so its screenshot support can be installed."})
                if proc.poll() is not None:
                    return self._send(409, {"error":"The Godot project stopped while Aoi was capturing its window. Launch it again before reviewing the preview.", "running":False, "pid":0})
                # Phone previews have a 2 MB transport limit. Downsample and
                # optimise the real capture before deciding it cannot be shown.
                try:
                    from PIL import Image
                    with Image.open(target) as source_image:
                        preview = source_image.convert("RGB")
                        if max(preview.size) > 1280:
                            scale = 1280.0 / max(preview.size)
                            preview = preview.resize((max(1, round(preview.width * scale)), max(1, round(preview.height * scale))), Image.Resampling.LANCZOS)
                        preview.save(target, format="PNG", optimize=True, compress_level=9)
                        while target.stat().st_size > MAX_BINARY and max(preview.size) > 640:
                            scale = 0.82
                            preview = preview.resize((max(1, round(preview.width * scale)), max(1, round(preview.height * scale))), Image.Resampling.LANCZOS)
                            preview.save(target, format="PNG", optimize=True, compress_level=9)
                except Exception:
                    pass
                result={"ok":True,"path":str(target.relative_to(self.server.workspace)),"method":method,"bytes":target.stat().st_size,"running":proc.poll() is None,"pid":proc.pid if proc.poll() is None else 0}
                if target.stat().st_size <= MAX_BINARY:
                    result["image_base64"]=base64.b64encode(target.read_bytes()).decode("ascii")
                else:
                    result["image_base64"]=""
                    result["preview_note"]="Screenshot saved in the cloud workspace; it is larger than the mobile preview limit."
                return self._send(200,result)
            return self._send(404,{"error":"Unknown endpoint"})
        except ValueError as exc: return self._send(400,{"error":str(exc)})
        except Exception as exc: return self._send(500,{"error":str(exc)[:300]})


def create_server(host: str, port: int, token: str, workspace: Path | str, godot_executable: str = "godot",
                  runner_user: str = "", runner_group: str = "") -> ThreadingHTTPServer:
    """Create a fully initialized bridge server for CLI and embedded/test use."""
    server = ThreadingHTTPServer((host, port), Bridge)
    server.token = token
    server.workspace = Path(workspace).expanduser().resolve()
    server.workspace.mkdir(parents=True, exist_ok=True)
    server.godot_executable = godot_executable
    server.runner_user = runner_user
    server.runner_group = runner_group
    server.godot_processes = {}
    server.auth_lock = threading.Lock()
    server.auth_failures = {}
    return server


def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--host",default="127.0.0.1"); parser.add_argument("--port",type=int,default=8765)
    parser.add_argument("--token",default=os.environ.get("AOI_BRIDGE_TOKEN","")); parser.add_argument("--workspace",default=str(Path.home()/"aoi_workspace"))
    parser.add_argument("--godot",default=os.environ.get("GODOT_BIN","godot"),help="Godot editor executable or path")
    parser.add_argument("--runner-user",default="",help="Unprivileged Linux account used for project commands and Godot")
    parser.add_argument("--runner-group",default="",help="Shared workspace group for project files")
    parser.add_argument("--allow-lan",action="store_true",help="Explicitly allow phone pairing over a trusted private LAN")
    parser.add_argument("--allow-public-interface",action="store_true",help="Allow a cloud HTTPS forwarding proxy to reach this token-protected service")
    args=parser.parse_args()
    if len(args.token)<32: raise SystemExit("Set AOI_BRIDGE_TOKEN to a random token of at least 32 characters.")
    if args.allow_public_interface:
        if args.host not in {"0.0.0.0","*"}:
            raise SystemExit("Cloud mode requires --host 0.0.0.0 behind the provider's HTTPS forwarding proxy.")
        if len(args.token)!=64 or not re.fullmatch(r"[0-9a-fA-F]{64}",args.token):
            raise SystemExit("Cloud mode requires a 64-character hexadecimal AOI_BRIDGE_TOKEN.")
        if args.allow_lan:
            raise SystemExit("Choose cloud mode or trusted LAN mode, not both.")
        if not args.runner_user or not args.runner_group:
            raise SystemExit("Cloud mode requires a separate --runner-user and --runner-group. Rebuild the Codespace container.")
    elif args.host not in {"127.0.0.1","localhost"} and not args.allow_lan:
        raise SystemExit("Refusing non-loopback bind. Use --allow-lan on a trusted private network or --allow-public-interface behind HTTPS.")
    if args.allow_lan and args.host not in {"0.0.0.0","*"} and not (args.host.startswith("192.168.") or args.host.startswith("10.") or args.host.startswith("172.")):
        raise SystemExit("For LAN mode use --host 0.0.0.0 or an explicit private LAN IP.")
    if args.runner_user:
        try:
            runner_check = subprocess.run(["sudo", "-n", "-u", args.runner_user, "-g", args.runner_group, "--", "/usr/bin/id", "-u"],
                                          capture_output=True, text=True, timeout=6)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise SystemExit(f"The isolated project runner could not be checked: {exc}. Rebuild the Codespace container.")
        if runner_check.returncode != 0:
            raise SystemExit("The isolated project runner is unavailable. Rebuild the Codespace container before starting the bridge.")
    workspace=Path(args.workspace).expanduser().resolve()
    server=create_server(args.host,args.port,args.token,workspace,args.godot,args.runner_user,args.runner_group)
    if args.allow_lan: print("WARNING: LAN mode exposes workspace files and command execution to devices with the token. Use trusted Wi-Fi and firewall rules.")
    if args.allow_public_interface: print("WARNING: Cloud mode is internet-reachable. Project commands run as a separate unprivileged account; keep the repository private, use a 64-character random secret, and never publish AOI_BRIDGE_TOKEN.")
    print(f"Aoi Linux Bridge listening at http://{args.host}:{args.port}; workspace={workspace}")
    try: server.serve_forever()
    except KeyboardInterrupt: print("\nStopping Aoi Linux Bridge")
    finally: server.server_close()
if __name__ == "__main__": main()
