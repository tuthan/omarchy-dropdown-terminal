#!/usr/bin/env python3
"""Deterministic filesystem race regressions; never contact the real compositor."""

import contextlib
import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("binding", ROOT / "bin/omarchy-dropdown-terminal-bind.py")
binding = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(binding)
KEY = "CTRL + GRAVE"
LINE = f'hl.bind("{KEY}", hl.dsp.global("io.github.tuthan.dropdown-terminal:toggle"))'
ORIGINAL = b"-- user config\nuser_setting = true\n"
OUTSIDE = b"-- outside reviewed target\n"


class BindingTransactionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "config"
        self.parent = self.home / "hypr"
        self.parent.mkdir(parents=True)
        self.config = self.parent / "bindings.lua"
        self.config.write_bytes(ORIGINAL)
        self.config.chmod(0o640)
        self.outside = self.root / "outside"
        self.outside.mkdir()
        (self.outside / "bindings.lua").write_bytes(OUTSIDE)
        self.outside_before = self.outside_snapshot()
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(mock.patch.object(binding, "notify"))
        self.reload = self.stack.enter_context(mock.patch.object(binding, "hyprctl",
            return_value=subprocess.CompletedProcess([], 0, b"[]", b"")))

    def outside_snapshot(self):
        return {p.name: (p.stat().st_ino, p.stat().st_mode, p.read_bytes())
                for p in self.outside.iterdir()}

    def assert_outside_untouched(self):
        self.assertEqual(self.outside_snapshot(), self.outside_before)

    def directory(self):
        return self.stack.enter_context(contextlib.closing(binding.ConfigDirectory(self.parent)))

    def mutate(self, directory=None, action="install"):
        return binding.mutate(directory or self.directory(), action, KEY, LINE)

    def swap(self, ancestor=False):
        if ancestor:
            self.home.rename(self.root / "detached-config")
            replacement = self.root / "replacement"
            replacement.mkdir()
            (replacement / "hypr").symlink_to(self.outside, target_is_directory=True)
            self.home.symlink_to(replacement, target_is_directory=True)
        else:
            self.parent.rename(self.home / "detached-hypr")
            self.parent.symlink_to(self.outside, target_is_directory=True)

    def test_install_remove_idempotent_and_exact_backup(self):
        self.assertEqual(self.mutate(), 0)
        self.assertIn(LINE.encode(), self.config.read_bytes())
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)
        backups = list(self.parent.glob("bindings.lua.bak.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), ORIGINAL)
        self.assertEqual(stat.S_IMODE(backups[0].stat().st_mode), 0o640)
        # Release the first transaction's lock before starting another one.
        self.stack.close()
        with mock.patch.object(binding, "notify"), mock.patch.object(binding, "hyprctl", self.reload):
            with contextlib.closing(binding.ConfigDirectory(self.parent)) as directory:
                self.assertEqual(self.mutate(directory), 0)
            self.assertEqual(list(self.parent.glob("bindings.lua.bak.*")), backups)
            with contextlib.closing(binding.ConfigDirectory(self.parent)) as directory:
                self.assertEqual(self.mutate(directory, "remove"), 0)
            removed = self.config.read_bytes()
            self.assertNotIn(LINE.encode(), removed)
            with contextlib.closing(binding.ConfigDirectory(self.parent)) as directory:
                self.assertEqual(self.mutate(directory, "remove"), 0)
            self.assertEqual(self.config.read_bytes(), removed)

    def test_refuses_existing_directory_symlink(self):
        self.swap()
        with self.assertRaises(OSError):
            self.directory()
        self.assert_outside_untouched()

    def test_refuses_existing_ancestor_symlink(self):
        self.swap(ancestor=True)
        with self.assertRaises(OSError):
            self.directory()
        self.assert_outside_untouched()

    def test_does_not_normalize_away_symlinked_components(self):
        (self.home / "link").symlink_to(self.outside, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "must not contain"):
            binding.ConfigDirectory(self.home / "link/../hypr")
        self.assertEqual(self.config.read_bytes(), ORIGINAL)
        self.assert_outside_untouched()

    def test_refuses_leaf_symlink(self):
        self.config.unlink()
        self.config.symlink_to(self.outside / "bindings.lua")
        with self.assertRaises(OSError):
            self.mutate()
        self.assert_outside_untouched()

    def test_refuses_lock_symlink_without_truncation(self):
        (self.parent / binding.LOCK).symlink_to(self.outside / "bindings.lua")
        with self.assertRaises(OSError):
            self.mutate()
        self.assert_outside_untouched()
        self.assertEqual(self.config.read_bytes(), ORIGINAL)

    def test_refuses_fifo_without_blocking(self):
        self.config.unlink()
        os.mkfifo(self.config)
        with self.assertRaisesRegex(RuntimeError, "regular file"):
            self.mutate()

    def test_swap_during_directory_walk(self):
        real_open = os.open
        def raced_open(name, *args, **kwargs):
            if name == "hypr":
                self.swap()
            return real_open(name, *args, **kwargs)
        with mock.patch.object(binding.os, "open", side_effect=raced_open):
            with self.assertRaises(OSError):
                self.directory()
        self.assert_outside_untouched()

    def test_swap_before_read(self):
        directory = self.directory()
        self.swap()
        with self.assertRaises(RuntimeError):
            self.mutate(directory)
        self.assert_outside_untouched()

    def test_swap_before_backup(self):
        directory = self.directory()
        real_stage = directory.stage
        def raced_stage(data, mode, prefix):
            if prefix.startswith("bindings.lua.bak."):
                self.swap(ancestor=True)
            return real_stage(data, mode, prefix)
        with mock.patch.object(directory, "stage", side_effect=raced_stage):
            with self.assertRaises(RuntimeError):
                self.mutate(directory)
        self.assert_outside_untouched()
        self.assertEqual((self.root / "detached-config/hypr/bindings.lua").read_bytes(), ORIGINAL)

    def test_parent_and_ancestor_swap_at_atomic_replace(self):
        for ancestor in (False, True):
            with self.subTest(ancestor=ancestor):
                # Each race needs a fresh filesystem and open directory.
                case = BindingTransactionTests()
                case.setUp()
                try:
                    directory = case.directory()
                    real_replace = os.replace
                    def raced_replace(*args, **kwargs):
                        case.swap(ancestor=ancestor)
                        return real_replace(*args, **kwargs)
                    with mock.patch.object(binding.os, "replace", side_effect=raced_replace):
                        with self.assertRaises(RuntimeError):
                            case.mutate(directory)
                    case.assert_outside_untouched()
                finally:
                    case.doCleanups()

    def test_leaf_swap_after_read_aborts(self):
        directory = self.directory()
        def config_errors():
            self.config.unlink()
            self.config.symlink_to(self.outside / "bindings.lua")
            return []
        with mock.patch.object(binding, "config_errors", side_effect=config_errors):
            with self.assertRaisesRegex(RuntimeError, "bindings.lua changed"):
                self.mutate(directory)
        self.assert_outside_untouched()

    def test_leaf_swap_at_rename_cannot_follow_symlink(self):
        directory = self.directory()
        real_replace = os.replace
        def raced_replace(*args, **kwargs):
            self.config.unlink()
            self.config.symlink_to(self.outside / "bindings.lua")
            return real_replace(*args, **kwargs)
        with mock.patch.object(binding.os, "replace", side_effect=raced_replace):
            self.assertEqual(self.mutate(directory), 0)
        self.assertFalse(self.config.is_symlink())
        self.assert_outside_untouched()

    def test_backup_collision_never_overwrites_symlink(self):
        with mock.patch.object(binding.secrets, "token_hex", return_value="fixed"), \
                mock.patch.object(binding.time, "strftime", return_value="stamp"):
            (self.parent / "bindings.lua.bak.stamp.fixed").symlink_to(self.outside / "bindings.lua")
            with self.assertRaises(FileExistsError):
                self.mutate()
        self.assert_outside_untouched()
        self.assertEqual(self.config.read_bytes(), ORIGINAL)

    def test_rejected_reload_restores_exact_bytes_and_mode(self):
        with mock.patch.object(binding, "config_errors", side_effect=[[], ["new error"]]):
            self.assertEqual(self.mutate(), 1)
        self.assertEqual(self.config.read_bytes(), ORIGINAL)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)

    def test_rejected_reload_removes_new_config(self):
        self.config.unlink()
        with mock.patch.object(binding, "config_errors", side_effect=[[], ["new error"]]):
            self.assertEqual(self.mutate(), 1)
        self.assertFalse(self.config.exists())

    def test_swap_during_reload_aborts_rollback(self):
        calls = 0
        def errors():
            nonlocal calls
            calls += 1
            if calls == 2:
                self.swap()
                return ["new error"]
            return []
        with mock.patch.object(binding, "config_errors", side_effect=errors):
            with self.assertRaises(RuntimeError):
                self.mutate()
        self.assert_outside_untouched()

    def test_swap_at_rollback_rename_cannot_redirect_restore(self):
        real_replace = os.replace
        calls = 0
        def raced_replace(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2:
                self.swap(ancestor=True)
            return real_replace(*args, **kwargs)
        with mock.patch.object(binding.os, "replace", side_effect=raced_replace), \
                mock.patch.object(binding, "config_errors", side_effect=[[], ["new error"]]):
            self.assertEqual(self.mutate(), 1)
        self.assert_outside_untouched()
        self.assertEqual((self.root / "detached-config/hypr/bindings.lua").read_bytes(), ORIGINAL)

    def test_concurrent_edit_during_reload_not_overwritten(self):
        calls = 0
        def errors():
            nonlocal calls
            calls += 1
            if calls == 2:
                self.config.write_bytes(b"-- newer user edit\n")
                return ["new error"]
            return []
        with mock.patch.object(binding, "config_errors", side_effect=errors):
            with self.assertRaisesRegex(RuntimeError, "bindings.lua changed"):
                self.mutate()
        self.assertEqual(self.config.read_bytes(), b"-- newer user edit\n")

    def test_failed_replace_preserves_config_and_cleans_temp(self):
        directory = self.directory()
        with mock.patch.object(binding.os, "replace", side_effect=OSError("rename failed")):
            with self.assertRaises(OSError):
                self.mutate(directory)
        directory.close()
        self.assertEqual(self.config.read_bytes(), ORIGINAL)
        self.assertEqual(list(self.parent.glob(".bindings.lua.dropdown-terminal.*")),
                         [self.parent / binding.LOCK])


if __name__ == "__main__":
    unittest.main()
