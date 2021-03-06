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

// BSV Libraries
import FIFO::*;
import Vector::*;
import List::*;
import GetPut::*;
import ClientServer::*;
import Assert::*;
import StmtFSM::*;

// CONNECTAL Libraries
import MemTypes::*;
import PortalMemory::*;
import MMU::*;
import MemServerInternal::*;

function Put#(t) null_put();
   return (interface Put;
              method Action put(t x) if (False);
                 noAction;
              endmethod
           endinterface);
endfunction

function Get#(t) null_get();
   return (interface Get;
              method ActionValue#(t) get() if (False);
                 return ?;
              endmethod
           endinterface);
endfunction

function  MemWriteClient#(addrWidth, busWidth) null_mem_write_client();
   return (interface MemWriteClient;
              interface Get writeReq = null_get;
              interface Get writeData = null_get;
              interface Put writeDone = null_put;
           endinterface);
endfunction

function  MemReadClient#(addrWidth, busWidth) null_mem_read_client();
   return (interface MemReadClient;
              interface Get readReq = null_get;
              interface Put readData = null_put;
           endinterface);
endfunction

interface MemServer#(numeric type addrWidth, numeric type dataWidth, numeric type nMasters);
   interface DmaDebugRequest request;
   interface Vector#(nMasters,MemMaster#(addrWidth, dataWidth)) masters;
endinterface
		 	 
   
typedef struct {
   DmaErrorType errorType;
   Bit#(32) pref;
   } DmaError deriving (Bits);

module mkMemServerRW#(DmaDebugIndication dmaIndication,
		      Vector#(numReadClients, ObjectReadClient#(dataWidth)) readClients,
		      Vector#(numWriteClients, ObjectWriteClient#(dataWidth)) writeClients,
		      Vector#(numMMUs,MMU#(PhysAddrWidth)) mmus)
   (MemServer#(PhysAddrWidth, dataWidth, nMasters))
   
   provisos (Add#(1,a__,dataWidth),
	     Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	     Mul#(nwc, nMasters, numWriteClients),
	     Mul#(nrc, nMasters, numReadClients),
	     Add#(b__, TLog#(nrc), 6),
	     Add#(c__, TLog#(nwc), 6),
	     Add#(TLog#(TDiv#(dataWidth, 8)), d__, BurstLenSize)
	     );

   MemServer#(PhysAddrWidth,dataWidth,nMasters) reader <- mkMemServerR(dmaIndication,  readClients, mmus);
   MemServer#(PhysAddrWidth,dataWidth,nMasters) writer <- mkMemServerW(dmaIndication, writeClients, mmus);
   
   FIFO#(DmaError) dmaErrorFifo <- mkFIFO();
   rule dmaError;
      let error <- toGet(dmaErrorFifo).get();
      dmaIndication.error(extend(pack(error.errorType)), error.pref, 0, 0);
   endrule

   function MemMaster#(PhysAddrWidth,dataWidth) mkm(Integer i) = (interface MemMaster#(PhysAddrWidth,dataWidth);
								 interface MemReadClient read_client = reader.masters[i].read_client;
								 interface MemWriteClient write_client = writer.masters[i].write_client;
							      endinterface);

   interface DmaDebugRequest request;
      method Action getStateDbg(ChannelType rc);
	 if (rc == Read)
	    reader.request.getStateDbg(rc);
	 else
	    writer.request.getStateDbg(rc);
      endmethod
      method Action getMemoryTraffic(ChannelType rc);
	 if (rc == Read) 
	    reader.request.getMemoryTraffic(rc);
	 else 
	    writer.request.getMemoryTraffic(rc);
      endmethod
      method Action addrRequest(Bit#(32) pointer, Bit#(32) offset);
	 writer.request.addrRequest(pointer,offset);
      endmethod
   endinterface
   interface masters = map(mkm,genVector);
endmodule
	
module mkMemServerR#(DmaDebugIndication dmaIndication,
		     Vector#(numReadClients, ObjectReadClient#(dataWidth)) readClients,
		     Vector#(numMMUs,MMU#(PhysAddrWidth)) mmus)
   (MemServer#(PhysAddrWidth, dataWidth, nMasters))
   
   provisos (Add#(1,a__,dataWidth),
	     Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	     Mul#(nrc, nMasters, numReadClients),
	     Add#(b__, TLog#(nrc), 6),
	     Add#(TLog#(TDiv#(dataWidth, 8)), c__, BurstLenSize)
	     );


   FIFO#(Bit#(32))   addrReqFifo <- mkFIFO;
   Reg#(Bit#(8)) dbgPtr <- mkReg(0);
   Reg#(Bit#(8)) trafficPtr <- mkReg(0);
   Reg#(Bit#(64)) trafficAccum <- mkReg(0);

   
   function a selectClient(Vector#(n, a) in, Integer r, Integer i, Integer j); return in[j * r + i]; endfunction
   function Vector#(nrc, a) selectClients(Vector#(numReadClients, a) vec, Integer m);
      return genWith(selectClient(vec, valueOf(nMasters), m));
   endfunction
   Vector#(nMasters,Vector#(nrc, ObjectReadClient#(dataWidth))) client_bins = genWith(selectClients(readClients));

   module foo#(Integer i) (MMUAddrServer#(PhysAddrWidth,nMasters));
      let rv <- mkMMUAddrServer(mmus[i].addr[0]);
      return rv;
   endmodule
   Vector#(numMMUs,MMUAddrServer#(PhysAddrWidth,nMasters)) mmu_servers <- mapM(foo,genVector);

   Vector#(nMasters,MemReadInternal#(PhysAddrWidth,dataWidth)) readers;
   for(Integer i = 0; i < valueOf(nMasters); i = i+1) begin
      Vector#(numMMUs,Server#(ReqTup,Bit#(PhysAddrWidth))) ss;
      for(Integer j = 0; j < valueOf(numMMUs); j=j+1)
	 ss[j] = mmu_servers[j].servers[i];
      readers[i] <- mkMemReadInternal(client_bins[i], dmaIndication, ss);
   end
   
   rule mmuEntry;
      addrReqFifo.deq;
      let physAddr <- mmus[addrReqFifo.first[31:16]].addr[0].response.get;
      dmaIndication.addrResponse(zeroExtend(physAddr));
   endrule
   
   function MemMaster#(PhysAddrWidth,dataWidth) mkm(Integer i) = (interface MemMaster#(PhysAddrWidth,dataWidth);
								 interface MemReadClient read_client = readers[i].read_client;
								 interface MemWriteClient write_client = null_mem_write_client;
							      endinterface);

   Stmt dbgStmt = seq
		     for(dbgPtr <= 0; dbgPtr < fromInteger(valueOf(nMasters)); dbgPtr <= dbgPtr+1)
			(action
			    let rv <- readers[dbgPtr].dbg.dbg;
			    dmaIndication.reportStateDbg(rv);
			 endaction);
		  endseq;
   FSM dbgFSM <- mkFSM(dbgStmt);

   Stmt trafficStmt = seq
			 trafficAccum <= 0;
			 for(trafficPtr <= 0; trafficPtr < fromInteger(valueOf(nMasters)); trafficPtr <= trafficPtr+1)
			    (action
				let rv <- readers[trafficPtr].dbg.getMemoryTraffic();
				trafficAccum <= trafficAccum + rv;
			     endaction);
			 dmaIndication.reportMemoryTraffic(trafficAccum);
		      endseq;
   FSM trafficFSM <- mkFSM(trafficStmt);
      
   FIFO#(DmaError) dmaErrorFifo <- mkFIFO();
   rule dmaError;
      let error <- toGet(dmaErrorFifo).get();
      dmaIndication.error(extend(pack(error.errorType)), error.pref, 0, 0);
   endrule

   interface DmaDebugRequest request;
      method Action getStateDbg(ChannelType rc);
	 if (rc == Read)
	    dbgFSM.start;
      endmethod
      method Action getMemoryTraffic(ChannelType rc);
	 if (rc == Read)
	    trafficFSM.start;
      endmethod
      method Action addrRequest(Bit#(32) pointer, Bit#(32) offset);
	 addrReqFifo.enq(pointer);
	 mmus[pointer[31:16]].addr[0].request.put(ReqTup{id:truncate(pointer), off:extend(offset)});
      endmethod
   endinterface
   interface masters = map(mkm,genVector);
endmodule
	
module mkMemServerW#(DmaDebugIndication dmaIndication,
		     Vector#(numWriteClients, ObjectWriteClient#(dataWidth)) writeClients,
		     Vector#(numMMUs,MMU#(PhysAddrWidth)) mmus)
   (MemServer#(PhysAddrWidth, dataWidth, nMasters))
   
   provisos (Add#(1,a__,dataWidth),
	     Mul#(TDiv#(dataWidth, 8), 8, dataWidth),
	     Mul#(nwc, nMasters, numWriteClients),
	     Add#(b__, TLog#(nwc), 6)
	     );

   FIFO#(Bit#(32))   addrReqFifo <- mkFIFO;
   Reg#(Bit#(8)) dbgPtr <- mkReg(0);
   Reg#(Bit#(8)) trafficPtr <- mkReg(0);
   Reg#(Bit#(64)) trafficAccum <- mkReg(0);
   
   function a selectClient(Vector#(n, a) in, Integer r, Integer i, Integer j); return in[j * r + i]; endfunction
   function Vector#(nwc, a) selectClients(Vector#(numWriteClients, a) vec, Integer m);
      return genWith(selectClient(vec, valueOf(nMasters), m));
   endfunction
   Vector#(nMasters,Vector#(nwc, ObjectWriteClient#(dataWidth))) client_bins = genWith(selectClients(writeClients));

   module foo#(Integer i) (MMUAddrServer#(PhysAddrWidth,nMasters));
      let rv <- mkMMUAddrServer(mmus[i].addr[1]);
      return rv;
   endmodule
   Vector#(numMMUs,MMUAddrServer#(PhysAddrWidth,nMasters)) mmu_servers <- mapM(foo,genVector);

   Vector#(nMasters,MemWriteInternal#(PhysAddrWidth,dataWidth)) writers;
   for(Integer i = 0; i < valueOf(nMasters); i = i+1) begin
      Vector#(numMMUs,Server#(ReqTup,Bit#(PhysAddrWidth))) ss;
      for(Integer j = 0; j < valueOf(numMMUs); j=j+1)
	 ss[j] = mmu_servers[j].servers[i];
      writers[i] <- mkMemWriteInternal(client_bins[i], dmaIndication, ss);
   end
   
   rule mmuEntry;
      addrReqFifo.deq;
      let physAddr <- mmus[addrReqFifo.first[31:16]].addr[1].response.get;
      dmaIndication.addrResponse(zeroExtend(physAddr));
   endrule

   function MemMaster#(PhysAddrWidth,dataWidth) mkm(Integer i) = (interface MemMaster#(PhysAddrWidth,dataWidth);
								 interface MemReadClient read_client = null_mem_read_client;
								 interface MemWriteClient write_client = writers[i].write_client;
							      endinterface);
   
   Stmt dbgStmt = seq
		     for(dbgPtr <= 0; dbgPtr < fromInteger(valueOf(nMasters)); dbgPtr <= dbgPtr+1)
			(action
			    let rv <- writers[dbgPtr].dbg.dbg;
			    dmaIndication.reportStateDbg(rv);
			 endaction);
		  endseq;
   FSM dbgFSM <- mkFSM(dbgStmt);

   Stmt trafficStmt = seq
			 trafficAccum <= 0;
			 for(trafficPtr <= 0; trafficPtr < fromInteger(valueOf(nMasters)); trafficPtr <= trafficPtr+1)
			    (action
				let rv <- writers[trafficPtr].dbg.getMemoryTraffic();
				trafficAccum <= trafficAccum + rv;
			     endaction);
			 dmaIndication.reportMemoryTraffic(trafficAccum);
		      endseq;
   FSM trafficFSM <- mkFSM(trafficStmt);

   FIFO#(DmaError) dmaErrorFifo <- mkFIFO();
   rule dmaError;
      let error <- toGet(dmaErrorFifo).get();
      dmaIndication.error(extend(pack(error.errorType)), error.pref, 0, 0);
   endrule

   interface DmaDebugRequest request;
      method Action getStateDbg(ChannelType rc);
	 if (rc == Write)
	    dbgFSM.start;
      endmethod
      method Action getMemoryTraffic(ChannelType rc);
	 if (rc == Write) 
	    trafficFSM.start;
      endmethod
      method Action addrRequest(Bit#(32) pointer, Bit#(32) offset);
	 addrReqFifo.enq(pointer);
	 mmus[pointer[31:16]].addr[1].request.put(ReqTup{id:truncate(pointer), off:extend(offset)});
      endmethod
   endinterface
   interface masters = map(mkm,genVector);
endmodule

