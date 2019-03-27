# Name: sim.tcl
# Since: 20/03/2019
# Author: Christen Ford
# Description: This script simulates a network with a triangular backbone structure, where 
#   each backbone node represents either a dsl, cable, or fiber provider. I have tried to 
#   make this as realistic as possible as it is to serve as a test suite for CoDel and 
#   sfqCoDel within the confines of Network Simulator 2. Calling this script require that you pass
#   in three parameters.
#
#   Each traffic agent will be randomly linked to a traffic sink either within its own network, 
#   or within another providers network. Network links will always use a random scheduler at the 
#   provider end and will have CoDel as the scheduler at the client end. Link parameters such
#   as delay and bandwidth should be approximated to real-life conditions exhibited by the 
#   various mediums the networks represent. 
#
#   This script can be called directly, but for the sake of not having to do that, I have created
#   a secondary script alongside this one. 'run.tcl' can be invoked by calling either tclsh or 
#   ns on it.
#
#   To directly invoke this script, pass it along with the parameters it expects to either tclsh
#   or ns.
#
# Parameters:
#   bandwidth: The bandwidth of each backbone link.
#   scheduler: The packet scheduler to use for each backbone node.
#       note: Must be one of {CoDel, sfqCoDel, DRR, DropTail}
#   nodes: The number of nodes on each provider network.
#       note: Must be greater than or equal to 1.
# The script runs for a predefined amount of time declared at the top of this script.

# List of things that need done still:
# TODO: Make network generation a callable function so I don't have to repeat everything thrice.
# TODO: Fiddle with the parameters on the agents so they aren't all the same.
# TODO: Figure out a simulation time to generate files of sufficient size for analysis.
# TODO: Aptly document each function in the script so people know what they do.
# TODO: Demarcate sections of the script to make it easier to read.
# TODO: Thoughroughly test this script.
# TODO: Schedule traffic to start and stop at random intervals.
# TODO: Maybe consider scheduling backbone link failures?

set sim_time 300

# returns a 'random' item from a list
proc choice {items} {
    return lindex $items expr {int(rand()*{llength items})}
}

# determine a random delay within the range [min, max]
proc delay {min max} {
    # set the min to 1 if it is less than 1
    if {$min < 0} {
        set $min 0
    }
    # do the same for max
    if {$max < 0} {
        set $max 0
    }
    # invert min and max if the user gave a higher min than max value
    if ($min > $max) {
        set temp $min
        set $min $max
        set $max $temp
    }
    # check if they are equal, I don't want that
    if ($min == $max) {
        set $max [expr $max+1]
    }
    # taken from: http://code.activestate.com/recipes/186512-generating-random-intergers-within-a-range-of-max-/
    return [expr int(rand()*($max-$min+1)) + $min] 
}

# make sure the user supplied bandwidth and a scheduler for the 
# backbone link, print usage and error out if they did not
if {$argc < 3} { 
    puts "usage: ns sim.tcl \[bandwidth\] \[scheduler\] \[nodes\]"
    exit -1
}

# create a new simulator
set ns [new Simulator]

# define three colors for the the different networks
#   1 = dsl, 2 = cable, 3 = fiber
$ns color 1 Blue
$ns color 2 Red
$ns Color 3 Green

# get the bandwidth and scheduler
set bb_bw [lindex $argv 0]
set bb_sched [lindex $argv 1]
set num_nodes [lindex $argv 2]

# create the directory for node trace output
file mkdir ntrace

# get the filename of this execution
set tracefile [format "ntrace/%s_%s_%d.nam" $bb_bw $bb_sched $bb_nodes]

# turn on tracing
set nf [open $ntrace w]
$ns namtrace-all $nf

# define a finish operation
proc finish {} {
    global ns nf nq tracefile
    $ns flush-trace
    # close the queue traces and NAM trace file
    for {set i 0} {$i < [array size $nq]} {incr i} {
        close $nq($i)
    }
    close $nf
    # execute NAM and the analysis program
    exec name $tracefile &
    exec python3 analysis.py &
    exit 0
}

# create the link parameters
set schedulers [list DropTail DRR CoDel sfqCoDel]

# create the dsl parameters
set dsl_up [list 1Mb 2.4Mb 2.4Mb]
set dsl_down [list 8Mb 16Mb 24Mb]

# create the cable parameters
set cable_up [list 10Mb 15Mb 30Mb]
set cable_down [list 50Mb 100Mb 300Mb]

# create the fiber parameters
set fiber_up [list 50Mb 100Mb]
set fiber_down [list 300Mb 1Gb]

# create the backbone nodes
set bb_dsl [$ns node]
set bb_cable [$ns node]
set bb_fiber [$ns node]

# create the directory for queue trace output
file mkdir qtrace

# create the backbone links
$ns duplex-link $bb_dsl $bb_cable $bb_bw 50ms $bb_sched
$ns duplex-link $bb_dsl $bb_fiber $bb_bw 50ms $bb_sched
$ns duplex-link $bb_cable $bb_fiber $bb_bw 50ms $bb_sched

# setup queue monitoring on the links so we can get the average length
$ns monitor-queue $bb_dsl $bb_cable
$ns monitor-queue $bb_dsl $bb_fiber
$ns monitor-queue $bb_cable $bb_fiber

# turn on tracing on the backbone links
$ns trace-queue $bb_dsl $bb_cable nq(0)
$ns trace-queue $bb_dsl $bb_fiber nq(1)
$ns trace-queue $bb_cable $bb_fiber nq(2)

# Note: end system links will just use the default linux scheduler, CoDel
#   technically, Linux uses fq_codel by default, but I don't have it available
#   While provider side of the link will use a random scheduler

# create lists for tcp
list tcp_agents []
list tcp_traf []
list tcp_sinks []
# create lists for udp
list udp_agents []
list udp_traf []
list udp_sinks []

# note: packet size from all traffic sources is limited to 1500 bytees

# create the dsl network
for {set i 0} {$i < $num_nodes} {incr i} {
    # create each dsl node
    set dsl($i) [$ns node]
    set link_delay [delay 50 250]ms
    $ns simplex-link $dsl($i) $bb_dsl [choice $dsl_up] $link_delay [choice $schedulers]
    $ns simplex-link $bb_dsl $dsl($i) [choice $dsl_down] $link_delay CoDel
    set p_agent rand()
    set p_sink rand()
    # bind an agent to the node
    # create tcp traffic, want more tcp traffic than udp traffic
    if {$p_agent <= 0.8} {
        set agent [new Agent/TCPAgent]
        $ns attach-agent $dsl($i) $agent
        lappend $tcp_agents $agent
        # create a traffic generator
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/Exponential]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $tcp_traf $traf
        } 
        # otherwise create a traffic sink
        else {
            set $sink [new Application/TCPSink]
            $sink attach-agent $agent
            lappend $tcp_sinks $sink
        }
    } 
    # create udp traffic
    else {
        set agent [new Agent/UDP]
        $ns attach-agent $dsl($i) $agent
        lappend $udp_agents $agent
        # same thing, create a generator
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/CBR]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $udp_traf $traf
        } 
        # create a sink
        else {
            set $sink [new Application/Null]
            $sink attach-agent $agent
            lappend $udp_sinks $sink
        }
    }
}

# create the cable network
for {set i 0} {$i < $num_nodes} {incr i} {
    # create each cable node
    set cable($i) [$ns node]
    set link_delay [delay 25 150]ms
    $ns simplex-link $cable($i) $bb_cable [choice $cable_up] $link_delay [choice $schedulers]
    $ns simplex-link $bb_cable $cable($i) [choice $cable_down] $link_delay CoDel
    set p_agent rand()
    set p_sink rand()
    # bind an agent to the node
    if {$p_agent <= 0.8} {
        set agent [new Agent/TCPAgent]
        $ns attach-agent $cable($i) $agent
        lappend $tcp_agents $agent
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/Exponential]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $tcp_traf $traf
        } 
        else {
            set $sink [new Application/TCPSink]
            $sink attach-agent $agent
            lappend $tcp_sinks $sink
        }
    } 
    else {
        set agent [new Agent/UDP]
        $ns attach-agent $cable($i) $agent
        lappend $udp_agents $agent
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/CBR]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $udp_traf $traf
        } 
        else {
            set $sink [new Application/Null]
            $sink attach-agent $agent
            lappend $udp_sinks $sink
        }
    }
}

# create the fiber network
for {set i 0} {$i < $num_nodes} {incr i} {
    # create each fiber node
    set fiber($i) [$ns node]
    set link_delay [delay 5 50]ms
    $ns simplex-link $fiber($i) $bb_fiber [choice $fiber_up] $link_delay [choice $schedulers]
    $ns simplex-link $bb_fiber $fiber($i) [choice $fiber_down] $link_delay CoDel
    set p_agent rand()
    set p_sink rand()
    # bind an agent to the node
    if {$p_agent <= 0.8} {
        set agent [new Agent/TCPAgent]
        $ns attach-agent $fiber($i) $agent
        lappend $tcp_agents $agent
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/Exponential]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $tcp_traf $agent
        } 
        else {
            set $sink [new Application/TCPSink]
            $sink attach-agent $agent
            lappend $tcp_sinks $sink
        }
    } 
    else {
        set agent [new Agent/UDP]
        $ns attach-agent $fiber($i) $agent
        lappend $udp_agents $agent
        if {$p_sink <= 0.5} {
            set $traf [new Application/Traffic/CBR]
            $traf attach-agent $agent
            $traf set packetSize_ 1500
            lappend $udp_traf $traf
        } 
        else {
            set $sink [new Application/Null]
            $sink attach-agent $agent
            lappend $udp_sinks $sink
        }
    }
}

# capture data for 300 sim seconds
$ns at $sim_time "finish"

$ns run
