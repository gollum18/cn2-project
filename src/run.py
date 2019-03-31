import subprocess

bw = ['1Gb', '2.5Gb', '5Gb']
sched = ['DropTail', 'DRR', 'CoDel', 'sfqCoDel']
nodes = '32'
time = '18000'
rounds = '100'

for b in bw:
    for s in sched:
        subprocess.run(['ns', 'sim.tcl', b, s, nodes, time, rounds])
