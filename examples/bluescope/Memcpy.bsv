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

import Vector::*;
import FIFOF::*;
import GetPut::*;
import FIFO::*;
import Connectable::*;

import PortalMemory::*;
import Dma::*;
import BlueScope::*;
import MemreadEngine::*;
import MemwriteEngine::*;


interface MemcpyRequest;
   method Action startCopy(Bit#(32) wrPointer, Bit#(32) rdPointer, Bit#(32) numWords, Bit#(32) burstLen);
endinterface

interface MemcpyIndication;
   method Action started();
   method Action done();
endinterface

interface Memcpy;
   interface MemcpyRequest request;
   interface ObjectReadClient#(64) readClient;
   interface ObjectWriteClient#(64) writeClient;
endinterface

module mkMemcpyRequest#(MemcpyIndication indication,
			BlueScope#(64) bs)(Memcpy);
   
   let readFifo <- mkFIFOF;
   let writeFifo <- mkFIFOF;

   MemreadEngine#(64) re <- mkMemreadEngine(1, readFifo);
   MemwriteEngine#(64) we <- mkMemwriteEngine(1, writeFifo);

   Reg#(Bit#(32))          iterCnt <- mkReg(0);
   Reg#(Bit#(32))         numWords <- mkReg(0);
   Reg#(ObjectPointer)      rdPointer <- mkReg(0);
   Reg#(ObjectPointer)      wrPointer <- mkReg(0);
   Reg#(Bit#(32))         burstLen <- mkReg(0);
      
   rule start(iterCnt > 0);
      re.start(rdPointer, 0, numWords*4, burstLen*4);
      we.start(wrPointer, 0, numWords*4, burstLen*4);
      iterCnt <= iterCnt-1;
   endrule

   rule finish;
      let rv0 <- re.finish;
      let rv1 <- we.finish;
      if(iterCnt==0) begin
	 indication.done;
      end
   endrule
   
   rule xfer;
      //$display("xfer: %h", readFifo.first);
      readFifo.deq;
      writeFifo.enq(readFifo.first);
      bs.dataIn(readFifo.first,readFifo.first);
   endrule
   
   interface MemcpyRequest request;
      method Action startCopy(Bit#(32) wp, Bit#(32) rp, Bit#(32) nw, Bit#(32) bl);
	 $display("startCopy wrPointer=%d rdPointer=%d numWords=%h burstLen=%d", wp, rp, nw, bl);
	 indication.started;
	 // initialized
	 wrPointer <= wp;
	 rdPointer <= rp;
	 numWords  <= nw;
	 iterCnt   <= 1;
	 burstLen  <= bl;
      endmethod
   endinterface
   interface readClient = re.dmaClient;
   interface writeClient = we.dmaClient;
endmodule

