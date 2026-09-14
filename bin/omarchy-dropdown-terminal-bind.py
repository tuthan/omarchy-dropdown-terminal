#!/usr/bin/env python3
"""Edit bindings through a pinned directory, including backup and rollback."""

import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import time

BEGIN = "-- BEGIN Dropdown Terminal binding"
END = "-- END Dropdown Terminal binding"
NAME = "bindings.lua"
LOCK = ".bindings.lua.dropdown-terminal.lock"
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK


def identity(info):
    return info.st_dev, info.st_ino


def revision(info):
    return identity(info), info.st_size, info.st_mtime_ns, info.st_ctime_ns


class ConfigDirectory:
    def __init__(self, path, create=False):
        self.fds = []
        self.chain = []
        self.pending = set()
        try:
            # Walk from root without resolving symlinks. Every ancestor stays
            # open, so neither a lookup nor a later mutation can follow a swap.
            path = Path(path)
            # Do not lexically collapse '..': doing so could hide a symlinked
            # component and select a different target than filesystem lookup.
            if ".." in path.parts:
                raise RuntimeError("config directory must not contain '..'")
            if not path.is_absolute():
                path = Path.cwd() / path
            self.fd = os.open(path.anchor, DIR_FLAGS)
            self.fds.append(self.fd)
            for part in path.parts[1:]:
                parent = self.fd
                try:
                    child = os.open(part, DIR_FLAGS, dir_fd=parent)
                except FileNotFoundError:
                    if not create:
                        raise
                    self.verify_directory()
                    try:
                        os.mkdir(part, 0o700, dir_fd=parent)
                    except FileExistsError:
                        pass
                    child = os.open(part, DIR_FLAGS, dir_fd=parent)
                self.fds.append(child)
                self.chain.append((parent, part, identity(os.fstat(child))))
                self.fd = child
            self.verify_directory()
        except BaseException:
            self.close()
            raise

    def close(self):
        for name in self.pending:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(name, dir_fd=self.fd)
        self.pending.clear()
        for fd in reversed(self.fds):
            os.close(fd)
        self.fds.clear()

    def verify_directory(self):
        for parent, name, expected in self.chain:
            current = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if not stat.S_ISDIR(current.st_mode) or identity(current) != expected:
                raise RuntimeError("config directory changed; review the target again")

    def lock(self):
        fd = os.open(LOCK, os.O_RDWR | os.O_CREAT | FILE_FLAGS, 0o600, dir_fd=self.fd)
        self.fds.append(fd)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise RuntimeError("unsafe binding lock file")
        deadline = time.monotonic() + 3
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("timed out waiting for binding lock")
                time.sleep(0.05)
        self.verify_directory()
        if identity(os.stat(LOCK, dir_fd=self.fd, follow_symlinks=False)) != identity(info):
            raise RuntimeError("binding lock changed")

    def read(self):
        try:
            fd = os.open(NAME, os.O_RDONLY | FILE_FLAGS, dir_fd=self.fd)
        except FileNotFoundError:
            return b"", None
        with os.fdopen(fd, "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise RuntimeError("bindings.lua must be a regular file")
            data = source.read()
            if revision(os.fstat(source.fileno())) != revision(info):
                raise RuntimeError("bindings.lua changed while reading")
        return data, info

    def verify(self, expected):
        self.verify_directory()
        try:
            current = os.stat(NAME, dir_fd=self.fd, follow_symlinks=False)
        except FileNotFoundError:
            current = None
        if ((current is None) != (expected is None)
                or current is not None and revision(current) != revision(expected)):
            raise RuntimeError("bindings.lua changed; review the target again")

    def stage(self, data, mode, prefix):
        # O_EXCL prevents existing files/symlinks (including backup names) from
        # being overwritten. All writes use the newly opened descriptor.
        name = prefix + secrets.token_hex(12)
        fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | FILE_FLAGS,
                     0o600, dir_fd=self.fd)
        self.pending.add(name)
        with os.fdopen(fd, "wb") as target:
            target.write(data)
            target.flush()
            os.fchmod(target.fileno(), mode)
            os.fsync(target.fileno())
            info = os.fstat(target.fileno())
        return name, info

    def replace(self, name, staged, expected):
        self.verify(expected)
        if revision(os.stat(name, dir_fd=self.fd, follow_symlinks=False)) != revision(staged):
            raise RuntimeError("staged binding file changed")
        # A swap after verification still cannot redirect either operand: both
        # are relative to the same open directory, never the original pathname.
        os.replace(name, NAME, src_dir_fd=self.fd, dst_dir_fd=self.fd)
        self.pending.remove(name)
        os.fsync(self.fd)
        installed = os.stat(NAME, dir_fd=self.fd, follow_symlinks=False)
        if identity(installed) != identity(staged):
            raise RuntimeError("bindings.lua changed during replacement")
        return installed


def notify(message):
    try:
        subprocess.run(["notify-send", "Dropdown Terminal", message],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except OSError:
        pass


def hyprctl(*args):
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, check=False)
    except OSError:
        return None


def config_errors():
    result = hyprctl("configerrors", "-j")
    try:
        errors = json.loads(result.stdout) if result and result.returncode == 0 else []
        return errors if isinstance(errors, list) else []
    except (ValueError, UnicodeError):
        return []


def canonical(key):
    return re.sub(r"\s+", "", re.sub(r"\s*[+,]\s*", "+", key.upper())).replace("GRAVE", "CODE:41")


def conflicts(lines, line, key):
    result = []
    for number, text in enumerate(lines, 1):
        if text == line or re.match(r"\s*--", text):
            continue
        match = re.search(r'hl\.bind\("([^"]*)"', text)
        found = match[1] if match else ""
        if not match and re.match(r"\s*bind\s*=", text):
            parts = re.sub(r"^\s*bind\s*=\s*", "", text).split(",")
            if len(parts) >= 2:
                found = parts[0] + " + " + parts[1]
        if canonical(found) == canonical(key):
            result.append({"lineNumber": number, "text": text})
    return result


def rewrite(lines, line, action):
    output = []
    inside = False
    begins = ends = 0
    for text in lines:
        if text == BEGIN:
            begins += 1
            if inside or begins > 1:
                raise RuntimeError("malformed managed binding block")
            inside = True
        elif text == END:
            ends += 1
            if not inside or ends > 1:
                raise RuntimeError("malformed managed binding block")
            inside = False
        elif not inside and not (action == "remove" and text == line):
            output.append(text)
    if inside:
        raise RuntimeError("malformed managed binding block")
    if action != "remove":
        output.extend(["", BEGIN, line, END])
    return ("\n".join(output) + ("\n" if output else "")).encode("utf-8", "surrogateescape")


def mutate(directory, action, key, line):
    directory.lock()
    original, info = directory.read()
    lines = original.decode("utf-8", "surrogateescape").split("\n")
    if lines[-1] == "":
        lines.pop()
    if action == "remove" and not any("io.github.tuthan.dropdown-terminal:toggle" in text for text in lines):
        return 0
    updated = rewrite(lines, line, action)
    if action != "remove":
        if line in lines:
            notify(f"{key} is already bound")
            return 0
        if action == "install" and conflicts(lines, line, key):
            raise RuntimeError(f"{key} is already used; review the conflict before installing")
    before = config_errors()
    directory.verify(info)
    mode = stat.S_IMODE(info.st_mode) if info else 0o644
    temp, staged = directory.stage(updated, mode, ".bindings.lua.dropdown-terminal.")
    if info:
        directory.verify(info)
        backup, _ = directory.stage(original, mode, NAME + ".bak." + time.strftime("%Y%m%d%H%M%S") + ".")
        directory.pending.remove(backup)
    installed = directory.replace(temp, staged, info)
    directory.verify(installed)
    result = hyprctl("reload")
    if result is None or result.returncode:
        notify("Binding saved; reload Hyprland manually")
        return 1
    if any(error not in before for error in config_errors()):
        # Restore our snapshot, never reopen a backup by an untrusted pathname.
        # Refuse to overwrite another writer's changes during reload.
        directory.verify(installed)
        if info:
            temp, staged = directory.stage(original, mode, ".bindings.lua.dropdown-terminal.")
            directory.replace(temp, staged, installed)
        else:
            directory.verify(installed)
            os.unlink(NAME, dir_fd=directory.fd)
            os.fsync(directory.fd)
        hyprctl("reload")
        notify("Hyprland rejected the binding; changes were reverted")
        return 1
    directory.verify(installed)
    notify("Removed the Dropdown Terminal binding" if action == "remove" else f"Bound {key}")
    return 0


def main(argv):
    action = argv[0] if argv else "install"
    key = argv[1] if len(argv) > 1 else "CTRL + GRAVE"
    if not key or len(key) > 80 or not re.fullmatch(r"[A-Za-z0-9_:+,\s-]+", key, re.ASCII):
        print(f"Dropdown Terminal: invalid keybinding: {key}", file=sys.stderr)
        return 2
    if action not in ("status", "install", "install-force", "remove"):
        print(f"Dropdown Terminal: unknown action: {action}", file=sys.stderr)
        return 2
    config = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "hypr", NAME)
    line = f'hl.bind("{key}", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))'
    try:
        try:
            directory = ConfigDirectory(os.path.dirname(config), create=action.startswith("install"))
        except FileNotFoundError:
            if action == "remove":
                return 0
            if action != "status":
                raise
            directory = None
        if action == "status":
            with contextlib.closing(directory) if directory else contextlib.nullcontext():
                data, info = directory.read() if directory else (b"", None)
                if directory:
                    directory.verify(info)
                lines = data.decode("utf-8", "surrogateescape").splitlines()
                found = conflicts(lines, line, key)
                print(json.dumps(dict(version=1, available=True, supported=True,
                                      installed=line in lines, config=config, keybinding=key,
                                      line=line, conflicts=found, conflictCount=len(found))))
                return 0
        with contextlib.closing(directory):
            return mutate(directory, action, key, line)
    except (OSError, RuntimeError) as error:
        print(f"Dropdown Terminal: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
