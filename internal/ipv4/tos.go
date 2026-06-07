package ipv4

import (
	"fmt"
)

type TypeOfService struct {
	raw         byte
	Precedence  uint8
	Delay       uint8
	Throughput  uint8
	Reliability uint8
}

// Type of Service:  8 bits
//
//   The Type of Service provides an indication of the abstract
//   parameters of the quality of service desired.  These parameters are
//   to be used to guide the selection of the actual service parameters
//   when transmitting a datagram through a particular network.  Several
//   networks offer service precedence, which somehow treats high
//   precedence traffic as more important than other traffic (generally
//   by accepting only traffic above a certain precedence at time of high
//   load).  The major choice is a three way tradeoff between low-delay,
//   high-reliability, and high-throughput.
//
//     Bits 0-2:  Precedence.
//     Bit    3:  0 = Normal Delay,      1 = Low Delay.
//     Bits   4:  0 = Normal Throughput, 1 = High Throughput.
//     Bits   5:  0 = Normal Relibility, 1 = High Relibility.
//     Bit  6-7:  Reserved for Future Use.
//
//        0     1     2     3     4     5     6     7
//     +-----+-----+-----+-----+-----+-----+-----+-----+
//     |                 |     |     |     |     |     |
//     |   PRECEDENCE    |  D  |  T  |  R  |  0  |  0  |
//     |                 |     |     |     |     |     |
//     +-----+-----+-----+-----+-----+-----+-----+-----+
//
//       Precedence
//
//         111 - Network Control
//         110 - Internetwork Control
//         101 - CRITIC/ECP
//         100 - Flash Override
//         011 - Flash
//         010 - Immediate
//         001 - Priority
//         000 - Routine
//

var precendenceTypes = [8]string{
	"Routine",
	"Priority",
	"Immediate",
	"Flash",
	"FlashOverride",
	"CRITIC_ECP",
	"InternetworkControl",
	"NetworkControl",
}

func (tos *TypeOfService) Process() *TypeOfService {
	tos.Precedence = tos.raw >> 5 // first 3 bits
	tos.Delay = (tos.raw >> 4) & 0x1
	tos.Throughput = (tos.raw >> 3) & 0x1
	tos.Reliability = (tos.raw >> 2) & 0x1
	return tos
}

func (tos TypeOfService) Print() {
	fmt.Printf("Type of Service:\n")
	fmt.Printf("	Precedence: %s\n", precendenceTypes[tos.Precedence])
	fmt.Printf("	Delay: %d\n", tos.Delay)
	fmt.Printf("	Throughput: %d\n", tos.Throughput)
	fmt.Printf("	Reliability: %d\n", tos.Reliability)
}
