from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SH = ROOT / "bring-back-gemini.sh"
PS = ROOT / "bring-back-gemini.ps1"
RUN_SH = ROOT / "run.sh"
RUN_PS = ROOT / "run.ps1"
PS_MOCK_POLICY = ROOT / "tests" / "Invoke-WithMockPolicy.ps1"


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.profile = Path(self.temp.name) / "profile"
        self.profile.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def write_state(self, value, version=" 123.45.6 \n"):
        path = self.profile / "Local State"
        path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
        if version is not None:
            (self.profile / "Last Version").write_text(version, encoding="utf-8")
        return path

    def bash_path(self, path):
        """Translate Windows paths for Git Bash while remaining a no-op on POSIX."""
        if os.name == "nt" and shutil.which("cygpath"):
            return subprocess.check_output(["cygpath", "-u", str(path)], text=True).strip()
        return str(path)

    def shell_env(self):
        bindir = Path(self.temp.name) / "bin"
        bindir.mkdir(exist_ok=True)
        python = bindir / "python3"
        uname = bindir / "uname"
        sudo = bindir / "sudo"
        python.write_text(f'#!/bin/sh\nexec "{self.bash_path(sys.executable)}" "$@"\n', encoding="utf-8")
        uname.write_text('#!/bin/sh\necho Linux\n', encoding="utf-8")
        # Tests intentionally never install a real policy. This stand-in only records success.
        sudo.write_text(
            '#!/bin/sh\n'
            'if [ -n "${BBG_TEST_SUDO_LOG:-}" ]; then\n'
            '  printf "%s\\n" "$*" >> "$BBG_TEST_SUDO_LOG"\n'
            '  exec "$@"\n'
            'fi\n'
            'exit 0\n', encoding="utf-8")
        for item in (python, uname, sudo):
            item.chmod(0o755)
        env = os.environ.copy()
        # Git Bash expects a colon-separated POSIX prefix; POSIX does too.
        env["PATH"] = self.bash_path(bindir) + ":" + env.get("PATH", "")
        return env

    def run_sh(self, *extra, env_extra=None):
        git_bash = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git" / "bin" / "bash.exe"
        bash = str(git_bash) if git_bash.exists() else shutil.which("bash")
        if not bash:
            self.skipTest("bash is unavailable")
        env = self.shell_env()
        if env_extra:
            env.update({key: str(value) for key, value in env_extra.items()})
        bindir = self.bash_path(Path(self.temp.name) / "bin")
        command = 'PATH="$1:$PATH"; shift; exec bash "$@"'
        return subprocess.run(
            [bash, "-c", command, "test-wrapper", bindir, self.bash_path(SH),
             "--user-data-dir", self.bash_path(self.profile), *extra],
            text=True, capture_output=True, env=env, timeout=30,
        )

    def powershell_exe(self):
        exe = shutil.which("pwsh") or shutil.which("powershell")
        if not exe:
            self.skipTest("PowerShell is unavailable")
        return exe

    def run_ps(self, *extra):
        return subprocess.run(
            [self.powershell_exe(), "-NoLogo", "-NoProfile", "-File", str(PS),
             "-UserDataDir", str(self.profile), *extra],
            text=True, capture_output=True, timeout=30,
        )

    def run_ps_with_mock_policy(self):
        return subprocess.run(
            [self.powershell_exe(), "-NoLogo", "-NoProfile", "-File", str(PS_MOCK_POLICY),
             "-ScriptPath", str(PS), "-ProfilePath", str(self.profile)],
            text=True, capture_output=True, timeout=30,
        )

    def fixture(self):
        return {
            "is_glic_eligible": False,
            "nested": [
                {"is_glic_eligible": 0, "keep": {"x": 1}},
                {"different_case": {"Is_glic_eligible": False}},
            ],
            "variations_country": "de",
            "variations_permanent_consistency_country": ["old", "ca", "keep"],
            "browser": {"enabled_labs_experiments": ["glic", "glic@2", "keep@1"]},
            "unrelated": {"value": "保留"},
        }

    def assert_core_result(self, state):
        value = json.loads(state.read_text(encoding="utf-8-sig"))
        self.assertIs(value["is_glic_eligible"], True)
        self.assertIs(value["nested"][0]["is_glic_eligible"], True)
        self.assertIs(value["nested"][1]["different_case"]["Is_glic_eligible"], False)
        self.assertEqual(value["variations_country"], "us")
        self.assertEqual(value["variations_permanent_overridden_country"], "us")
        self.assertEqual(value["variations_permanent_consistency_country"], ["123.45.6", "us", "keep"])
        self.assertEqual(value["browser"]["enabled_labs_experiments"], ["keep@1", "glic@1"])
        self.assertEqual(value["unrelated"], {"value": "保留"})

    def test_shell_live_core_without_backup_and_idempotence(self):
        state = self.write_state(self.fixture())
        first = self.run_sh("--no-restart")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assert_core_result(state)
        self.assertEqual(list(self.profile.glob("Local State.backup-*")), [])
        second = self.run_sh("--no-restart")
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(list(self.profile.glob("Local State.backup-*")), [])

    def test_shell_dry_run_does_not_write(self):
        state = self.write_state(self.fixture())
        original = state.read_bytes()
        result = self.run_sh("--dry-run", "--disable-ai-download")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state.read_bytes(), original)
        self.assertEqual(list(self.profile.glob("*.backup-*")), [])
        self.assertIn("dry-run", result.stdout)

    def test_shell_flag_normalization_and_preservation(self):
        state = self.write_state({
            "browser": {"enabled_labs_experiments": [
                "keep@1", "glic", "glic@0", "glic@2",
                "optimization-guide-on-device-model@1",
                "optimization-guide-on-device-model@2",
                "prompt-api-for-gemini-nano", "prompt-api-for-gemini-nano@1",
                "prompt-api-for-gemini-nano@99",
                7, {"keep": True}
            ]}
        }, version=None)
        result = self.run_sh("--disable-ai-download", "--no-restart")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result_value = json.loads(state.read_text(encoding="utf-8"))
        flags = result_value["browser"]["enabled_labs_experiments"]
        self.assertEqual(flags, ["keep@1", 7, {"keep": True}, "glic@1",
                                 "optimization-guide-on-device-model@2",
                                 "prompt-api-for-gemini-nano@2"])
        self.assertNotIn("is_glic_eligible", result_value)
        self.assertEqual(result_value["variations_country"], "us")
        self.assertEqual(result_value["variations_permanent_overridden_country"], "us")

    def test_shell_rejects_malformed_and_unsafe_schema_without_write(self):
        state = self.profile / "Local State"
        for raw in ('{"broken":', '[]', '{"browser":42}', '{"value":NaN}'):
            state.write_text(raw, encoding="utf-8")
            result = self.run_sh("--dry-run")
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(state.read_text(encoding="utf-8"), raw)
            self.assertEqual(list(self.profile.glob("*.backup-*")), [])

    def test_shell_empty_channel_is_usage_error(self):
        state = self.write_state(self.fixture())
        original = state.read_bytes()
        result = self.run_sh("--channel", "", "--dry-run")
        self.assertEqual(result.returncode, 64, result.stdout + result.stderr)
        self.assertEqual(state.read_bytes(), original)

    def test_linux_policy_test_override_never_uses_etc(self):
        state = self.write_state({"browser": {"enabled_labs_experiments": []}})
        policy_dir = Path(self.temp.name) / "isolated-policy"
        policy_dir.mkdir()
        policy_file = policy_dir / "bring-back-gemini.json"
        policy_file.write_text(json.dumps({"UnrelatedPolicy": True}), encoding="utf-8")
        sudo_log = Path(self.temp.name) / "sudo.log"
        result = self.run_sh(
            "--disable-ai-download", "--no-restart",
            env_extra={
                "BRING_BACK_GEMINI_TEST_MODE": "1",
                "BRING_BACK_GEMINI_POLICY_DIR": self.bash_path(policy_dir),
                "BBG_TEST_SUDO_LOG": self.bash_path(sudo_log),
            })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        merged = json.loads(policy_file.read_text(encoding="utf-8"))
        self.assertEqual(merged, {"UnrelatedPolicy": True, "GenAILocalFoundationalModelSettings": 1})
        log = sudo_log.read_text(encoding="utf-8")
        self.assertIn("mkdir -p", log)
        self.assertIn("install -m 0644", log)
        self.assertIn("mv -f", log)
        self.assertNotIn("/etc/", log)
        self.assertTrue(state.exists())

    def test_powershell_live_core_without_backup(self):
        state = self.write_state(self.fixture())
        result = self.run_ps("-NoRestart")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_core_result(state)
        self.assertEqual(list(self.profile.glob("Local State.backup-*")), [])

    def test_powershell_dry_run_and_malformed(self):
        state = self.write_state(self.fixture())
        original = state.read_bytes()
        result = self.run_ps("-DryRun", "-DisableAIDownload")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state.read_bytes(), original)
        for unsafe in ('{"broken":', '[]', '[{"is_glic_eligible":false}]',
                       '42', 'true', 'null', '"scalar"', '{"browser":42}'):
            state.write_text(unsafe, encoding="utf-8")
            malformed = self.run_ps("-DryRun")
            self.assertEqual(malformed.returncode, 1, malformed.stdout + malformed.stderr)
            self.assertEqual(state.read_text(encoding="utf-8"), unsafe)
            self.assertEqual(list(self.profile.glob("*.backup-*")), [])

    def test_powershell_exact_structural_keys_and_flag_normalization(self):
        state = self.write_state({
            "Variations_country": "de",
            "Variations_permanent_consistency_country": ["old", "de"],
            "browser": {"Enabled_labs_experiments": ["wrong-case-preserve"]}
        })
        result = self.run_ps_with_mock_policy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        value = json.loads(state.read_text(encoding="utf-8-sig"))
        self.assertEqual(value["Variations_country"], "de")
        self.assertEqual(value["variations_country"], "us")
        self.assertEqual(value["variations_permanent_overridden_country"], "us")
        self.assertEqual(value["Variations_permanent_consistency_country"], ["old", "de"])
        self.assertEqual(value["browser"]["Enabled_labs_experiments"], ["wrong-case-preserve"])
        self.assertEqual(value["browser"]["enabled_labs_experiments"], [
            "glic@1", "optimization-guide-on-device-model@2", "prompt-api-for-gemini-nano@2"
        ])

        state.write_text(json.dumps({"Browser": {"marker": "preserve"}}), encoding="utf-8")
        second = self.run_ps_with_mock_policy()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        second_value = json.loads(state.read_text(encoding="utf-8-sig"))
        self.assertEqual(second_value["Browser"], {"marker": "preserve"})
        self.assertIn("browser", second_value)
        self.assertEqual(second_value["browser"]["enabled_labs_experiments"], [
            "glic@1", "optimization-guide-on-device-model@2", "prompt-api-for-gemini-nano@2"
        ])

    def test_powershell_bare_flag_normalization_preserves_other_entries(self):
        state = self.write_state({"browser": {"enabled_labs_experiments": [
            "keep@1", "glic@0", "optimization-guide-on-device-model",
            "optimization-guide-on-device-model@7",
            "prompt-api-for-gemini-nano", 9, {"keep": True}
        ]}})
        result = self.run_ps_with_mock_policy()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        flags = json.loads(state.read_text(encoding="utf-8-sig"))["browser"]["enabled_labs_experiments"]
        self.assertEqual(flags, ["keep@1", 9, {"keep": True}, "glic@1",
                                 "optimization-guide-on-device-model@2",
                                 "prompt-api-for-gemini-nano@2"])

    def test_bootstraps_download_pinned_commit_payloads(self):
        sha = "0123456789abcdef0123456789abcdef01234567"
        server_root = Path(self.temp.name) / "server"
        commit_root = server_root / "raw" / sha
        commit_root.mkdir(parents=True)
        for source in (SH, PS):
            shutil.copy2(source, commit_root / source.name)

        class QuietHandler(SimpleHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

        server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            partial(QuietHandler, directory=str(server_root)),
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f"http://127.0.0.1:{server.server_port}"
            original = self.write_state(self.fixture()).read_bytes()

            git_bash = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git" / "bin" / "bash.exe"
            bash = str(git_bash) if git_bash.exists() else shutil.which("bash")
            if bash:
                env = self.shell_env()
                bootstrap_tmp = Path(self.temp.name) / "bootstrap-tmp"
                bootstrap_tmp.mkdir()
                env.update({
                    "BBG_PAYLOAD_COMMIT": sha,
                    "BBG_RAW_ROOT": base + "/raw",
                    "TMPDIR": self.bash_path(bootstrap_tmp),
                })
                bindir = self.bash_path(Path(self.temp.name) / "bin")
                shell_command = [
                    bash, "-c", 'PATH="$1:$PATH"; shift; exec bash "$@"',
                    "test-wrapper", bindir, self.bash_path(RUN_SH),
                    "--user-data-dir", self.bash_path(self.profile), "--dry-run",
                ]
                shell_result = subprocess.run(
                    shell_command, text=True, capture_output=True, env=env, timeout=30,
                )
                self.assertEqual(shell_result.returncode, 0, shell_result.stdout + shell_result.stderr)
                self.assertIn("已下载", shell_result.stdout)
                self.assertEqual(list(bootstrap_tmp.glob("bring-back-gemini-run.*")), [])

            ps_env = os.environ.copy()
            ps_env.update({
                "BBG_PAYLOAD_COMMIT": sha,
                "BBG_RAW_ROOT": base + "/raw",
                "BBG_RUN_PS": str(RUN_PS),
                "BBG_TEST_PROFILE": str(self.profile),
            })
            ps_result = subprocess.run(
                [self.powershell_exe(), "-NoLogo", "-NoProfile", "-Command",
                 '& $env:BBG_RUN_PS -ForwardArguments @("-UserDataDir",$env:BBG_TEST_PROFILE,"-DryRun")'],
                text=True, capture_output=True, env=ps_env, timeout=30,
            )
            self.assertEqual(ps_result.returncode, 0, ps_result.stdout + ps_result.stderr)
            self.assertIn("已下载", ps_result.stdout)
            self.assertEqual((self.profile / "Local State").read_bytes(), original)

            # Canonical full commit IDs are mandatory; abbreviated IDs must be rejected.
            if bash:
                bad_shell_env = env.copy()
                bad_shell_env["BBG_PAYLOAD_COMMIT"] = "a"
                bad_shell = subprocess.run(
                    shell_command, text=True, capture_output=True, env=bad_shell_env, timeout=30,
                )
                self.assertNotEqual(bad_shell.returncode, 0)
                self.assertIn("40", bad_shell.stdout + bad_shell.stderr)
            bad_ps_env = ps_env.copy()
            bad_ps_env["BBG_PAYLOAD_COMMIT"] = "a"
            bad_ps = subprocess.run(
                [self.powershell_exe(), "-NoLogo", "-NoProfile", "-Command",
                 '& $env:BBG_RUN_PS -ForwardArguments @("-UserDataDir",$env:BBG_TEST_PROFILE,"-DryRun")'],
                text=True, capture_output=True, env=bad_ps_env, timeout=30,
            )
            self.assertNotEqual(bad_ps.returncode, 0)
            self.assertIn("40", bad_ps.stdout + bad_ps.stderr)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_concurrency_guards_and_stale_plan_seams_exist(self):
        ps_source = PS.read_text(encoding="utf-8")
        write_loop = ps_source[ps_source.index("foreach ($plan in $changedPlans)"):]
        self.assertIn("$fresh = Convert-LocalState $plan.Path", write_loop)
        self.assertIn("if (-not $fresh.Changed)", write_loop)
        self.assertIn("$fresh.SourceBytes", write_loop)
        self.assertIn("ReadAllBytes($plan.Path)", write_loop)
        self.assertIn("Replace-FileWithoutBackup $temp $plan.Path", write_loop)
        self.assertIn("MoveFileEx", ps_source)
        self.assertNotIn(".backup-", write_loop)
        self.assertNotIn("$plan.Data | ConvertTo-Json", write_loop)
        self.assertNotIn("Get-FileSha256", ps_source)
        self.assertNotIn("SourceHash", ps_source)
        self.assertIn("function Restart-CapturedChrome", ps_source)
        self.assertIn("finally {\n    Restart-CapturedChrome", ps_source)
        self.assertIn("$_.Target.Exes", ps_source)
        sh_source = SH.read_text(encoding="utf-8")
        self.assertIn('if current_file.read() != raw:', sh_source)
        self.assertIn('os.replace(temp, path)', sh_source)
        self.assertIn("grep -q '^CHANGED=0$'", sh_source)
        self.assertNotIn("os.fsync(dfd)", sh_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
