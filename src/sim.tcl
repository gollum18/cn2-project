# Name: sim.tcl
# Created: March 20th, 2019
# Author: Christen Ford
# Purpose: To gather performance metrics on sfqCoDel, CoDel, DRR, and FIFO
#  queueing algorithms.

# get the bb algorithm and speed, as well as the sim time
set bb_alg [lindex $argv 0]
set bb_bw [lindex $argv 1]
set sim_time [lindex $argv 2]

# setup some constants for use later (do not change these please!)
# represents the number of gateway nodes
set gw_num 3
# represents the number of end systems attached to each gateway
set es_num 10

# define lists for the cable down/up, dsl down/up, fiber down/up
set cable_bw_down list 25Mb 50Mb 100Mb
set cable_bw_up list 5Mb 10Mb 10Mb
set dsl_bw_down list 6Mb 12Mb 24Mb
set dsl_bw_up list 1Mb 1Mb 3Mb
set fiber_bw_down list 300Mb 500Mb 1Gb
set fiber_bw_up list 20Mb 30Mb 35Mb

# create a simulator object
set ns [new Simulator]

# turn on general tracing

# define the finish operation
proc finish {} {
    global ns nf
    $ns flush-trace
    close $nf
    # todo: start the analysis script
    exit 0
}

# create the backbone nodes
for {set i 0} {$i < 2} {incr i} {
    set bb_nodes($i) [$ns node]
}

# create the backbone link
if {[string compare $bb_alg "sfq"] == 0} {
    set $bb_alg sfqCoDel
} 
elseif {[string compare $bb_alg "codel"] == 0} {
    set $bb_alg CoDel
} 
elseif {[string compare $bb_alg "drr"] == 0} {
    set $bb_alg DRR
} 
else {
    set $bb_alg DropTail
}
$ns duplex-link $bb_dsl $bb_cable $bb_bw $bb_alg

# create the dsl/cable gateways and their links
# the gateway nodes will always use CoDel and be at 1Gbs
for {set i 0} {$i < $gw_num} {incr i} {
    set dsl_gw($i) [$ns node]
    $ns duplex-link $bb_dsl $dsl_gw($i) 1Gbs CoDel
    set cable_gw($i) [$ns node]
    $ns duplex-link $bb_cable $cable_gw($i) 1Gbs CoDel
}

# create the dsl/cable nodes and their links
for {set i 0} {$i < $gw_num} {incr i} {
    for {set j 0} {$j < $es_num} {incr j} {
        # create the dsl nodes
        set dsl_nodes($i,$j) [$ns node]
        # create the cable nodes
        set cable_nodes($i,$j) [$ns node]
        # generate a random speed for the up and down
        set r_cable expr {int(rand()*3)}
        set r_dsl expr {int(rand()*3)}
        # create the up/down streams for the dsl nodes
        # todo: come up with appropriate delays, maybe randomize the link queue?
        if {$i == 0} {
            $ns simplex-link $dsl_nodes($i,$j) $dsl_gw($i) [lindex $dsl_bw_up $r_dsl]
            $ns simplex-link $dsl_gw($i) $dsl_nodes($i,$j) [lindex $dsl_bw_down $r_dsl]
            $ns simplex-link $cable_nodes($i,$j) $cable_gw($i) [lindex $cable_bw_up $r_cable]
            $ns simplex-link $cable_gw($i) $cable_nodes($i,$j) [lindex $cable_bw_down $r_cable]
        }
        elseif {$i == 1} {
            if {rand() <= 0.5} {
                $ns simplex-link $dsl_nodes($i,$j) $dsl_gw($i) [lindex $dsl_bw_up $r_dsl]
                $ns simplex-link $dsl_gw($i) $dsl_nodes($i,$j) [lindex $dsl_bw_down $r_dsl]
                $ns simplex-link $cable_nodes($i,$j) $cable_gw($i) [lindex $cable_bw_up $r_cable]
                $ns simplex-link $cable_gw($i) $cable_nodes($i,$j) [lindex $cable_bw_down $r_cable]
            } 
            else {
                $ns simplex-link $dsl_nodes($i,$j) $dsl_gw($i) [lindex $fiber_bw_up $r_dsl]
                $ns simplex-link $dsl_gw($i) $dsl_nodes($i,$j) [lindex $fiber_bw_down $r_dsl]
                $ns simplex-link $cable_nodes($i,$j) $cable_gw($i) [lindex $fiber_bw_up $r_cable]
                $ns simplex-link $cable_gw($i) $cable_nodes($i,$j) [lindex $fiber_bw_down $r_cable]
            }
        }
        # create the up/down streams for the cable nodes
        else {
            $ns simplex-link $dsl_nodes($i,$j) $dsl_gw($i) [lindex $fiber_bw_up $r_dsl]
            $ns simplex-link $dsl_gw($i) $dsl_nodes($i,$j) [lindex $fiber_bw_down $r_dsl]
            $ns simplex-link $cable_nodes($i,$j) $cable_gw($i) [lindex $fiber_bw_up $r_cable]
            $ns simplex-link $cable_gw($i) $cable_nodes($i,$j) [lindex $fiber_bw_down $r_cable]
        }
    }
}

# run the simluation
$ns run
