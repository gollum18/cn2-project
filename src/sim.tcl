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
# The point is to stress the queueing mechanisms at each backbone router
#   This way we cann provide a useful analysis of them

# List of things that need done still:
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
    return [lindex $items [expr {int(rand()*[llength $items])}]]
}

# Determine a random delay within the range [min, max]
#   min: The minimum delay value
#   max: The maximum delay value
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
    if {$min > $max} {
        set temp $min
        set $min $max
        set $max $temp
    }
    # check if they are equal, I don't want that
    if {$min == $max} {
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

# get the bandwidth and scheduler
set bb_bw [lindex $argv 0]
set bb_sched [lindex $argv 1]
set num_nodes [lindex $argv 2]

# create the directory for node trace output
file mkdir ntrace

# get the filename of this execution
set ntrace [format "ntrace/%s_%s_%d.nam" $bb_bw $bb_sched $num_nodes]

# turn on tracing
set nf [open $ntrace w]
$ns namtrace-all $nf

# define a finish operation
proc finish {} {
    global ns nf ntrace
    global dcmon dfmon cfmon
    $ns flush-trace
    # close the trace files
    close $nf
    close $dcmon
    close $dfmon
    close $cfmon
    # execute NAM and the analysis program
    exec python3 analysis.py &
    exit 0
}

# create the link parameters
set schedulers [list DropTail DRR CoDel]

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

# setup the files for queue monitoring
set dcmon [open [format "qtrace/dcmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]
set dfmon [open [format "qtrace/dfmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]
set cfmon [open [format "qtrace/cfmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]

# setup queue monitoring on the links so we can get the average length
$ns monitor-queue $bb_dsl $bb_cable $dcmon
$ns monitor-queue $bb_dsl $bb_fiber $dfmon
$ns monitor-queue $bb_cable $bb_fiber $cfmon 

# create lists for tcp
set tcp_agents ""
set tcp_traf ""
set tcp_sinks ""
# create lists for udp
set udp_agents ""
set udp_traf  ""
set udp_sinks ""

# Creates a network stored in the clients list that are all connected to 
#   the indicated backbone node, with randomly chosen upload and download speeds from 
#   the given bandwidth lists, as well as a random delay in the range of 
#   [min_delay, max_delay]
# Parameters:
#   clients: A list to store the networks nodes in.
#   bb_node: The node to connect the network to.
#   bb_up: A list containing available uplink bandwidths.
#   bb_down: A list containing available downlink bandwidths.
#   min_delay: The minimum ddelay on a link.
#   max_delay: The maximum delay on a link.
proc create_network {clients bb_node bb_up bb_down min_delay max_delay} {
    # Note: end system links will just use the default linux scheduler, CoDel
    #   technically, Linux uses fq_codel by default, but I don't have it available

    #   While provider side of the link will use a random scheduler
    
    global ns num_nodes schedulers
    global tcp_agents tcp_traf tcp_sinks
    global udp_agents udp_traf udp_sinks

    # create a generic network based on the parameters
    for {set i 0} {$i < $num_nodes} {incr i} {
        # create each dsl node
        set client [$ns node]
        lappend $clients $client
        set link_delay [delay $min_delay $max_delay]ms
        $ns simplex-link $client $bb_node [choice $bb_up] $link_delay [choice $schedulers]
        $ns simplex-link $bb_node $client [choice $bb_down] $link_delay CoDel
        set p_agent rand()
        set p_sink rand()
        # bind an agent to the node
        # create tcp traffic, want more tcp traffic than udp traffic
        if {$p_agent <= 0.8} {
            set agent [new Agent/TCPAgent]
            $ns attach-agent $client $agent
            lappend $tcp_agents $agent
            # create a traffic generator
            if {$p_sink <= 0.5} {
                set traf [new Application/Traffic/Exponential]
                $traf set packetSize_ 1500
                $ns connect $agent $traf
                lappend $tcp_traf $traf
            } else {
                set sink [new Agent/TCPSink]
                $ns connect $agent $sink
                lappend $tcp_sinks $sink
            }
        } else {
            set agent [new Agent/UDP]
            $ns attach-agent $client $agent
            lappend $udp_agents $agent
            # same thing, create a generator
            if {$p_sink <= 0.5} {
                set traf [new Application/Traffic/CBR]
                $traf set packetSize_ 1500
                $ns connect $agent $traf
                lappend $udp_traf $traf
            } else {
                set sink [new Agent/Null]
                $ns connect $agent $sink
                lappend $udp_sinks $sink
            }
        }
    }
}

# create lists to hold the client nodes
set dsl_nodes ""
set cable_nodes ""
set fiber_nodes ""

# create the dsl network
create_network $dsl_nodes $bb_dsl $dsl_up $dsl_down 50 250
# create the cable network
create_network $cable_nodes $bb_cable $cable_up $cable_down 25 150
# create the fiber network
create_network $fiber_nodes $bb_fiber $fiber_up $fiber_down 5 50

# note traffic starts at a random time and runs for at least 5 seconds
#   currenntly each traffic generator only generates traffic once

# schedule tcp traffic
for {set i 0} {$i < [llength $tcp_traf]} {incr i} {
    set start [delay 0 295]
    puts $start
    $ns at $start "\[lindex $tcp_traf $i\] start"
    $ns at [delay [expr {$start+5}] 300] "[lindex $tcp_traf $i] stop"
}

# schedule udp traffic
for {set i 0} {$i < [llength $udp_traf]} {incr i} {
    set start [delay 0 295]
    $ns at $start "[lindex $udp_traf $i] start"
    $ns at [delay [expr {$start+5}] 300] "[lindex $udp_traf $i] stop"
}

# capture data for 300 sim seconds
$ns at $sim_time "finish"

$ns run
