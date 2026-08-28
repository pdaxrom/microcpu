"""Board project/pin/ROM consistency and build-script guards; no Diamond run."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "boards/hc1200-microcomp"


def implementation(name):
    project = ET.parse(BOARD / name).getroot()
    return next(impl for impl in project.findall("Implementation")
                if impl.get("title") == project.get("default_implementation"))


def sources(impl, kind):
    return {src.get("name") for src in impl.findall("Source")
            if src.get("type") == kind and src.get("excluded") != "TRUE"}


def pins(name):
    return dict(re.findall(r'LOCATE COMP "([^"]+)" SITE "([^"]+)"',
                           (BOARD / name).read_text()))


class BoardProject(unittest.TestCase):
    def test_default_uses_complete_sd_design(self):
        main = implementation("microcomp.ldf")
        sd = implementation("microcomp-sd.ldf")
        self.assertEqual(main.find("Options").get("def_top"), "ucode_sd_microcomp")
        self.assertEqual(sources(main, "Verilog"), sources(sd, "Verilog"))
        self.assertIn("sd_urom_ebr.v", sources(main, "Verilog"))
        self.assertEqual(sources(main, "Logic Preference"), {"sd.lpf"})
        self.assertEqual(main.get("dir"), "impl1-sdboot")
        self.assertEqual(sources(main, "Programming Project File"), set())
        for name in sources(main, "Verilog"):
            self.assertTrue((BOARD / name).is_file(), name)

    def test_preserved_original_project(self):
        old = implementation("microcomp-original.ldf")
        self.assertEqual(old.find("Options").get("def_top"), "demo")
        self.assertIn("../../rtl/cpu.v", sources(old, "Verilog"))
        self.assertIn("microcomp.v", sources(old, "Verilog"))
        self.assertEqual(sources(old, "Logic Preference"), {"microcomp.lpf"})
        self.assertEqual(sources(old, "Programming Project File"), set())
        self.assertNotEqual(old.get("dir"), implementation("microcomp.ldf").get("dir"))
        for name in ("microcomp.ldf", "microcomp-original.ldf"):
            strategy = ET.parse(BOARD / name).getroot().find("Strategy").get("file")
            self.assertTrue((BOARD / strategy).is_file(), strategy)

    def test_uart_and_spi_pinout(self):
        original, sd = pins("microcomp.lpf"), pins("sd.lpf")
        self.assertEqual({key: sd[key] for key in ("rx", "tx")},
                         {"rx": "PT15D", "tx": "PT17D"})
        for key in ("rx", "tx", "res", "gpio_miso", "gpio_mosi", "gpio_msck", "gpio_mcs"):
            self.assertEqual(sd[key], original[key], key)
        for signal, gpio in zip(("sd_cs_n", "sd_mosi", "sd_sck", "sd_miso"),
                                ("gpio[0]", "gpio[1]", "gpio[2]", "gpio[3]")):
            self.assertEqual(sd[signal], original[gpio])
            self.assertNotIn(gpio, sd)  # no second port placed at the same site
        self.assertEqual(len(sd), len(set(sd.values())))

    def test_sd_preserves_all_original_constraints(self):
        # SD takes over exactly the four external GPIO pads. Preserve every
        # other LOCATE, IOBUF/pull mode and SYSCONFIG setting verbatim.
        expected = (BOARD / "microcomp.lpf").read_text()
        for index, signal in enumerate(("sd_cs_n", "sd_mosi", "sd_sck", "sd_miso")):
            expected = expected.replace(f'"gpio[{index}]"', f'"{signal}"')
        self.assertEqual((BOARD / "sd.lpf").read_text(), expected)

    def test_sd_top_ports_match_pin_constraints(self):
        # This board uses a simple ANSI header with decimal bus bounds. Check
        # every bit, including unused keyboard inputs, and reject extra GPIOs
        # that would leave the placer free to assign unexpected package pads.
        header = (BOARD / "sd_microcomp.v").read_text().split("\n);", 1)[0]
        declarations = re.findall(
            r"\b(?:input|output|inout)\s+wire\s+(?:\[(\d+):(\d+)\]\s+)?([^\n]+)", header)
        actual = []
        for high, low, names in declarations:
            for name in names.rstrip(",").split(","):
                name = name.strip()
                self.assertRegex(name, r"^[a-zA-Z_][a-zA-Z0-9_]*$")
                if high:
                    actual.extend(f"{name}[{bit}]" for bit in
                                  range(min(int(high), int(low)), max(int(high), int(low)) + 1))
                else:
                    actual.append(name)
        self.assertCountEqual(actual, pins("sd.lpf"))

    def test_board_rom_matches_autoboot_and_ebr(self):
        mem = BOARD / "j11_sd.mem"
        self.assertEqual(mem.read_bytes(), (ROOT / "testbench/build/j11_sd_boot.words").read_bytes())
        words = [int(word, 16) for word in mem.read_text().split()[1:]]
        rows = re.findall(r'\.INITVAL_[0-9A-F]{2}\("0x([0-9A-F]+)"\)',
                          (BOARD / "sd_urom_ebr.v").read_text())
        actual = [(int(row, 16) >> (20 * i)) & 0xfffff for row in rows for i in range(16)]
        self.assertEqual(actual, words)
        self.assertEqual(len(words), 3584)
        self.assertEqual(words[-64:], [0] * 64)

    def test_build_script_exports_only_after_passing_timing(self):
        tclsh = shutil.which("tclsh")
        self.assertIsNotNone(tclsh, "tclsh is required to check the build script without Diamond")
        # Only the Diamond command names and report input are mocked. The real
        # build script runs unchanged, including catch/exit and timing gates.
        harness = r'''
proc prj_project {args} { puts "PROJECT $args" }
proc prj_run {args} {
    puts "RUN $args"
    if {[lindex $args 0] eq $::env(TEST_FAIL_STAGE)} { error "injected tool failure" }
}
rename open real_open
proc open {path mode} {
    if {$path ne "impl1-sdboot/microcomp_impl1.twr" || $mode ne "r"} {
        error "unexpected report path or write: $path $mode"
    }
    return [real_open $::env(TEST_TRACE) r]
}
source $::env(TEST_SCRIPT)
'''
        with tempfile.TemporaryDirectory(prefix="microcpu-project-") as directory:
            report = Path(directory) / "timing.twr"
            cases = [("Cumulative negative slack: 0.000\n" * 2, "", True),
                     ("Cumulative negative slack: 0.000\nCumulative negative slack: -0.1\n", "", False),
                     ("No timing summary", "", False),
                     ("Cumulative negative slack: 0.000\n", "Synthesis", False)]
            for timing, failed_stage, success in cases:
                with self.subTest(timing=timing, failed_stage=failed_stage):
                    report.write_text(timing)
                    env = dict(os.environ, TEST_TRACE=str(report),
                               TEST_SCRIPT=str(BOARD / "build-microcomp.tcl"), TEST_FAIL_STAGE=failed_stage)
                    result = subprocess.run([tclsh], input=harness, text=True, capture_output=True,
                                            env=env, timeout=10, check=False)
                    self.assertEqual(result.returncode == 0, success, result.stderr)
                    self.assertEqual("RUN Export -impl impl1 -task Jedecgen" in result.stdout, success)
                    self.assertIn("PROJECT open microcomp.ldf", result.stdout)
                    self.assertNotIn("Program", result.stdout)


if __name__ == "__main__":
    unittest.main()
