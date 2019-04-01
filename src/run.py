import os

bw = ['1Gb', '2.5Gb', '5Gb']
sched = ['DropTail', 'DRR', 'CoDel', 'sfqCoDel']
nodes = '32'
time = '32000'
rounds = '320'

for b in bw:
    for s in sched:
        if os.fork() == 0:
            os.execlp('ns', 'ns', 'sim.tcl', b, s, nodes, time, rounds)
