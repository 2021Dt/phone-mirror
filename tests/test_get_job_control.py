"""Run with python3 on macOS. No GUI, phone or user download folder is needed."""

import os
from pathlib import Path
import pty
import subprocess
import tempfile
import time
import unittest


class GetJobControlTest(unittest.TestCase):
    def test_up_open_folder_and_cancel_in_background(self):
        source = Path(__file__).resolve().parents[1] / "phone-transfer.zsh"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            downloads = root / "downloads"
            downloads.mkdir()
            trace = root / "visited"
            picker = root / "picker"
            picker.write_text(
                '#!/bin/zsh -f\n'
                '[[ $# == 5 && $1 == get ]] || exit 2\n'
                'print -r -- "picker opened" >> "$VISITED"\n'
                'for dir in /sdcard/Download/ /sdcard/ /sdcard/Projects/; do\n'
                '  result=$(/bin/zsh -f "$4" list "$2" "$3" "$dir") || exit 3\n'
                '  [[ $result == $\'DProjects\\0\' ]] || exit 4\n'
                '  print -r -- "$dir" >> "$VISITED"\n'
                'done\n'
            )
            adb = root / "adb"
            adb.write_text("#!/bin/sh\nprintf 'DProjects\\000'\n")
            adb.chmod(0o700)
            picker.chmod(0o700)
            entry = '/usr/bin/osascript -l JavaScript "$picker"'
            worker = root / "phone-transfer.zsh"
            program = source.read_text()
            self.assertIn(entry, program)
            worker.write_text(program.replace(entry, '"$TEST_PICKER"'))
            environment = dict(os.environ, TEST_PICKER=str(picker), VISITED=str(trace),
                               PHONE_WINDOW_FEEDBACK="1", XDG_CONFIG_HOME=tmp)

            # Like NSTask in a mirror launched from Terminal, the worker has a
            # controlling tty but a different process group from its foreground job.
            supervisor, master = pty.fork()
            if supervisor == 0:
                child = subprocess.Popen(
                    ["/bin/zsh", "-f", str(worker), "get", str(adb), "fixture", "", str(downloads)],
                    stdin=subprocess.DEVNULL, env=environment, preexec_fn=os.setpgrp,
                )
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    pid, status = os.waitpid(child.pid, os.WUNTRACED | os.WNOHANG)
                    if pid and os.WIFEXITED(status):
                        os._exit(os.WEXITSTATUS(status))
                    if pid and os.WIFSIGNALED(status):
                        os._exit(128 + os.WTERMSIG(status))
                    if pid:
                        break
                    time.sleep(0.02)
                child.kill()
                os.waitpid(child.pid, 0)
                os._exit(1)
            try:
                _, status = os.waitpid(supervisor, 0)
            finally:
                os.close(master)
            self.assertEqual(status, 0, "file picker stopped, timed out, or failed")
            self.assertEqual(trace.read_text().splitlines(),
                             ["picker opened", "/sdcard/Download/", "/sdcard/", "/sdcard/Projects/"])
            self.assertEqual(list(downloads.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
