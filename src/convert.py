# Name: convert.py
# Since: 04/22/2019
# Author: Christen Ford <c.t.ford@vikes.csuohio.edu>
# Purpose: Converts NS-2 variable trace files to a format compatible with XGraph.

import os
import sys

# TODO: There has to be a way to refactor these guys to a single method

def slack_trace_to_graph(filename, epsilon):
    '''
    Converts the slack trace file pointed to by filename to a format utilizable by XGraph. Epsilon is the sampling interval. For instance, if interval is 30, then one sample will be drawn from the trace every 30 seconds.
    '''
    pass

def qlen_trace_to_graph(filename, epsilon):
    '''
    Converts the queue length trace file pointed to by filename to a format utilizable by XGraph. Epsilon is the sampling interval. For instance, if interval is 30, then one sample will be drawn from the trace every 30 seconds.
    '''
    pass

def delay_trace_to_graph(filename, epsilon):
    '''
    Converts the delay trace file pointed to by filename to a format utilizable by XGraph. Epsilon is the sampling interval. For instance, if interval is 30, then one sample will be drawn from the trace every 30 seconds.
    '''
    fparts = filename.split(os.path.sep)
    out = open(os.path.join('graph', fparts[len(fparts)-1]), 'w')
    capture = 0.0
    try:
        with open(filename) as f:
            for line in f:
                parts = line.split(' ')
                time = float(parts[1].replace('t', ''))
                delay = parts[len(parts)-1].replace('v', '').replace('\n', '')
                if time > capture:
                    out.write('{0} {1}\n'.format(time, delay))
                    capture += epsilon
        out.close()
    except IOError as e:
        usage(e)
        sys.exit(-1)

def invoke(script, epsilon, filename):
    '''
    Attempts to invoke the appropriate convert script on the given filename with the given epsilon.
    '''
    if not os.path.exists(filename):
        usage('Error: Indicated file does not exist!')
        sys.exit(-1)
    script = script.lower()
    if script == 'delay':
        delay_trace_to_graph(filename, epsilon)
    elif script == 'qlen':
        qlen_trace_to_graph(filename, epsilon)
    elif script == 'slack':
        slack_trace_to_graph(filename, epsilon)
    else:
        usage('Error: Invalid script specified')
        sys.exit(-1)

def usage(error):
    print('-'*80)
    print(error)
    print('-'*80)
    print('Usage: python scripts.py [delay|qlen|slack] [epsilon] [filename]')
    print('Params are:')
    print('[delay|qlen|slack]: The conversion script to run.')
    print('[epsilon]: The sampling interval.')
    print('[filename]: The filename or path of the trace file to convert.')
    print('-'*80)

def main():
    if len(sys.argv) != 4:
        usage()
        sys.exit(-1)
    invoke(sys.argv[1], float(sys.argv[2]), sys.argv[3])

if __name__ == '__main__':
    main()
