
## hardware interfaces invoked from software (requests)
S2H = SerialconfigRequest
## software interfaces invoked from hardware (indications)
H2S = SerialconfigIndication
## all the BSV files to be scanned for types and interfaces
BSVFILES = Serialconfig.bsv Top.bsv
## the source files in the example
CPPFILES=testserialconfig.cpp
## uncomment the following line to enable AXI trace
# CONNECTALFLAGS="--bscflags=-D TRACE_AXI"
NUMBER_OF_MASTERS =0

include ../../Makefile.connectal

