# Name: lstf.tcl
# Since: ~04/12/2019, I forgot the exact date
# Author: Christen Ford <c.t.ford@vikes.csuohio.edu>
# Purpose: This simulation is meant to 'stress' lstf-codel just enough to produce analyzable output

# I originally intended to stress CoDel's mechanisms to the point where packets were forced to drop, but then I remembered CoDel uses AQM based on queuing delay so forcing packet drops is largely unnecessary

# Switched '<' tp '!=', what was I thinking?? hah
if {$argc != 2} {
    puts "Usage: ns lstf.tcl \[forgetfulness\] \[run time (s)\]"
    exit -1
}

# Please don't switch these up, it will cause massive errors otherwise
set forgetfulness [lindex $argv 0]
set run_time [lindex $argv 1]

# create a new simulator object
set ns [new Simulator]

# define a finish proc
proc finish {} {
    global ns nf trf
    $ns flush-trace
    close $nf
    close $trf
    # leave this guy in, for longer simulations, this provides necessary feedback to let the user know the simulation is done
    puts "Simulation complete..."
    exit 0
}

# note that these <file mkdir "dir"> commands do no harm if the directory already exists 
# tcl doesn't actually have a way to check if a directory already exists

# create the output directory
file mkdir "out"

# open the output file
set fpart [string replace $forgetfulness 0 1 ""]
set nf [open [format "out/lstf_%d.tr" $fpart run_time] w]

# refer to my paper on LSTFCoDel, these names come from the topology specified there
set client_a [$ns node]
set client_b [$ns node]
set router_a [$ns node]
set server_a [$ns node]

# Its important to know that the use of Queue/LSTFCoDel below sets the class parameter, not the instance parameter
# An instance parameter should still override the class parameter as long as it is set on an instance of a LSTFCoDel link after the class variable

# configure LSTFCoDel
# these parameters are recommended by RFC 8289: CoDel
#   they are recommended best parameters for Earth-bound networks
Queue/LSTFCoDel set interval_ 100
Queue/LSTFCoDel set target_ 5

# forgetfulness must be between 0 and 1 - I have tested it with increments of 0.125 in the range of (0, 1)
# note 0 and 1 were not tested and I have no intention of doing so
Queue/LSTFCoDel set forgetfulness_ $forgetfulness

# initialize the traced variables
#   apparently for traced variables this is necessary, otherwise ns2 throws some warnings around for no reason
Queue/LSTFCoDel set curq_ 0
Queue/LSTFCoDel set d_exp_ 0.0
Queue/LSTFCoDel set slack_ 0.0

# create the links between the nodes
$ns duplex-link $client_a $router_a 10Mb 25ms DropTail
$ns duplex-link $client_b $router_a 7.5Mb 25ms DropTail
$ns duplex-link $router_a $server_a 10Mb 50ms LSTFCoDel

# set a queue size of 32 for the LSTFCoDel link
$ns queue-limit $router_a $server_a 32

# trace the queue we are concerned about, do not use "ns trace-all" - this command traces activity on ALL nodes, we do NOT want that!!
$ns trace-queue $router_a $server_a $nf

# get a reference to the server/router
#   this little *gem* was actually quite hard to find
set lclink [[$ns link $router_a $server_a] queue]

# make the variable trace directory if it doesnt exist
file mkdir "var"

# make the necessary output files
file mkdir "var/curq"
file mkdir "var/dexp"
file mkdir "var/slack"

# ahhhh, the specific format for these trace commands was also hard to find - NS2 docs are lacking, as are online resources

# trace current queue length
set curqtracer [new Trace/Var] 
$curqtracer attach [open [format "var/curq/lstf_%d_curq.tr" $fpart run_time] w] 
$lclink trace curq_ $curqtracer

# trace current delay experienced
set dexptracer [new Trace/Var]
$dexptracer attach [open [format "var/dexp/lstf_%d_dexp.tr" $fpart run_time] w] 
$lclink trace d_exp_ $dexptracer

# trace current slack time
set slacktrace [new Trace/Var]
$slacktrace attach [open [format "var/slack/lstf_%d_slack.tr" $fpart run_time] w]
$lclink trace slack_ $slacktrace

# create some agents
set tcp [new Agent/TCP]
# set tcp to have a rtt of 50ms with deviation of 25ms, note that CoDels interval is set to 100 above
$tcp set rtt_ 50
$tcp set rttvar_ 25
# sets tcps window size to 100
$tcp set window_ 100
# set packet size to Ethernet
$tcp set packetSize_ 1500

# create the udp agent
set udp [new Agent/UDP]
# set packet size to Ethernet
$udp set packetSize_ 1500

# create the tcp sink and udp null sink (although it can be used with tcp agents too!) 
set sink [new Agent/TCPSink]
set null [new Agent/Null]

# attach the agents to the nodes
$ns attach-agent $client_a $tcp
$ns attach-agent $client_b $udp
$ns attach-agent $server_a $sink
$ns attach-agent $server_a $null

# connect the agents and the sinks
$ns connect $tcp $sink
$ns connect $udp $null

# create some traffic generators
set ftp [new Application/FTP]
set cbr [new Application/Traffic/CBR]

# link the traffic generators to the agents
$ftp attach-agent $tcp
$cbr attach-agent $udp

# schedule some traffic - Maybe having both traffic generators running for the length of the simulation is a bad idea??, maybe...
$ns at 0 "$ftp start"
$ns at 0 "$cbr start"

# schedule finish at variable sim time
$ns at $run_time "finish"

# run the simulation
$ns run
