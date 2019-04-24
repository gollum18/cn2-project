/*
 * Codel - The Controlled-Delay Active Queue Management algorithm
 * Copyright (C) 2011-2012 Kathleen Nichols <nichols@pollere.com>
 *
 * LSTFCoDel - The Least Slack Time First Priotized Controlled-Delay 
 * Active Queue Management algorithm
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

#include <math.h>
#include <sys/types.h>
#include "config.h"
#include "template.h"
#include "random.h"
#include "flags.h"
#include "delay.h"
#include "lstfcodel.h"

// defines an LSTFCoDelQueue as derived TclClass
static class LSTFCoDelClass : public TclClass {
  public:
    // empty constructor for creating instances of the LSTFCoDelClass from its TCL counterpart
    LSTFCoDelClass() : TclClass("Queue/LSTFCoDel") {}
    // returns a new instance of the LSTFCoDelClass its corresponding TCL object LSTFCoDelQueue
    TclObject* create(int, const char*const*) {
        return (new LSTFCoDelQueue);
    }
} class_codel;

// creates an instance of an LSTFCoDel queue
LSTFCoDelQueue::LSTFCoDelQueue() : tchan_(0)
{
    bind("forgetfulness_", &forgetfulness_);    // weighting factor used to determine how much influence past congestion has on incoming packets
    bind("interval_", &interval_);              // target interval CoDel aims for
    bind("target_", &target_);  // target min delay in clock ticks
    bind("curq_", &curq_);      // current queue size in bytes
    bind("d_exp_", &d_exp_);    // current delay experienced in clock ticks
    bind("slack_", &slack_);    // current slack value 
    q_ = new PacketQueue();     // underlying queue
    pq_ = q_;
    reset();
}

void LSTFCoDelQueue::reset()
{
    // initialize average slack to CoDels interval, not sure if this is what we want, but it seems to be working ok
    slack_ = interval_;
    curq_ = 0;
    d_exp_ = 0.;
    slack_ = 0.;
    dropping_ = 0;
    first_above_time_ = 0;
    maxpacket_ = 256;
    count_ = 0;
    drop_next_ = 0;
    while (sched_.size() > 0) {
        sched_.erase(0);
    }
    Queue::reset();
}

// Add a new packet to the queue.  The packet is dropped if the maximum queue
// size in pkts is exceeded. Otherwise just add a timestamp so dequeue can
// compute the sojourn time (all the work is done in the deque).

void LSTFCoDelQueue::enque(Packet* pkt)
{
    // drop the incoming packet if the queue is full
    if(q_->length() >= qlim_) {
        drop(pkt);
    } else {
        // update the packets timestamp
        HDR_CMN(pkt)->ts_ = Scheduler::instance().clock();
        // add the packet to the multimap with the calculated priority per my paper -> priority is irrelevant of the packet
        // priority is purely determined from what is going on with congestion in the router, it is not derived from any fields in the packet
        // e.g. no special treatment of packets!!
        add_packet(priority(), pkt);
        // throw the packet into the backing FIFO queue
        q_->enque(pkt);
    } 
}

// return the time of the next drop relative to 't'
double LSTFCoDelQueue::control_law(double t)
{
    // this calculation is derived from a paper referenced in RFC 8289
    //   according to said paper, this calculation attempts to maximize power efficiency of the router
    return t + interval_ / sqrt(count_);
}

// determine the priority in the queue
double LSTFCoDelQueue::priority()
{   
    // determine a packets priority in the queue per my paper
    if (slack_ == 0) {
        return 0;
    } else {
        return 1.0 / (1.0 + slack_);
    }
}

// update the average slack time 
void LSTFCoDelQueue::update_slack()
{
    // calculate the average slack value as stated in my paper
    slack_ =  max_delay_ + ((1 - forgetfulness_) * slack_ + forgetfulness_ * drop_next_);
    // reset drop_next_ to zero after calculating slack
    //   does not affect CoDel at all - drop_next_ is temporally local to when it used and is recalculated each CoDel round
    drop_next_ = 0;
}

// Internal routine to dequeue a packet. All the delay and min tracking
// is done here to make sure it's done consistently on every dequeue.
dodequeResult LSTFCoDelQueue::dodeque()
{
    double now = Scheduler::instance().clock();
    dodequeResult r = { NULL, 0 };

    // get_packet grabs the first packet from the multimap (the packet with least slack time)
    r.p = get_packet();
    // remove searches the backing FIFO queue and removes the packet in place (if it is found, if not this triggers an error and abort() call)
    q_->remove(r.p);
    
    if (r.p == NULL) {
        curq_ = 0;
        first_above_time_ = 0;
    } else {
        // d_exp_ and curq_ are ns2 'traced variables' that allow the dynamic
        // queue behavior that drives CoDel to be captured in a trace file for
        // diagnostics and analysis.  d_exp_ is the sojourn time and curq_ is
        // the current q size in bytes.
        d_exp_ = now - HDR_CMN(r.p)->ts_;
        // check if we need to update the max observed delay
        if (d_exp_ > max_delay_) {
            max_delay_ = d_exp_;
        }
        curq_ = q_->byteLength();

        if (maxpacket_ < HDR_CMN(r.p)->size_)
            // keep track of the max packet size.
            maxpacket_ = HDR_CMN(r.p)->size_;

        if (d_exp_ < target_ || curq_ <= maxpacket_) {
            // went below - stay below for at least interval
            first_above_time_ = 0;
        } else {
            if (first_above_time_ == 0) {
                //just went above from below.
		// if still above at first_above_time, say it’s ok to drop
	    // next 3 lines added by kmn (might better adjust count_ first?)
	    if( (now - drop_next_) < 8*interval_ && count_ > 1) {
	     first_above_time_ = control_law(now);
	    } else
                first_above_time_ = now + interval_;
            } else if (now >= first_above_time_) {
                r.ok_to_drop = 1;
            }
        }
    }
    return r;
}

// All of the work of CoDel is done here. There are two branches: In packet
// dropping state (meaning that the queue sojourn time has gone above target
// and hasn’t come down yet) check if it’s time to leave or if it’s time for
// the next drop(s). If not in dropping state, decide if it’s time to enter it
// and do the initial drop.

Packet* LSTFCoDelQueue::deque()
{
    // The guard here is to ensure whatever touches this queue does not trigger an abort from the call to q_->remove above in dodeque()
    if (length() == 0) {
        return 0;
    }
    
    // max_delay is amortized because congestion is a temporal issue
    //  it comes and goes
    // amortizing max_delay account for periodic bursts of heavy traffic -> which causes long queueing delays
    max_delay_ = max_delay_ * 0.925;

    // the rest of this is the normal CoDel AQM algorithm

    double now = Scheduler::instance().clock();;
    dodequeResult r = dodeque();
    
    if (dropping_) {
        if (! r.ok_to_drop) {
            // sojourn time below target - leave dropping state
            dropping_ = 0;
        }
        // It’s time for the next drop. Drop the current packet and dequeue
        // the next.  If the dequeue doesn't take us out of dropping state,
        // schedule the next drop. A large backlog might result in drop
        // rates so high that the next drop should happen now, hence the
        // ‘while’ loop.
        while (now >= drop_next_ && dropping_) {
            drop(r.p);
            r = dodeque();
	//in dropping state, drop elderly packets 
	// doesn't seem to kick in except for extreme bw drops
	// and question is how old is elderly?
	//while (r.ok_to_drop && d_exp_ > 8*interval_) {
	// drop(r.p);
	// r = dodeque();
	//}
            if (! r.ok_to_drop) {
                // leave dropping state
                dropping_ = 0;
            } else {
                // schedule the next drop.
	        ++count_;	//kmn -  only count one drop
				//     moved from after drop(r.p) above
                drop_next_ = control_law(drop_next_);
            }
        }

    // If we get here we’re not in dropping state. 'ok_to_drop' means that the
    // sojourn time has been above target for interval so enter dropping state.
    } else if (r.ok_to_drop) {
        drop(r.p);
        r = dodeque();
        dropping_ = 1;

        // If min went above target close to when it last went below,
        // assume that the drop rate that controlled the queue on the
        // last cycle is a good starting point to control it now.
	// Unfortunately, this is not easy to get at. "n*interval" is
	// used to indicate "close to" and values from 2 - 16 have been
	// used. A value of 8 has worked well. The count value doesn't
	// decay well enough with this control law. Until a better one
	// is devised, the below is a hack that appears to improve things.

	if(count_ > 2 && now- drop_next_ < 8*interval_) {
		count_ = count_ - 2;
		// kmn decay tests
		if(count_ > 126) count_ = 0.9844 * (count_ + 2);
	} else
		count_ = 1;
        drop_next_ = control_law(now);
    }
    
    // update slack time
    update_slack();
    
    return (r.p);
}

// NS-2 specific method for capturing TCL commands and translating them to the appropriate C++ commands
int LSTFCoDelQueue::command(int argc, const char*const* argv)
{
    Tcl& tcl = Tcl::instance();
    if (argc == 2) {
        if (strcmp(argv[1], "reset") == 0) {
            reset();
            return (TCL_OK);
        }
    } else if (argc == 3) {
        // attach a file for variable tracing
        if (strcmp(argv[1], "attach") == 0) {
            int mode;
            const char* id = argv[2];
            tchan_ = Tcl_GetChannel(tcl.interp(), (char*)id, &mode);
            if (tchan_ == 0) {
                tcl.resultf("CoDel trace: can't attach %s for writing", id);
                return (TCL_ERROR);
            }
            return (TCL_OK);
        }
        // connect CoDel to the underlying queue
        if (!strcmp(argv[1], "packetqueue-attach")) {
            delete q_;
            if (!(q_ = (PacketQueue*) TclObject::lookup(argv[2])))
                return (TCL_ERROR);
            else {
                pq_ = q_;
                return (TCL_OK);
            }
        }
    }
    return (Queue::command(argc, argv));
}

// Routine called by TracedVar facility when variables change values.
// Note that the tracing of each var must be enabled in tcl to work.
void
LSTFCoDelQueue::trace(TracedVar* v)
{
    const char *p;

    // should I add an additional traced variable here, perhaps for the slack time?
    // last time I did NS kept segfaulting
    if (((p = strstr(v->name(), "slack")) == NULL) &&
        ((p = strstr(v->name(), "curq")) == NULL) &&
        ((p = strstr(v->name(), "d_exp")) == NULL) ) {
        fprintf(stderr, "CoDel: unknown trace var %s\n", v->name());
        return;
    }
    if (tchan_) {
        char wrk[500];
        double t = Scheduler::instance().clock();
        if(*p == 'c') {
            sprintf(wrk, "c %g %d", t, int(*((TracedInt*) v)));
        } else if(*p == 'd') {
            sprintf(wrk, "d %g %g", t, double(*((TracedDouble*) v)));
        }
        int n = strlen(wrk);
        wrk[n] = '\n'; 
        wrk[n+1] = 0;
        (void)Tcl_Write(tchan_, wrk, n+1);
    }
}
