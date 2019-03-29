# Abstract
This project is meant to investigate the performance of recent advancements in the fq-CoDel packet scheduling algorithm, proposed in [RFC 8290](https://tools.ietf.org/html/rfc8290). CoDel or controlled delay is a packet scheduling algorithm built with the intention to fight [bufferbloat](https://www.bufferbloat.net/projects/) and network latency. This project will utilize [ns2](https://www.isi.edu/nsnam/ns/) to compare the performance of the most recent iteration of the fq-CoDel algorithm I could find (sfq-CoDel), to the performance of traditonal CoDel, Deficit Round Robin (DRR), and DropTail (FIFO) packet scheduling. I have tried to set this project up so that it is as close to simulating a modern network as it possibly can be within the limitations of Network Simulator.

---
# Parameters
I am still figuring out the required length of each simulation however, the parameters for the rest of the project are defined here:

- Each simulation will have two autonomous systems connected by a backbone link running at a total bandwidth of 1 GB/s, 10 GB/s, and 50 GB/s for a total of three simulations.
- The backbone link shall be a single duplex-link running at the configured above bandwidths per simulation.
- The packet scheduler for the backbone link in each direction will rotate out between sfq-Codel, CoDel, DRR, and DropTail.
- Each autonomous system will represent different carriers providing access following what I determined is common in the current U.S. telecommunications market.
  - The first autonomous system shall represent a ADSL/FTTH carrier and will consist of three sub-networks: one strictly ADSL, one mixed ADSL/FTTH, and one strictly FTTH.
  - The second autonomous system shall represent a Cable/FTTH carrier and will consist of three sub-networks: one strictly Cable, one mixed Cable/FTTH, and one strictly FTTH.
  - Each sub-network will have six nodes with varying access speeds and link properties that I am still working out. It should be noted that each node has is connected to the sub-networks gateway node via two simplex-links, one representing the downstream and the other the upstream.
- There shall be 30 nodes in the the network:
  - 2 for the backbone link.
  - 4 gateway nodes (2 for each autonomous system connected to opposite ends of the backbone link).
  - 24 end system nodes (6 connected to each gateway node).

---
# Topology
I'm gonna stiick to describing the topology by hand. It has changed since I initially drew it up and I do not feel like drawing it up right now.

Essentially what we have is a triangular linking of three backbone nodes where each node represents one of either a dsl, cable, or fiber provider. Client nodes connect directly to these nodes and communicate with each other using the backbone links that connect the backbone nodes. 

Link dynamics are still an issue that I am considering handling.
