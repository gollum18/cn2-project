if {$argc < 2} {
    puts "Usage: ns lstf.tcl \[forgetfulness\] \[run time (s)\]"
    exit -1
}

puts $argv

set forgetfulness [lindex $argv 0]
set run_time [lindex $argv 1]

# create a new simulator object
set ns [new Simulator]

# define a finish proc
proc finish {} {
    global ns nf
    $ns flush-trace
    close $nf
    puts "Simulation complete..."
    exit 0
}

# create the output directory
file mkdir out

# open the output file
set fpart [string replace $forgetfulness 0 1 ""]
set nf [open [format "out/lstf_%d.tr" $fpart run_time] w]

# create some nodes
set a [$ns node]
set b [$ns node]
set c [$ns node]
set d [$ns node]

# configure LSTFCoDel
# these parameters are recommended by RFC 8289: CoDel
Queue/LSTFCoDel set interval_ 100
Queue/LSTFCoDel set target_ 5
# forgetfulness needs more investigation for now, lets try
# with TCP's default value
Queue/LSTFCoDel set forgetfulness_ $forgetfulness

# link the nodes, no need for high speed links we just want to stress test
# no drops here since we dont match or exceed c->d link bandwidth
$ns duplex-link $a $c 1.5Mb 25ms DropTail
$ns duplex-link $b $c 1.5Mb 25ms DropTail
$ns duplex-link $c $d 3Mb 50ms LSTFCoDel

# trace the queue we are concerned about
$ns trace-queue $c $d $nf

# create some agents - note we use tcplinux since that is what 
#   CoDel runs on natively
set tcp [new Agent/TCP/Linux]
# set tcp to have a rtt of 50ms with deviation of 25ms
$tcp set rtt_ 50
$tcp set rttvar_ 25
# set window to 100
$tcp set window_ 100
# set packet size to Ethernet
$tcp set packetSize_ 1500
set udp [new Agent/UDP]
# set packet size to Ethernet
$udp set packetSize_ 1500 
set sink [new Agent/TCPSink]
set null [new Agent/Null]

# attach the agents to the nodes
$ns attach-agent $a $tcp
$ns attach-agent $b $udp
$ns attach-agent $d $sink
$ns attach-agent $d $null

# connect the agents and the sinks
$ns connect $tcp $sink
$ns connect $udp $null

# create some traffic generators
set exp [new Application/Traffic/Exponential]
set cbr [new Application/Traffic/CBR]

# link the traffic generators to the agents
$exp attach-agent $tcp
$cbr attach-agent $udp

# schedule some traffic
$ns at 0 "$exp start"
$ns at 0 "$cbr start"

# schedule finish at 7 days sim time
$ns at $run_time "finish"

# run the simulation
$ns run
