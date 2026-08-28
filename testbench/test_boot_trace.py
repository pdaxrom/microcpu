"""Keep the no-FIS trace isolated, bounded and byte-identical to its EBR image."""
import unittest

import test_hc1200_diag as diagnostic_checks


class BootTraceProject(diagnostic_checks.DiagnosticProject):
    project = "microcomp-boot-trace"
    implementation_dir = "impl1-boot-trace"
    image = "j11_boot_trace"
    ebr = "boot_trace_ebr.v"
    script = "build-boot-trace.tcl"

    def test_trace_is_assembled_without_fis(self):
        board = diagnostic_checks.BOARD
        listing = (board / (self.image + ".lst")).read_text()
        self.assertIn("[boot_trace_state]", listing)
        self.assertIn("[boot_trace_crc_byte]", listing)
        self.assertNotIn("[fis_entry]", listing)
        self.assertIn("[sd_boot]", listing)
        self.assertIn("[arithmetic_shift_combined]", listing)
        self.assertIn("[cpu_swap_register]", listing)
        self.assertIn("[halt_stopped]", listing)


if __name__ == "__main__":
    unittest.main()
