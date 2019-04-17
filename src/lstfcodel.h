/*
 * Codel - The Controlled-Delay Active Queue Management algorithm
 * Copyright (C) 2011-2012 Kathleen Nichols <nichols@pollere.com>
 * 
 * LSTFCoDel - The Least Slack Time First CoDel AQM algorithm
 * Copyright (C) 2019 Christen Ford <c.t.ford@vikes.csuohio.edu>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions, and the following disclaimer,
 *    without modification.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The names of the authors may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * Alternatively, provided that this notice is retained in full, this
 * software may be distributed under the terms of the GNU General
 * Public License ("GPL") version 2, in which case the provisions of the
 * GPL apply INSTEAD OF those given above.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef ns_lstfcodel_h
#define ns_lstfcodel_h

// I really should just define a priority queue class for this, but this is fine for now. Just know that in actual implementation, LSTFCoDel uses a priority queue as its backing queue.
#include <map>
#include <stdlib.h>
#include "agent.h"
#include "template.h"
#include "trace.h"

using std::multimap;
using std::pair;

// used by CoDel when dequeing
struct dodequeResult { Packet* p; int ok_to_drop; };

/*
 * Declares a CoDel-based queue that implements priority 
 * dequeueing based on delay spent in multiplexer.
 *
 * Packets with the highest expected delay are dequeue first.
 * Delay is computed and assigned to packets based on a 
 * modified TCP EstimatedRTT calculation which includes 
 * expected deque time as well as observed delay.
 */
class LSTFCoDelQueue : public Queue {
    public: 
        LSTFCoDelQueue();
    protected: 
        void enque(Packet* pkt);
        Packet* deque();
        
        // static LSTF state
        double forgetfulness_;
        
        // dynamic lstf state
        double avg_slack_;          // the average expected deque time, updated every time a packet is dequeued
        
        // This is an ugly, ugly hack because I ran out of time to implement it properly. This would be unneccessary if I could figure out how to use NS's priority queue or build my own
        multimap<double, Packet*> deque_order_; // used to track packet ordering for LSTF so we know which packet to deque next
        
        // static CoDel state
        double target_;
        double interval_;
        
        // dynamic CoDel state
        double first_above_time_;
        double drop_next_;          // the observed (or estimated) drop time, only updated when a drop actually occurs
        int count_;
        int dropping_;
        int maxpacket_;
        
        // NS-specific junk
        int command(int argc, const char*const* argv);
        void reset();
        void trace(TracedVar*); // routine to write trace records

        PacketQueue *q_;           // underlying DropTail queue
        Tcl_Channel tchan_;     // place to write trace records
        TracedInt curq_;        // current qlen seen by arrivals
        TracedDouble d_exp_;    // delay seen by most recently
    private:
        void add_packet(double pri, Packet* pkt) {
            deque_order_.insert(pair<double, Packet*>(pri, pkt));
        }
        double control_law(double);
        dodequeResult dodeque();
        Packet* get_packet() {
            // this should never be the case
            if (deque_order_.empty()) {
                return NULL;
            }
            // get the first element in the iterator
            // hopefully this doesnt blow up, we'll see
            pair<double, Packet*> entry = (*(deque_order_.begin()));
            deque_order_.erase(0);
            return entry.second;
        }
        double priority();
        void update_slack(double);
};

#endif
