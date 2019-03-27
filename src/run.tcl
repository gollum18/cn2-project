set bw_list [list 1Gb 2.5Gb 10b]
set sched_list [list DropTail DRR CoDel sfqCoDel]

for {set i 0} {$i < [llength $bw_list]} {incr i} {
    for {set j 0} {$j < [llength $sched_list]} {incr j} {
        exec ns sim.tcl [lindex $bw_list $i] [lindex $sched_list $j] 16
    }
}
