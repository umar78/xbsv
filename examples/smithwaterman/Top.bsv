// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;

// portz libraries
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import BlueScope::*;
import PortalMemory::*;
import Dma::*;
import DmaUtils::*;
import MemServer::*;

// generated by tool
import SmithwatermanRequestWrapper::*;
import DmaConfigWrapper::*;
import SmithwatermanIndicationProxy::*;
import DmaIndicationProxy::*;

// defined by user
import Smithwaterman::*;

typedef enum {SmithwatermanIndication, SmithwatermanRequest, DmaIndication, DmaConfig} IfcNames deriving (Eq,Bits);
typedef 1 DegPar;


module mkPortalTop(StdPortalDmaTop#(addrWidth)) 

   provisos(Add#(addrWidth, a__, 52),
	    Add#(b__, addrWidth, 64),
	    Add#(c__, 12, addrWidth),
	    Add#(addrWidth, d__, 44),
	    Add#(e__, c__, 40),
	    Add#(f__, addrWidth, 40));

   DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndication);
   DmaReadBuffer#(64,1) setupA_read_chan <- mkDmaReadBuffer();
   DmaReadBuffer#(64,1) setupB_read_chan <- mkDmaReadBuffer();
   
   ObjectReadClient#(64) setupA_read_client = setupA_read_chan.dmaClient;
   ObjectReadClient#(64) setupB_read_client = setupB_read_chan.dmaClient;
   
   Vector#(2,  ObjectReadClient#(64)) readClients;
   readClients[0] = setupA_read_client;
   readClients[1] = setupB_read_client;

   Vector#(0, ObjectWriteClient#(64)) writeClients;

   MemServer#(addrWidth,64,1) dma <- mkMemServer(dmaIndicationProxy.ifc, readClients, writeClients);
   
   DmaConfigWrapper dmaConfigWrapper <- mkDmaConfigWrapper(DmaConfig, dma.request);
   
   SmithwatermanIndicationProxy smithwatermanIndicationProxy <- mkSmithwatermanIndicationProxy(SmithwatermanIndication);
   SmithwatermanRequest smithwatermanRequest <- mkSmithwatermanRequest(smithwatermanIndicationProxy.ifc, setupA_read_chan.dmaServer, setupB_read_chan.dmaServer);
   SmithwatermanRequestWrapper smithwatermanRequestWrapper <- mkSmithwatermanRequestWrapper(SmithwatermanRequest,smithwatermanRequest);

   Vector#(4,StdPortal) portals;
   portals[0] = smithwatermanRequestWrapper.portalIfc;
   portals[1] = smithwatermanIndicationProxy.portalIfc; 
   portals[2] = dmaConfigWrapper.portalIfc;
   portals[3] = dmaIndicationProxy.portalIfc; 
   
   StdDirectory dir <- mkStdDirectory(portals);
   let ctrl_mux <- mkSlaveMux(dir,portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;
   interface leds = default_leds;
endmodule