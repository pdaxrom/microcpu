# Build/export ONLY. Never erase/program a board or write an SD card.
cd [file dirname [file normalize [info script]]]
if {[catch {
    prj_project open microcomp-diag.ldf
    prj_run Synthesis -impl impl1
    prj_run Translate -impl impl1
    prj_run Map -impl impl1
    prj_run PAR -impl impl1
    prj_run PAR -impl impl1 -task PARTrace
    set report [open impl1-diag/microcomp-diag_impl1.twr r]
    set timing [read $report]
    close $report
    set slacks [regexp -all -inline {Cumulative negative slack: (-?[0-9.]+)} $timing]
    if {[llength $slacks] == 0} { error "No timing summary in TRACE report" }
    foreach {match slack} $slacks {
        if {$slack != 0} { error "Timing failed: cumulative negative slack $slack" }
    }
    prj_run Export -impl impl1 -task Jedecgen
    prj_project close
} message]} {
    puts stderr "HC1200 diagnostic build failed: $message"
    exit 1
}
exit 0
