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
# TODO: Maybe consider scheduling backbone link failures?

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
if {$argc < 4} {
    puts "usage: ns sim.tcl \[bandwidth\] \[scheduler\] \[nodes\] \[sim time (seconds)\] \[rounds\]"
    exit -1
}

# create a new simulator
set ns [new Simulator]

# get the bandwidth and scheduler
set bb_bw [lindex $argv 0]
set bb_sched [lindex $argv 1]
set num_nodes [lindex $argv 2]
set sim_time [lindex $argv 3]
set rounds [lindex $argv 4]

# create the directory for node trace output
file mkdir ntrace

# get the filename of this execution
set ntrace [format "ntrace/%s_%s_%d.nam" $bb_bw $bb_sched $num_nodes]

# turn on tracing
#set nf [open $ntrace w]
#$ns namtrace-all $nf

# define a finish operation
proc finish {} {
    global nf
    global ns ntrace
    global dcmon dfmon cfmon
    $ns flush-trace
    # close the trace files
    #close $nf
    close $dcmon
    close $dfmon
    close $cfmon
    # execute NAM and the analysis program
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

# setup the files for queue monitoring
set dcmon [open [format "qtrace/dcmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]
set dfmon [open [format "qtrace/dfmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]
set cfmon [open [format "qtrace/cfmon_%s_%s_%d.out" $bb_bw $bb_sched $num_nodes] w]

# setup queue monitoring on the links so we can get the average length
$ns trace-queue $bb_dsl $bb_cable $dcmon
$ns trace-queue $bb_dsl $bb_fiber $dfmon
$ns trace-queue $bb_cable $bb_fiber $cfmon 

# create lists for tcp
set tcp_agents [list]
set tcp_traf [list]
set tcp_sinks [list]
# create lists for udp
set udp_agents [list]
set udp_traf [list]
set udp_sinks [list]

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
        lappend clients $client
        set link_delay [delay $min_delay $max_delay]ms
        $ns simplex-link $client $bb_node [choice $bb_up] $link_delay [choice $schedulers]
        $ns simplex-link $bb_node $client [choice $bb_down] $link_delay CoDel
        # bind an agent to the node
        # randomly generate a tcp/udp agent and attach it to the client
        #   want more tcp agents than udp agents
        if {rand() < 0.75} {
            # randomly pick a generator or sink
            #   want slightly more generators than sinks
            if {rand() < 0.625} {
                # generate a TCP Reno agent
                set agent [new Agent/TCP]
                $agent set packetSize_ 1500
                $ns attach-agent $client $agent
                lappend tcp_agents $agent
                # generate traffic generator and attach it to the agent
                set traf [new Application/Traffic/Exponential]
                $traf attach-agent $agent
                lappend tcp_traf $traf
            } else {
                # otherwise generate a tcp sink and attach it to the node
                set sink [new Agent/TCPSink]
                $ns attach-agent $client $sink
                lappend tcp_sinks $sink
            }
        } else {
            # randomly pick a generator or sink
            #   this time we want more sinks than generators
            if {rand() < 0.375} {
                # generate a udp agent
                set agent [new Agent/UDP]
                $agent set packetSize_ 1500
                $ns attach-agent $client $agent
                lappend $udp_agents $agent
                # generate a traffic generator and attach it to the agent
                set traf [new Application/Traffic/CBR]
                # randomize packet size
                $traf set packet_size_ delay 80 3250
                # randomly enable dithering
                #   dithering randomly enables and disables the sending 
                #   of packets from the CBR generator during up time 
                #   of the generator
                if {rand() <= 0.5} {
                    $traf set random_ 1
                }
                $traf attach-agent $agent
                lappend udp_traf $traf
            } else {
                # otherwise generate a udp sink and attach it to the node
                set sink [new Agent/Null]
                $ns attach-agent $client $sink
                lappend udp_sinks $sink
            }
        }
    }
}

# create lists to hold the client nodes
set dsl_nodes [list]
set cable_nodes [list]
set fiber_nodes [list]

# create the dsl network
create_network $dsl_nodes $bb_dsl $dsl_up $dsl_down 50 250
# create the cable network
create_network $cable_nodes $bb_cable $cable_up $cable_down 25 150
# create the fiber network
create_network $fiber_nodes $bb_fiber $fiber_up $fiber_down 5 50

# create a lan for the backbone nodes
#   TODO: For some reason this command throws an invalid command error for Mac/Csma/Cd
#set bb_lan [$ns make-lan "$bb_dsl $bb_cable $bb_fiber" $bb_bw 50ms LL Queue/$bb_sched MAC/Csma/Cd]
# create a lan for the dsl network
set dsl_lan [$ns make-lan $dsl_nodes [choice $dsl_down] [delay 50 250]ms LL Queue/$bb_sched MAC/Csma/Cd]
# create a lan for the cable network
set cable_lan [$ns make-lan $cable_nodes [choice $cable_down] [delay 25 150]ms LL Queue/$bb_sched MAC/Csma/Cd]
# create a lan for the fiber network
set fiber_lan [$ns make-lan $fiber_nodes [choice $fiber_down] [delay 5 50]ms LL Queue/$bb_sched MAC/Csma/Cd]

# Randomly connects agents to sinks and schedules traffic for said
# agents for n rounds. Currently agents generate traffic once per 
# round.
# Parameters:
#   agents: A list of agents.
#   sinks: A list of sinks.
#   traf: A list containing traffic generators attached to agents.
proc sched_traf {agents sinks traf} {
    global ns rounds sim_time
    # randomly attach agents to sinks
    for {set i 0} {$i < [llength $agents]} {incr i} {
        $ns connect [lindex $agents $i] [choice $sinks]
    }
    # schedule traffic for the given amount of rounds
    set interval [expr {floor($sim_time/$rounds)}]
    for {set i 0} {$i <= $rounds} {incr i} {
        set p1 [expr {$i+1}]
        set lower [expr {$interval*$i}]
        set upper [expr {$interval*$p1}]
        for {set j 0} {$j < [llength $agents]} {incr j} {
            set start [delay $lower $upper]
            $ns at $start [format "%s start" [lindex $traf $j]]
            $ns at [delay [expr {$start+5}] $upper] [format "%s stop" [lindex $traf $i]]
        }
    }
}

# schedule traffic for tcp and udp
sched_traf $tcp_agents $tcp_sinks $tcp_traf 
sched_traf $udp_agents $udp_sinks $udp_traf

# capture data for 300 sim seconds
$ns at $sim_time "finish"

$ns run
