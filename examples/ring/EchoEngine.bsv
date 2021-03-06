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
import RingTypes::*;
import ClientServer::*;
import GetPut::*;
import GetPutF::*;

module mkEchoEngine ( ServerF#(Bit#(64), Bit#(64)));
   FIFOF#(Bit#(64)) f_echo <- mkSizedFIFOF(16);   // buffer incoming requests
   
   PutF#(Bit#(64)) req_ifc <- toPutF(toPut(f_echo));
   GetF#(Bit#(64)) resp_ifc <- toGetF(toGet(f_echo));
   
   interface PutF request = req_ifc;
   interface GetF response = resp_ifc;

endmodule: mkEchoEngine

