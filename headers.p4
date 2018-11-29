/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/
const bit<16> TYPE_IPV4 = 0x800;
const bit<16> TYPE_STREAM = 0x1234;
const bit<16> TYPE_STREAM_P = 0x1235;

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;
typedef bit<32> portAddr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4> version;
    bit<4> ihl;
    bit<8> diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

header tcp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4>  dataOffset;
    bit<3>  res;
    bit<9>  cntrl;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

header entry_t {
    bit<32> schema;
    bit<32> key;
    bit<32> val;
    bit<8> unprocessed;
}

header program_t {
    bit<32> lineNo;
    bit<32> stackLen;
}

header stack_t {
    bit<1> bos;
    bit<32> val;
}

header entry_count_t {
    bit<32> count;
}

struct metadata {
    bit<32> lineNo;
    bool resubmit_invoked;
    bit<32> packet_no;
    bit<32> packet_size;
    bool repeat_line_flag;
    entry_t entry;
    bit<10> join_idx;
    entry_t new_entry;
    bit<1> new_entry_valid;
    bit<1> pop_front;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    tcp_t        tcp;
    entry_count_t entry_count;
    entry_t[10] entry;
    entry_t entry_swap;
}
