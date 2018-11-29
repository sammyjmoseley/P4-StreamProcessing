#!/usr/bin/env python
import argparse
import sys
import socket
import random
import struct

from scapy.all import sendp, send, get_if_list, get_if_hwaddr, bind_layers
from scapy.all import Packet, Raw
from scapy.all import Ether, IP, TCP
from scapy.fields import *
import readline

def get_if():
    ifs=get_if_list()
    iface=None
    for i in get_if_list():
        if "eth0" in i:
            iface=i
            break;
    if not iface:
        print "Cannot find eth0 interface"
        exit(1)
    return iface

class KeyValCount(Packet):
  fields_desc = [ IntField("count", 0)
  ]

class KeyValPair(Packet):
   fields_desc = [ IntField("schema", 0),
                   IntField("key", 0),
                   IntField("val", 0),
                   BitField("unprocessed", 0, 8)
                   ] #add bit field
   
bind_layers(TCP, KeyValCount, dport=0x1234)
bind_layers(KeyValCount, KeyValPair)
bind_layers(KeyValPair, KeyValPair)

def main():

    if len(sys.argv)<5:
        print 'pass 2 arguments: <destination> "<schema>" "<key>" "<val>"'
        exit(1)

    addr = socket.gethostbyname(sys.argv[1])
    iface = get_if()

    print "sending on interface %s to %s" % (iface, str(addr))
    pkt =  Ether(src=get_if_hwaddr(iface), dst='ff:ff:ff:ff:ff:ff')
    # pkt = pkt /IP(dst=addr, chksum=0xffff) / TCP(dport=1234, sport=random.randint(49152,65535)) / sys.argv[2]
    pkt = pkt /IP(dst=addr) / TCP(dport=0x1234, sport=random.randint(49152,65535))
    l = (len(sys.argv)-2)//3
    pkt = pkt / KeyValCount(count=l)
    for i in range(2, len(sys.argv), 3):
        pkt = pkt  / KeyValPair(schema=int(sys.argv[i]), key=int(sys.argv[i+1]), val=int(sys.argv[i+2]), unprocessed=1)
    pkt.show2()
    sendp(pkt, iface=iface, verbose=False)
    
if __name__ == '__main__':
    main()
