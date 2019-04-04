import os
import sys

if len(sys.argv) < 3:
    print('usage: python run.py [time] [rounds]')
    sys.exit(22)

bw = ['100Mb', '500Mb', '1Gb']
sched = ['DropTail', 'DRR', 'CoDel', 'sfqCoDel']
delay = ['50ms', '250ms', '500ms', '1s']
time = sys.argv[1]
rounds = sys.argv[2]

for b in bw:
    for d in delay:
        for s in sched:
            if os.fork() == 0:
                os.execlp('ns', 'ns', 'sim.tcl', b, d, s, time, rounds)
