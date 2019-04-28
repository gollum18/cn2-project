# Name: codel.tcl
# Since: 04/28/2019
# Author: Christen Ford <c.t.ford@vikes.csuohio.edu>
# Purpose: This simulation is meant to 'stress' codel just enough to produce analyzable output

# NOTE: This is a modified version of lstf.codel, I may eventually merge the two into one file

# I originally intended to stress CoDel's mechanisms to the point where packets were forced to drop, but then I remembered CoDel uses AQM based on queuing delay so forcing packet drops is largely unnecessary

# Switched '<' tp '!=', what was I thinking?? hah
if {$argc != 1} {
    puts "Usage: ns codel.tcl \[run time (s)\]"
    exit -1
}

# get the run time
set run_time [lindex $argv 0]

# create a new simulator object
set ns [new Simulator]

# define a finish proc
proc finish {} {
    global ns nf trq trd
    $ns flush-trace
    close $nf
    close $trq
    close $trd
    # leave this guy in, for longer simulations, this provides necessary feedback to let the user know the simulation is done
    puts "Simulation complete..."
    exit 0
}

# note that these <file mkdir "dir"> commands do no harm if the directory already exists 
# tcl doesn't actually have a way to check if a directory already exists

# create the output directory
file mkdir "out"

# open the output file
set nf [open "out/codel.tr" w]

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
Queue/CoDel set interval_ 100
Queue/CoDel set target_ 5

# initialize the traced variables
#   apparently for traced variables this is necessary, otherwise ns2 throws some warnings around for no reason
Queue/CoDel set curq_ 0
Queue/CoDel set d_exp_ 0.0

# create the links between the nodes
$ns duplex-link $client_a $router_a 2Mb 25ms DropTail
$ns duplex-link $client_b $router_a 1.5Mb 25ms DropTail
$ns duplex-link $router_a $server_a 1.7Mb 50ms CoDel

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

# ahhhh, the specific format for these trace commands was also hard to find - NS2 docs are lacking, as are online resources

# trace current queue length
set curqtracer [new Trace/Var] 
set trq [open "var/curq/codel_curq.tr" w]
$curqtracer attach $trq 
$lclink trace curq_ $curqtracer

# trace current delay experienced
set dexptracer [new Trace/Var]
set trd [open "var/dexp/codel_dexp.tr" w]
$dexptracer attach $trd 
$lclink trace d_exp_ $dexptracer

# create some agents
set tcp [new Agent/TCP]
# set packet size to Ethernet
$tcp set packetSize_ 1500

# create a UDP agent
set udp [new Agent/UDP]
# set packet size to Ethernet
$udp set packetSize_ 1000

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
# stagger the start time for the telnet agent
$ns at 300 "$cbr start"

# schedule finish at variable sim time
$ns at $run_time "finish"

# run the simulation
$ns run
