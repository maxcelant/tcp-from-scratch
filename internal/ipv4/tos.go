package ipv4

type TypeOfService struct {
	raw         byte
	Precedence  uint8
	Delay       uint8
	Throughput  uint8
	Reliability uint8
}

func (tos *TypeOfService) Process() error {
	tos.Precedence = tos.raw >> 5 // first 3 bits
	tos.Delay = (tos.raw >> 4) & 0x1
	tos.Throughput = (tos.raw >> 3) & 0x1
	tos.Reliability = (tos.raw >> 2) & 0x1
}
