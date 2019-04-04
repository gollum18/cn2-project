# semi-random simulation where nodes randomly transmit at certain
#   intervals for time/rounds time spans
# note: CoDel requires intensely high-traffic applications to 
#   showcase its functionality, otherwise these results are bunk

# check for the specified number of arguments
if {$argc < 5} {
    puts "usage: ns sim.tcl \[bandwidth\] \[delay\] \[scheduler\] \[time (s)\] \[rounds\]"
    exit -1
}

# get the simulation parameters
set bb_bw [lindex $argv 0]
set bb_delay [lindex $argv 1]
set bb_sched [lindex $argv 2]
set sim_time [lindex $argv 3]
set rounds [lindex $argv 4]

# create a new simulator
set ns [new Simulator]
$ns use-scheduler Heap

# create the directories for trace and queue trace output
file mkdir ntrace
file mkdir qtrace

# turn on tracing
set nf [open [format "ntrace/%s_%s_%s.nam" $bb_bw $bb_delay $bb_sched] w]
$ns namtrace-all $nf

# define a finish operation
proc finish {} {
    global ns nf qm 
    $ns flush-trace
    close $nf
    close $qm
    exit 0
}

# create lists for the up/down streams and delay
set node_up [list 1Mb 10Mb 300Mb]
set node_down [list 12Mb 30Mb 1Gb]
set node_delay [list 125ms 50ms 25ms]

# create the server nodes
set bb_carrier [$ns node]
set bb_sink [$ns node]

# create the backbone link
$ns duplex-link $bb_carrier $bb_sink $bb_bw $bb_delay $bb_sched
$ns queue-limit $bb_carrier $bb_sink 32

# setup the file for queue monitoring
set qm [open [format "qtrace/%s_%s_%s.out" $bb_bw $bb_delay $bb_sched] w]

# setup queue monitoring on the backbone link
$ns trace-queue $bb_carrier $bb_sink $qm

# attach sinks to the server
set sink [new Agent/TCPSink]
$ns attach-agent $bb_sink $sink
set null [new Agent/Null]
$ns attach-agent $bb_sink $null

set bw_down [list 12Mb 30Mb 1Gb]
set bw_up [list 1Mb 10Mb 300Mb]
set delay [list 75ms 50ms 25ms]
set sched [list DRR CoDel sfqCoDel]

# create the traffic nodes
for {set i 0} {$i < 3} {incr i} {
    # create the node
    set nodes($i) [$ns node]
        # link the node to the backbone carrier node
        $ns simplex-link $bb_carrier $nodes($i) [lindex $bw_down $i] [lindex $delay $i] [lindex $sched $i]
        $ns simplex-link $nodes($i) $bb_carrier [lindex $bw_up $i] [lindex $delay $i] [lindex $sched $i]       
}

# packet size for the dsl, cable, and fiber links
set psize [list 1500 1500 3250]

# create the tcp/udp agents
for {set i 0} {$i < 3} {incr i} {
    set tcp($i) [new Agent/TCP]
    $tcp($i) set packetSize_ [lindex $psize $i]
    $tcp($i) set maxcwnd_ 32
    set udp($i) [new Agent/UDP]
    $udp($i) set packetSize [lindex $psize $i]
    # attach the agents to the node
    $ns attach-agent $nodes($i) $tcp($i)
    $ns attach-agent $nodes($i) $udp($i)
    # connect the agents to the sinks
    $ns connect $tcp($i) $sink
    $ns connect $udp($i) $null
}

# create the traffic generators
for {set i 0} {$i < 3} {incr i} {
    set ftp($i) [new Application/FTP]
    $ftp($i) set type_ FTP
    set telnet($i) [new Application/Telnet]
    $telnet($i) set type_ Telnet
    set cbr($i) [new Application/Traffic/CBR]
    $cbr($i) set type_ CBR
    # attach the generators to the agents
    $ftp($i) attach-agent $tcp($i)
    $telnet($i) attach-agent $tcp($i)
    $cbr($i) attach-agent $udp($i)
}

# Determine a random number within the range [min, max]
#   min: The minimum range value
#   max: The maximum range value
proc rrange {min max} {
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

proc traf_interval {lower upper} {
    set start [rrange $lower [expr {$upper-10}]]
    set end [rrange [expr {$start+5}] [expr {$upper}]]
    return [list $start $end]
}

set interval [expr {$sim_time/$rounds}]
# schedule traffic for the interval at each node
for {set round 0} {$round < $rounds} {incr round} {
    set lower [expr {$interval*$round}]
    set upper [expr {$interval*[expr {$round+1}]}]
    for {set node 0} {$node < 3} {incr node} {
        set type [expr {floor([rrange 0 1])}]
        if {[expr {$type}] == 0} {
            set traf [expr {floor([rrange 0 1])}]
            if {[expr {$traf}] == 0} {
                set times [traf_interval $lower $upper]
                $ns at [lindex $times 0]s "$ftp($node) start"
                $ns at [lindex $times 1]s "$ftp($node) stop"
            } else {
                set times [traf_interval $lower $upper]
                $ns at [lindex $times 0]s "$telnet($node) start"
                $ns at [lindex $times 1]s "$telnet($node) stop"
            }
        } else {
            set times [traf_interval $lower $upper]
            $ns at [lindex $times 0]s "$cbr($node) start"
            $ns at [lindex $times 1]s "$cbr($node) stop"
        }
    }
}

# schedule the finish op
$ns at $sim_time "finish"

# run the simulation
$ns run
