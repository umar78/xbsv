// Copyright (c) 2014 Quanta Research Cambridge, Inc.

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

import Vector            :: *;
import GetPut            :: *;
import Connectable       :: *;
import Xilinx            :: *;
import XilinxCells       :: *;
import X7PcieSplitter    :: *;
import Portal            :: *;
import Leds              :: *;
import Top               :: *;
import AxiSlaveEngine    :: *;
import AxiMasterEngine   :: *;
import AxiMasterSlave    :: *;
import AxiDma            :: *;
import AxiCsr            :: *;
import HDMI::*;
import Imageon::*;

typedef (function Module#(PortalTop#(40, dsz, ipins)) mkPortalTop(Clock io_vita_clk)) MkPortalTop#(numeric type dsz, type ipins);

`ifdef Artix7
typedef 4 PcieLanes;
typedef 4 NumLeds;
`else
typedef 8 PcieLanes;
typedef 8 NumLeds;
`endif

interface PcieTop#(type ipins);
   (* prefix="PCIE" *)
   interface PCIE_EXP#(PcieLanes) pcie;
   (* always_ready *)
   method Bit#(NumLeds) leds();
   interface ipins       pins;
endinterface

(* no_default_clock, no_default_reset *)
module  mkPcieTopFromPortal #(Clock pci_sys_clk_p, Clock pci_sys_clk_n,
				      Clock sys_clk_p,     Clock sys_clk_n,
				      Clock io_vita_clk_out_p, Clock io_vita_clk_out_n,
				      Reset pci_sys_reset_n,
				      MkPortalTop#(dsz, ipins) mkPortalTop)
   (PcieTop#(ipins))
   provisos (Mul#(TDiv#(dsz, 32), 32, dsz),
	     Add#(b__, 32, dsz),
	     Add#(c__, dsz, 256),
	     Add#(d__, TMul#(8, TDiv#(dsz, 32)), 64),
	     Add#(e__, TMul#(32, TDiv#(dsz, 32)), 256),
	     Add#(f__, TDiv#(dsz, 32), 8),
	     Mul#(TDiv#(dsz, 8), 8, dsz)
      );

   let contentId = 0;

   X7PcieSplitter#(PcieLanes) x7pcie <- mkX7PcieSplitter(pci_sys_clk_p, pci_sys_clk_n, sys_clk_p, sys_clk_n, pci_sys_reset_n,
							 contentId );
   
   // instantiate user portals
   Clock io_vita_clk <- XilinxCells::mkClockIBUFDS(io_vita_clk_out_p, io_vita_clk_out_n);
   IDELAYCTRL idel <- mkIDELAYCTRL(2, clocked_by x7pcie.clock200, reset_by x7pcie.portalReset);
   let portalTop <- mkPortalTop(io_vita_clk, clocked_by x7pcie.clock125, reset_by x7pcie.portalReset);

   AxiSlaveEngine#(dsz) axiSlaveEngine <- mkAxiSlaveEngine(x7pcie.pciId(), clocked_by x7pcie.clock125, reset_by x7pcie.reset125);
   AxiMasterEngine axiMasterEngine <- mkAxiMasterEngine(x7pcie.pciId(), clocked_by x7pcie.clock125, reset_by x7pcie.reset125);

   mkConnection(tpl_1(x7pcie.slave), tpl_2(axiSlaveEngine.tlps), clocked_by x7pcie.clock125, reset_by x7pcie.reset125);
   mkConnection(tpl_1(axiSlaveEngine.tlps), tpl_2(x7pcie.slave), clocked_by x7pcie.clock125, reset_by x7pcie.reset125);

   Axi3Master#(40,dsz,6) m_axi <- mkAxiDmaMaster(portalTop.master,clocked_by x7pcie.clock125, reset_by x7pcie.portalReset);
   mkConnection(m_axi, axiSlaveEngine.slave, clocked_by x7pcie.clock125, reset_by x7pcie.reset125);

   mkConnection(tpl_1(x7pcie.master), axiMasterEngine.tlp_in);
   mkConnection(axiMasterEngine.tlp_out, tpl_2(x7pcie.master));

   Axi3Slave#(32,32,12) ctrl <- mkAxiDmaSlave(portalTop.slave, clocked_by x7pcie.clock125, reset_by x7pcie.reset125);
   mkConnection(axiMasterEngine.master, ctrl, clocked_by x7pcie.clock125, reset_by x7pcie.reset125);

   // going from level to edge-triggered interrupt
   Vector#(15, Reg#(Bool)) interruptRequested <- replicateM(mkReg(False, clocked_by x7pcie.clock125, reset_by x7pcie.reset125));
   for (Integer i = 0; i < 15; i = i + 1) begin
      // intr_num 0 for the directory
      Integer intr_num = i+1;
      MSIX_Entry msixEntry = x7pcie.msixEntry[intr_num];
      rule interruptRequest;
	 if (portalTop.interrupt[i] && !interruptRequested[i])
	    axiMasterEngine.interruptRequest.put(tuple2({msixEntry.addr_hi, msixEntry.addr_lo}, msixEntry.msg_data));
	 interruptRequested[i] <= portalTop.interrupt[i];
      endrule
   end

   interface pcie = x7pcie.pcie;
   //interface ddr3 = x7pcie.ddr3;
   method Bit#(NumLeds) leds();
      return extend({x7pcie.isLinkUp(),3'd2});
   endmethod
   interface pins = portalTop.pins;

endmodule: mkPcieTopFromPortal


(* synthesize *)
module mkSynthesizeablePortalTop#(Clock io_vita_clk)(PortalTop#(40, 64, ImageCapturePins));
   let top <- mkPortalTop(io_vita_clk);
   interface master = top.master;
   interface slave = top.slave;
   interface interrupt = top.interrupt;
   interface leds = top.leds;
   interface pins = top.pins;
endmodule

module mkImageonPcieTop #(Clock pci_sys_clk_p, Clock pci_sys_clk_n,
   Clock sys_clk_p,     Clock sys_clk_n,
   Clock io_vita_clk_out_p, Clock io_vita_clk_out_n,
   Reset pci_sys_reset_n)
   (PcieTop#(ImageCapturePins));

   let top <- mkPcieTopFromPortal(pci_sys_clk_p, pci_sys_clk_n, sys_clk_p, sys_clk_n,
				  io_vita_clk_out_p, io_vita_clk_out_n,
				  pci_sys_reset_n,
				  mkSynthesizeablePortalTop);
   return top;
endmodule: mkImageonPcieTop
