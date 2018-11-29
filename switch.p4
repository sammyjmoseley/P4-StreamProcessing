/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>
#include "headers.p4"

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {
    bit<32> entry_count;
    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition check_tcp;      
    }

    state check_tcp {
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        transition select(hdr.tcp.dstPort) {
            TYPE_STREAM: pre_parse_entry;
            TYPE_STREAM_P: pre_parse_entry;
            default: accept;
        }
    }

    state pre_parse_entry {
        meta.packet_no = 0;
        meta.packet_size = 0;
        packet.extract(hdr.entry_count);
        entry_count = hdr.entry_count.count;
        transition parse_entry;
    }

    state parse_entry {
        packet.extract(hdr.entry.next);
        meta.packet_size = meta.packet_size + 1;
        transition select (hdr.entry.last.unprocessed) {
            0: parse_entry_2;
            default: parse_entry_3;
        }        
    }

    state parse_entry_2 {
        meta.packet_no = meta.packet_no + 1;

        transition parse_entry_3;
    }

    state parse_entry_3 {
        entry_count = entry_count - 1;
        transition select (entry_count) {
            0: check_finished;
            default: parse_entry;
        }
    }

    state check_finished {
        meta.entry.setValid();
        meta.entry.key = hdr.entry.last.key;
        meta.entry.val = hdr.entry.last.val;
        meta.entry.unprocessed = 0;
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {   
    apply { 
    }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    register<bit<64>>(128) keyWindowIndex1_8;
    register<bit<32>>(1280) keyWindowIndex1_8_hst;
    register<bit<32>>(128) keyWindowIndex1_8_sum; 
    register<bit<10>>(128) keyWindowIndex1_8_pos;
    register<bit<1>>(128) keyWindowIndex1_8_rst;

    register<bit<32>>(128) joinIndex1_8;
    register<bit<32>>(1280) joinIndex1_8_key;
    register<bit<32>>(1280) joinIndex1_8_hst;
    register<bit<10>>(128) joinIndex1_8_pos;
    register<bit<1>>(128) joinIndex1_8_rst;

    action drop() {
        
    }
    
    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
    
    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    action add(bit<32> i) {
        hdr.entry[0].val = hdr.entry[0].val + i;
        meta.resubmit_invoked = true;
    }

    action key_window_aggregate() {
        bit<64> schemaKeyPair = (bit<64>)hdr.entry[0].schema;
        schemaKeyPair = schemaKeyPair << 32;
        schemaKeyPair = schemaKeyPair + (bit<64>)hdr.entry[0].key;
        bit<32> hash1 = (bit<32>)schemaKeyPair;
        hash1 = hash1 % 128;
        bit<64> window;
        keyWindowIndex1_8.read(window, hash1);

        bit<32> eq;

        if (window == schemaKeyPair) {
            eq = 1;
        } else {
            eq = 0;
        }

        keyWindowIndex1_8.write(hash1, schemaKeyPair);

        bit<32> hst;
        bit<32> sum;
        bit<10> pos;
        bit<1> rst;

        bit<32> i = hash1 * 10;

        keyWindowIndex1_8_sum.read(sum, hash1);
        keyWindowIndex1_8_pos.read(pos, hash1);
        keyWindowIndex1_8_rst.read(rst, hash1);

        
        sum = eq * sum;
        pos = (bit<10>) eq * pos;
        rst = (bit<1>) eq * rst;


        keyWindowIndex1_8_hst.read(hst, i + (bit<32>) pos);

        sum = sum - hst * (bit<32>)rst;
        sum = sum + hdr.entry[0].val;

        hst = hdr.entry[0].val;

        keyWindowIndex1_8_hst.write(i + (bit<32>) pos, hst);

        pos = pos + 1;

        if (pos >= 10) {
            rst = 1;
            pos = 0;
        }

        keyWindowIndex1_8_sum.write(hash1, sum);
        keyWindowIndex1_8_pos.write(hash1, pos);
        keyWindowIndex1_8_rst.write(hash1, rst);

        hdr.entry[0].val = sum;
    }

    action join_sum() {
        bit<32> hash1 = hdr.entry[0].schema % 128;
        bit<32> window;
        joinIndex1_8.read(window, hash1);

        bit<32> eq;

        if (window == hdr.entry[0].schema) {
            eq = 1;
        } else {
            eq = 0;
        }

        joinIndex1_8.write(hash1, hdr.entry[0].schema);

        bit<1> rst;
        bit<10> pos;
        bit<10> new_pos;
        bit<32> hst;
        bit<32> key;
        bit<32> hdr_key = hdr.entry[0].key;

        bit<32> i = hash1 * 10;

        joinIndex1_8_rst.read(rst, hash1);
        joinIndex1_8_pos.read(pos, hash1);
        joinIndex1_8_hst.read(hst, i + (bit<32>) meta.join_idx);
        joinIndex1_8_key.read(key, i + (bit<32>) meta.join_idx);

        rst = rst * (bit<1>) eq;
        pos = pos * (bit<10>) eq;
        new_pos = pos;

        meta.repeat_line_flag = true;

        if (meta.join_idx == 10 || (rst == 0 && meta.join_idx == pos)) {
            meta.repeat_line_flag = false;
            meta.join_idx = 0;

            hst = hdr.entry[0].val;
            key = hdr.entry[0].key;
            new_pos = pos + 1;

            if (new_pos == 10) {
                new_pos = 0;
                rst = 1;
            }

            meta.pop_front = 1;
        } else {
            if (key == hdr.entry[0].key) {
                meta.new_entry_valid = 1;
                meta.new_entry.schema = hdr.entry[0].schema;
                meta.new_entry.key = key;
                meta.new_entry.val = hst + hdr.entry[0].val;
            }
            meta.join_idx = meta.join_idx + 1;
        }

        joinIndex1_8_rst.write(hash1, rst);
        joinIndex1_8_pos.write(hash1, new_pos);
        joinIndex1_8_hst.write(i + (bit<32>) pos, hst);
        joinIndex1_8_key.write(i + (bit<32>) pos, key);
    }

    action next_packet() {
        hdr.entry[0].unprocessed = 0;
        meta.lineNo = 0;
        meta.repeat_line_flag = true;
    }

    table stream_ops {
        key = {
            hdr.entry[0].schema: exact;
            meta.lineNo: exact;
        }
        actions = {
            add;
            key_window_aggregate;
            join_sum;
            next_packet;
        }

        size = 1024;
        default_action = next_packet();
    }

    table acl {
        key = {
            hdr.ethernet.srcAddr: exact;
            hdr.ethernet.dstAddr: exact;
            hdr.ipv4.dstAddr: exact;
            hdr.ipv4.srcAddr: exact;
            /*hdr.tcp.srcPort: range;*/
            hdr.tcp.dstPort: exact;
        }

        actions = {
            NoAction;
            drop;
        }

        size = 1024;
        default_action = NoAction();
    }
    
    apply {
        if (hdr.tcp.isValid()) {
            acl.apply();
        }
        ipv4_lpm.apply();

        meta.new_entry.setValid();
        meta.resubmit_invoked = false;

        if (hdr.entry[0].isValid() && meta.packet_no < meta.packet_size) {
            if (hdr.entry[0].unprocessed == 0) {
                entry_t t = hdr.entry[0];
                hdr.entry.pop_front(1);
                hdr.entry_swap.setValid();
                hdr.entry_swap = t;
                meta.resubmit_invoked = true;
            } else {
                meta.repeat_line_flag = false;
                meta.new_entry_valid = 0;
                meta.pop_front = 0;
                stream_ops.apply();
                if (!meta.repeat_line_flag) {
                    meta.lineNo = meta.lineNo + 1;
                }

                if (meta.new_entry_valid == 1) {
                    meta.new_entry.setValid();
                    hdr.entry.push_front(1);
                    hdr.entry_count.count = hdr.entry_count.count + 1;
                    hdr.ipv4.totalLen = hdr.ipv4.totalLen + 13;
                    hdr.entry[0].setValid();

                    hdr.entry[0] = hdr.entry[1];

                    hdr.entry[1].schema = meta.new_entry.schema;
                    hdr.entry[1].key = meta.new_entry.key;
                    hdr.entry[1].val = meta.new_entry.val;
                }

                if (meta.pop_front == 1) {
                    hdr.entry.pop_front(1);
                    hdr.entry_count.count = hdr.entry_count.count - 1;
                }
            }
        }
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {
        if (hdr.entry[0].isValid() && (meta.resubmit_invoked || meta.packet_no < meta.packet_size)) {
            recirculate({standard_metadata, meta.lineNo, meta.join_idx});
        }

    }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.entry_count);
        packet.emit(hdr.entry);
        packet.emit(hdr.entry_swap);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;

