"""Diagnostic image/project identity and export guards, without Diamond."""
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import unittest

import test_hc1200_sd_project as board_checks

BOARD = board_checks.BOARD


class DiagnosticProject(unittest.TestCase):
    def test_same_hardware_different_firmware(self):
        production = board_checks.implementation("microcomp.ldf")
        diagnostic = board_checks.implementation("microcomp-diag.ldf")
        self.assertEqual(diagnostic.find("Options").get("def_top"), "ucode_sd_microcomp")
        self.assertEqual(board_checks.sources(diagnostic, "Verilog"),
                         board_checks.sources(production, "Verilog") - {"sd_urom_ebr.v"}
                         | {"sd_fram_diag_ebr.v"})
        self.assertEqual(board_checks.sources(diagnostic, "Logic Preference"), {"sd.lpf"})
        self.assertEqual(board_checks.sources(diagnostic, "Programming Project File"), set())
        self.assertEqual(diagnostic.get("dir"), "impl1-diag")
        self.assertNotEqual(diagnostic.get("dir"), production.get("dir"))
        for name in board_checks.sources(diagnostic, "Verilog"):
            self.assertTrue((BOARD / name).is_file(), name)

    def test_mem_and_ebr_pack_the_assembled_source(self):
        binary = (BOARD / "sd_fram_diag.bin").read_bytes()
        self.assertEqual(len(binary) % 2, 0)
        self.assertLessEqual(len(binary), 3520 * 2)
        code = list(struct.unpack(f"<{len(binary) // 2}H", binary))
        expected = code + [0x00b0] * (3520 - len(code)) + [0] * 64
        actual = [int(word, 16) for word in (BOARD / "sd_fram_diag.mem").read_text().split()[1:]]
        self.assertEqual(actual, expected)
        rows = re.findall(r'\.INITVAL_[0-9A-F]{2}\("0x([0-9A-F]+)"\)',
                          (BOARD / "sd_fram_diag_ebr.v").read_text())
        ebr = [(int(row, 16) >> (20 * i)) & 0xfffff for row in rows for i in range(16)]
        self.assertEqual(ebr, expected)

    def test_export_requires_successful_build_and_timing(self):
        tclsh = shutil.which("tclsh")
        self.assertIsNotNone(tclsh)
        harness = r'''
proc prj_project {args} { puts "PROJECT $args" }
proc prj_run {args} {
    puts "RUN $args"
    if {[lindex $args 0] eq $::env(TEST_FAIL_STAGE)} { error "injected failure" }
}
rename open real_open
proc open {path mode} {
    if {$path ne "impl1-diag/microcomp-diag_impl1.twr" || $mode ne "r"} {
        error "unexpected report access: $path $mode"
    }
    return [real_open $::env(TEST_TRACE) r]
}
source $::env(TEST_SCRIPT)
'''
        with tempfile.TemporaryDirectory(prefix="microcpu-diag-") as directory:
            report = Path(directory) / "timing.twr"
            cases = [("Cumulative negative slack: 0.000\n" * 2, "", True),
                     ("Cumulative negative slack: 0.000\nCumulative negative slack: -0.1\n", "", False),
                     ("No timing summary", "", False)]
            cases += [("Cumulative negative slack: 0.000\n" * 2, stage, False)
                      for stage in ("Synthesis", "Translate", "Map", "PAR")]
            for timing, failed_stage, success in cases:
                with self.subTest(timing=timing, stage=failed_stage):
                    report.write_text(timing)
                    env = dict(os.environ, TEST_TRACE=str(report), TEST_FAIL_STAGE=failed_stage,
                               TEST_SCRIPT=str(BOARD / "build-diag.tcl"))
                    result = subprocess.run([tclsh], input=harness, text=True, capture_output=True,
                                            env=env, timeout=10, check=False)
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    self.assertEqual("RUN Export -impl impl1 -task Jedecgen" in result.stdout, success)
                    self.assertIn("PROJECT open microcomp-diag.ldf", result.stdout)
                    self.assertNotIn("Program", result.stdout)


if __name__ == "__main__":
    unittest.main()
