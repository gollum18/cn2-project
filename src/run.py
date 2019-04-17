import os

f_lvls = [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
r = 432000

for f in f_lvls:
    os.system('ns lstf.tcl {0} {1} &'.format(f, r))
