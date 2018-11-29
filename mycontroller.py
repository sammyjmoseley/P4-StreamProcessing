#!/usr/bin/env python2
import argparse
import grpc
import os
import sys
from time import sleep
import json
import networkx

sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'utils/'))
import run_exercise
import p4runtime_lib.bmv2
from p4runtime_lib.switch import ShutdownAllSwitchConnections
import p4runtime_lib.helper
    
def printGrpcError(e):
    """
    Helper function to print a GRPC error

    :param e: the error object
    """
    
    print "gRPC Error:", e.details(),
    status_code = e.code()
    print "(%s)" % status_code.name,
    traceback = sys.exc_info()[2]
    print "[%s:%d]" % (traceback.tb_frame.f_code.co_filename, traceback.tb_lineno)

def load_topology(topo_file_path):
    """
    Helper function to load a topology

    :param topo_file_path: the path to the JSON file containing the topology
    """

    switch_number = 0
    switches = {}
    with open(topo_file_path) as topo_data:
        j = json.load(topo_data)
    json_hosts = j['hosts']
    json_switches = j['switches'].keys()
    json_links = run_exercise.parse_links(j['links'])
    mn_topo = run_exercise.ExerciseTopo(json_hosts, json_switches, json_links, "logs")
    for switch in mn_topo.switches():
        switch_number += 1
        bmv2_switch = p4runtime_lib.bmv2.Bmv2SwitchConnection(
            name=switch,
            address="127.0.0.1:%d" % (50050 + switch_number),
            device_id=(switch_number - 1),
            proto_dump_file="logs/%s-p4runtime-requests.txt" % switch)
        switches[switch] = bmv2_switch
                
    return (switches, mn_topo)
    
def main(p4info_file_path, bmv2_file_path, topo_file_path):
    # Instantiate a P4Runtime helper from the p4info file
    p4info_helper = p4runtime_lib.helper.P4InfoHelper(p4info_file_path)

    try:
        # Load the topology from the JSON file
        switches, mn_topo = load_topology(topo_file_path)

        # Establish a P4 Runtime connection to each switch
        for bmv2_switch in switches.values():
            bmv2_switch.MasterArbitrationUpdate()
            print "Established as controller for %s" % bmv2_switch.name

        # Load the P4 program onto each switch
        for bmv2_switch in switches.values():
            bmv2_switch.SetForwardingPipelineConfig(p4info=p4info_helper.p4info,
                                                    bmv2_json_file_path=bmv2_file_path)
            print "Installed P4 Program using SetForwardingPipelineConfig on %s" % bmv2_switch.name


        graph = networkx.Graph()
        host_ipv4 = {}
        host_mac = {}
        host_dst_id = {}
        dst_cnt = 1
        for host in mn_topo.hosts():
            print('added node: ' + host)
            graph.add_node(host)
            ip = tuple(mn_topo.nodeInfo(host)['ip'].split('/'))
            host_mac[host] = mn_topo.nodeInfo(host)['mac']
            host_ipv4[host] = (ip[0], int(ip[1]))
            host_dst_id[host] = dst_cnt
            dst_cnt += 1
        for switch in mn_topo.switches():
            print('added node: ' + switch)
            graph.add_node(switch)
        for link in mn_topo.links():
            graph.add_edge(link[0], link[1])
            graph.add_edge(link[1], link[0])
        
        table_entries = []

        for host in mn_topo.hosts():
            table_entry = p4info_helper.buildTableEntry(
                table_name="MyIngress.ipv4_lpm",
                match_fields={
                    "hdr.ipv4.dstAddr": (host_ipv4[host][0], 32)
                },
                action_name="MyIngress.myTunnel_ingress",
                action_params={
                    "dst_id": host_dst_id[host],
                })
            table_entries.append(table_entry)

        for s in mn_topo.switches():
            switch = switches[s]
            for table_entry in table_entries:
                switch.WriteTableEntry(table_entry)

        for host_s in mn_topo.hosts():
            host_s = str(host_s)
            for host_d in mn_topo.hosts():
                host_d = str(host_d)
                if host_s == host_d:
                    continue
                print((host_s, host_d))
                path = networkx.shortest_path(graph, host_s, host_d)
                print path
                for i in range(1, len(path)-2):
                    forward_entry = p4info_helper.buildTableEntry(
                            table_name="MyIngress.myTunnel_exact",
                            match_fields={
                                "hdr.myTunnel.dst_id": host_dst_id[host_d]
                            },
                            action_name="MyIngress.myTunnel_forward",
                            action_params={
                                "port": mn_topo.port(path[i], path[i+1])[0]
                            }
                        )
                    print "forwarding " + path[i] + " -> " + path[i+1] + " for  dst " + host_d
                    switches[path[i]].WriteTableEntry(forward_entry)
                egress_entry = p4info_helper.buildTableEntry(
                        table_name="MyIngress.myTunnel_exact",
                        match_fields={
                            "hdr.myTunnel.dst_id": host_dst_id[host_d]
                        },
                        action_name="MyIngress.myTunnel_egress",
                        action_params={
                            "dstAddr": host_mac[host_d],
                            "port": mn_topo.port(path[-2], path[-1])[0]
                        }
                    )
                print str((host_d, path[-2], path[-1]))
                print "egress: %s, %s" % (host_mac[host_d], mn_topo.port(path[-2], path[-1])[0])
                switches[path[-2]].WriteTableEntry(egress_entry) 
                # now do egress

            
    except KeyboardInterrupt:
        print " Shutting down."
    except grpc.RpcError as e:
        printGrpcError(e)

    ShutdownAllSwitchConnections()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='P4Runtime Controller')
    parser.add_argument('--p4info', help='p4info proto in text format from p4c',
                        type=str, action="store", required=False,
                        default='./build/switch.p4info')
    parser.add_argument('--bmv2-json', help='BMv2 JSON file from p4c',
                        type=str, action="store", required=False,
                        default='./build/switch.json')
    parser.add_argument('--topo', help='Topology file',
                        type=str, action="store", required=False,
                        default='topology.json')
    args = parser.parse_args()

    if not os.path.exists(args.p4info):
        parser.print_help()
        print "\np4info file not found: %s\nHave you run 'make'?" % args.p4info
        parser.exit(1)
    if not os.path.exists(args.bmv2_json):
        parser.print_help()
        print "\nBMv2 JSON file not found: %s\nHave you run 'make'?" % args.bmv2_json
        parser.exit(1)
    if not os.path.exists(args.topo):
        parser.print_help()
        print "\nTopology file not found: %s" % args.topo
        parser.exit(1)
    main(args.p4info, args.bmv2_json, args.topo)
