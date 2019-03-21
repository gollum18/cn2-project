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
if {string compare $bb_alg "sfq"} {
    set $bb_alg sfqCoDel
} 
elseif {string compare $bb_alg "codel"} {
    set $bb_alg CoDel
} 
elseif {string compare $bb_alg "drr"} {
    set $bb_alg DRR
} 
else {
    set $bb_alg DropTail
}
$ns duplex-link $bb_dsl $bb_cable $bb_bw $bb_alg

# create the dsl/cable gateways and their links
for {set i 0} {$i < $gw_num} {incr i} {
    set dsl_gw($i) [$ns node]
    $ns duplex-link $bb_dsl $dsl_gw($i) 1Gbs CoDel

    set cable_gw($i) [$ns node]
    $ns duplex-link $bb_cable $cable_gw($i) 1Gbs CoDel
}

# create the dsl/cable nodes and their links
for {set i 0} {$i < $gw_node} {incr i} {
    for {set j 0} {$j < $es_num} {incr j} {
        set dsl_nodes($i,$j) [$ns node]
        set cable_nodes($i,$j) [$ns node]
    }
}

# run the simluation
$ns run
