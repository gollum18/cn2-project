# Name: run.tcl
# Created: March 20th, 2019
# Author: Christen Ford
# Purpose: Bootstrap script that fires off sim.tcl with the appropriate 
#  parameters.

# set sim time to 300 seconds
set sim_time 300

# create a speed list
set bw_list [list 1Gbs 10Gbs 25Gbs]

# create a algorithm list
set alg_list [list "sfq" "codel" "drr" "fifo"]

# execute the simulation script
for {set bw 0} {$bw < [llength $bw_list]} {incr bw} {
    for {set alg 0} {$alg < [llength $alg_list]} {incr alg}  {
        exec sim.tcl [lindex $alg_list $alg] [lindex $bw_list $bw] $sim_time
    }
}
