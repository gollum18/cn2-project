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
        set $max expr {$max+1}
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

# turn on tracing on the backbone links

# Note: end system links will just use the default linux scheduler, CoDel
#   technically, Linux uses fq_codel by default, but I don't have it available
#   While provider side of the link will use a random scheduler

# TODO: determine the common delays for dsl, cable, and fiber links

# create the dsl network
for {set i 0} {$i < $num_nodes} {incr i} {
    set dsl($i) [$ns node]
    $ns simplex-link $dsl($i) $bb_dsl [choice $dsl_up] [delay ] [choice $schedulers]
    $ns simplex-link $bb_dsl $dsl($i) [choice $dsl_down] [delay ] CoDel
}

# create the cable network
for {set i 0} {$i < $num_nodes} {incr i} {
    set cable($i) [$ns node]
    $ns simplex-link $cable($i) $bb_cable [choice $cable_up] [delay ] [choice $schedulers]
    $ns simplex-link $bb_cable $cable($i) [choice $cable_down] [delay ] CoDel
}

# create the fiber network
for {set i 0} {$i < $num_nodes} {incr i} {
    set fiber($i) [$ns node]
    $ns simplex-link $fiber($i) $bb_fiber [choice $fiber_up] [delay ] [choice $schedulers]
    $ns simplex-link $bb_fiber $fiber($i) [choice $fiber_down] [delay ] CoDel
}

# capture data for 300 sim seconds
$ns at 300 "finish"

$ns run
