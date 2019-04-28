#! /usr/bin/python

# Name: graph.py
# Since:
# Author: Christen Ford
# Purpose: Generates a graph pair (paired dexp/slack) files for use with gnuplot or xgraph.

import os
import sys

from multiprocessing import Pool

write_time = 30
out_dir = './var/graph'
dexp_path = './var/dexp'
slack_path = './var/slack'

def extract_tv_pair(record):
    parts = record.split(' ')
    if len(parts) != 5:
        print('Error: Record is not a valid format!')
        sys.exit(-1)
    time = float(parts[1].replace('t', ''))
    value = float(parts[4].replace('v', ''))
    return time, value
    
def get_file(filename):
    return filename.split(os.path.sep)[-1]

def generate_file(filename):
    lim = 0.
    try:
        out = open(os.path.join(out_dir, get_file(filename)), 'w')
        with open(filename) as f:
            for line in f:
                time, value = extract_tv_pair(line)
                lim += 1000.*time
                if lim > write_time:
                    out.write('{0} {1}\n'.format(time, value))
                    lim = 0.
        out.close()
    except IOError as e:
        print(e)
        sys.exit(-1)

def main():
    if len(sys.argv) != 2:
        print('Usage: python graph.py [alpha|--codel]')
        print('\talpha: Alpha value corresponding to the file pair.')
        print('\t--codel: Instructs graph.py to generate output for the codel trace file.')
        sys.exit(-1)
    if not os.path.exists(out_dir):
        os.mkdir(out_dir)
    if sys.argv[1].lower() == '--codel':
        dexp = os.path.join(dexp_path, 'codel_dexp.tr')
        generate_file(dexp)
    else:
        # perform checks on alpha
        try:
        if not 0 < float(sys.argv[1]) < 1:
            print('ValueError: Alpha must be in the range (0, 1)!')
        except TypeError:
            print('TypeError: Alpha must be a number in the range (0, 1)!')
        finally:
            sys.exit(-1)
        # create needed program variables
        alpha = sys.argv[1]
        dexp = os.path.join(dexp_path, 'lstf_{0}_dexp.tr'.format(alpha))
        slack = os.path.join(slack_path, 'lstf_{0}_slack.tr'.format(alpha))
        # kick off the graph generation as a mp-pool map call
        with Pool(3) as pool:
            pool.map(generate_file, [dexp, slack])

if __name__ == '__main__':
    main()
