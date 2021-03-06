// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import FIFOF::*;
import FIFO::*;
import GetPut::*;
import MemTypes::*;
import AddressGenerator::*;
import BRAM::*;


module mkCtrl2BRAM#(BRAMServer#(Bit#(bramAddrWidth), Bit#(busDataWidth)) br) (MemSlave#(busAddrWidth, busDataWidth))
   provisos(Add#(a__, bramAddrWidth, busAddrWidth));

   FIFOF#(Bit#(6))  readTagFifo <- mkFIFOF();
   FIFOF#(Bit#(6)) writeTagFifo <- mkFIFOF();
   FIFO#(Bool)     readLastFifo <- mkFIFO();
   AddressGenerator#(busAddrWidth,busDataWidth) readAddrGenerator <- mkAddressGenerator();
   AddressGenerator#(busAddrWidth,busDataWidth) writeAddrGenerator <- mkAddressGenerator();
   Bool verbose = False;

    Reg#(Bit#(32)) cycles      <- mkReg(0);
    rule count;
       cycles <= cycles + 1;
    endrule

   rule read_req;
      let addrBeat <- readAddrGenerator.addrBeat.get();
      let addr = addrBeat.addr;
      let tag = addrBeat.tag;
      let burstCount = addrBeat.bc;
      readTagFifo.enq(tag);
      readLastFifo.enq(addrBeat.last);
      Bit#(bramAddrWidth) regFileAddr = truncate(addr/fromInteger(valueOf(TDiv#(busDataWidth,8))));
      br.request.put(BRAMRequest{write:False, responseOnWrite:False, address:regFileAddr, datain:?});
      if (verbose) $display("%d read_server.readData (a) %h %d last=%d", cycles, addr, burstCount, addrBeat.last);
   endrule

   interface MemReadServer read_server;
      interface Put readReq;
	 method Action put(MemRequest#(busAddrWidth) req);
            if (verbose) $display("%d axiSlave.read.readAddr %h bc %d", cycles, req.addr, req.burstLen);
	    readAddrGenerator.request.put(req);
	 endmethod
      endinterface
      interface Get readData;
	 method ActionValue#(ObjectData#(busDataWidth)) get();
   	    let tag = readTagFifo.first;
	    readTagFifo.deq;
	    readLastFifo.deq;
            let data <- br.response.get;
            if (verbose) $display("%d read_server.readData (b) %h", cycles, data);
            return ObjectData { data: data, tag: tag, last: readLastFifo.first };
	 endmethod
      endinterface
   endinterface
   interface MemWriteServer write_server;
      interface Put writeReq;
	 method Action put(MemRequest#(busAddrWidth) req);
	    writeAddrGenerator.request.put(req);
            if (verbose) $display("%d write_server.writeAddr %h bc %d", cycles, req.addr, req.burstLen);
	 endmethod
      endinterface
      interface Put writeData;
	 method Action put(ObjectData#(busDataWidth) resp);
	    let addrBeat <- writeAddrGenerator.addrBeat.get();
	    let addr = addrBeat.addr;
	    Bit#(bramAddrWidth) regFileAddr = truncate(addr/fromInteger(valueOf(TDiv#(busDataWidth,8))));
            br.request.put(BRAMRequest{write:True, responseOnWrite:False, address:regFileAddr, datain:resp.data});
            if (verbose) $display("%d write_server.writeData %h %h %d", cycles, addr, resp.data, addrBeat.bc);
            if (addrBeat.last)
               writeTagFifo.enq(addrBeat.tag);
	 endmethod
      endinterface
      interface Get writeDone;
	 method ActionValue#(Bit#(6)) get();
	    writeTagFifo.deq;
            return writeTagFifo.first;
	 endmethod
      endinterface
   endinterface
endmodule

