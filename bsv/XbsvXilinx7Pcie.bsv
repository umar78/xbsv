////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2012  Bluespec, Inc.  ALL RIGHTS RESERVED.
////////////////////////////////////////////////////////////////////////////////
//  Filename      : XbsvXilinx7PCIE.bsv
//  Description   : 
////////////////////////////////////////////////////////////////////////////////
package XbsvXilinx7Pcie;

// Notes :

////////////////////////////////////////////////////////////////////////////////
/// Imports
////////////////////////////////////////////////////////////////////////////////
import Clocks            ::*;
import Vector            ::*;
import Connectable       ::*;
import GetPut            ::*;
import Reserved          ::*;
import TieOff            ::*;
import DefaultValue      ::*;
import DReg              ::*;
import Gearbox           ::*;
import FIFO              ::*;
import FIFOF             ::*;
import SpecialFIFOs      ::*;

import XilinxCells       ::*;
import PCIE              ::*;

////////////////////////////////////////////////////////////////////////////////
/// Types
////////////////////////////////////////////////////////////////////////////////
typedef struct {
   Bit#(64)      data;
   Bool          sof;
   Bool          eof;
   Bit#(8)       hit;
   Bit#(1)       rrem;
   Bool          errfwd;
   Bool          ecrcerr;
   Bool          disc;
} AxiRx deriving (Bits, Eq);

typedef struct {
   Bit#(64)      data;
   Bool          sof;
   Bool          eof;
   Bit#(1)       rem;
} AxiTx deriving (Bits, Eq);		

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////
(* always_ready, always_enabled *)
interface PCIE_X7#(numeric type lanes);
   interface PCIE_EXP#(lanes) pcie;
   interface PCIE_TRN_X7      trn;
   interface PCIE_TX_X7       tx;
   interface PCIE_RX_X7       rx;
   interface PCIE_PL_X7       pl;
   interface PCIE_CFG_X7      cfg;
   interface PCIE_INT_X7      cfg_interrupt;
   interface PCIE_ERR_X7      cfg_err;
endinterface

(* always_ready, always_enabled *)
interface PCIE_TRN_X7;
   interface Clock            clk;
   interface Reset            reset;
   method    Bool             lnk_up;
   method    Bit#(8)          fc_ph;
   method    Bit#(12)         fc_pd;
   method    Bit#(8)          fc_nph;
   method    Bit#(12)         fc_npd;
   method    Bit#(8)          fc_cplh;
   method    Bit#(12)         fc_cpld;
   method    Action           fc_sel(FlowControlInfoSelect i);
endinterface

(* always_ready, always_enabled *)
interface PCIE_TX_X7;
   method    Action           tdata(Bit#(64) i);
   method    Action           tsof(Bool i);
   method    Action           teof(Bool i);
   method    Action           trem(Bit#(1) i);
   method    Action           tecrc_gen(Bool i);
   method    Action           tstr(Bool i);
   method    Action           tdisc(Bool i);
   method    Action           terrfwd(Bool i);
   method    Action           tvalid(Bool i);
   method    Bool             tready();
   method    Bit#(6)          tbuf_av();
   method    Bool             terr_drop();
   method    Bool             tcfg_req();
   method    Action           tcfg_gnt(Bool i);
endinterface

(* always_ready, always_enabled *)
interface PCIE_RX_X7;
   method    Bit#(64)         rdata();
   method    Bool             rsof();
   method    Bool             reof();
   method    Bit#(8)          rhit();
   method    Bit#(1)          rrem(); // 2 bits for 128-bit data, 1 bit for 64-bit data
   method    Bool             disc();
   method    Bool             errfwd();
   method    Bool             ecrcerr();
   method    Bool             rvalid();
   method    Action           rready(Bool i);
   method    Action           rnp_ok(Bool i);
   method    Action           rnp_req(Bool i);
endinterface

(* always_ready, always_enabled *)
interface PCIE_PL_X7;
   method    Bit#(3)     initial_link_width;
   method    Bool        phy_link_up;
   method    Bit#(2)     lane_reversal_mode;
   method    Bit#(1)     link_gen2_capable;
   method    Bit#(1)     link_partner_gen2_supported;
   method    Bit#(1)     link_upcfg_capable;
   method    Bit#(1)     sel_link_rate;
   method    Bit#(2)     sel_link_width;
   method    Bit#(6)     ltssm_state;
   method    Bit#(2)     rx_pm_state;
   method    Bit#(3)     tx_pm_state;
   method    Action      directed_link_auton(Bit#(1) i);
   method    Action      directed_link_change(Bit#(2) i);
   method    Action      directed_link_speed(Bit#(1) i);
   method    Action      directed_link_width(Bit#(2) i);
   method    Bit#(1)     directed_change_done;
   method    Action      upstream_prefer_deemph(Bit#(1) i);
   method    Bit#(1)     received_hot_rst;   
endinterface

(* always_ready, always_enabled *)
interface PCIE_CFG_X7;
   method    Bit#(32)    dout;
   method    Bit#(1)     rd_wr_done;
   method    Action      di(Bit#(32) i);
   method    Action      dwaddr(Bit#(10) i);
   method    Action      byte_en(Bit#(4) i);
   method    Action      wr_en(Bit#(1) i);
   method    Action      rd_en(Bit#(1) i);
   method    Action      wr_readonly(Bit#(1) i);
   method    Bit#(8)     bus_number;
   method    Bit#(5)     device_number;
   method    Bit#(3)     function_number;
   method    Bit#(16)    status;
   method    Bit#(16)    command;
   method    Bit#(16)    dstatus;
   method    Bit#(16)    dcommand;
   method    Bit#(16)    dcommand2;
   method    Bit#(16)    lstatus;
   method    Bit#(16)    lcommand;
   method    Bit#(1)     aer_ecrc_gen_en;
   method    Bit#(1)     aer_ecrc_check_en;
   method    Bit#(3)     pcie_link_state;
   method    Action      trn_pending(Bit#(1) i);
   method    Action      dsn(Bit#(64) i);
   method    Bit#(1)     pmcsr_pme_en;
   method    Bit#(1)     pmcsr_pme_status;
   method    Bit#(2)     pmcsr_powerstate;
   method    Action      pm_halt_aspm_l0s(Bit#(1) i);
   method    Action      pm_halt_aspm_l1(Bit#(1) i);
   method    Action      pm_force_state(Bit#(2) i);
   method    Action      pm_force_state_en(Bit#(1) i);
   method    Bit#(1)     received_func_lvl_rst;
   method    Bit#(7)     vc_tcvc_map;
   method    Bit#(1)     to_turnoff;
   method    Action      turnoff_ok(Bit#(1) i);
   method    Action      pm_wake(Bit#(1) i);
endinterface

(* always_ready, always_enabled *)
interface PCIE_INT_X7;
   method    Action      req(Bit#(1) i);
   method    Bit#(1)     rdy;
   method    Action      assrt(Bit#(1) i);
   method    Action      di(Bit#(8) i);
   method    Bit#(8)     dout;
   method    Bit#(3)     mmenable;
   method    Bit#(1)     msienable;
   method    Bit#(1)     msixenable;
   method    Bit#(1)     msixfm;
   method    Action      pciecap_msgnum(Bit#(5) i);
   method    Action      stat(Bit#(1) i);
endinterface

(* always_ready, always_enabled *)
interface PCIE_ERR_X7;
   method    Action      ecrc(Bit#(1) i);
   method    Action      ur(Bit#(1) i);
   method    Action      cpl_timeout(Bit#(1) i);
   method    Action      cpl_unexpect(Bit#(1) i);
   method    Action      cpl_abort(Bit#(1) i);
   method    Action      posted(Bit#(1) i);
   method    Action      cor(Bit#(1) i);
   method    Action      atomic_egress_blocked(Bit#(1) i);
   method    Action      internal_cor(Bit#(1) i);
   method    Action      internal_uncor(Bit#(1) i);
   method    Action      malformed(Bit#(1) i);
   method    Action      mc_blocked(Bit#(1) i);
   method    Action      poisoned(Bit#(1) i);
   method    Action      no_recovery(Bit#(1) i);
   method    Action      tlp_cpl_header(Bit#(48) i);
   method    Bit#(1)     cpl_rdy;
   method    Action      locked(Bit#(1) i);
   method    Action      aer_headerlog(Bit#(128) i);
   method    Bit#(1)     aer_headerlog_set;
   method    Action      aer_interrupt_msgnum(Bit#(5) i);
   method    Action      acs(Bit#(1) i);
endinterface

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
/// Implementation
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
import "BVI" xilinx_x7_pcie_wrapper =
module vMkXilinx7PCIExpress#(PCIEParams params)(PCIE_X7#(lanes))
   provisos( Add#(1, z, lanes));
   
   // PCIe wrapper takes active low reset
   let sys_reset_n <- exposeCurrentReset;
   
   default_clock clk(sys_clk); // 100 MHz refclk
   default_reset rstn(sys_reset_n) = sys_reset_n;
   
   parameter PL_FAST_TRAIN = (params.fast_train_sim_only) ? "TRUE" : "FALSE";
   parameter PCIE_EXT_CLK  = "TRUE";
   parameter BAR0 = 32'hFFF00004;
   parameter BAR1 = 32'hFFFFFFFF;
   parameter BAR2 = 32'hFF000004;
   parameter BAR3 = 32'hFFFFFFFF;
   
   interface PCIE_EXP pcie;
      method                            rxp(pci_exp_rxp) enable((*inhigh*)en0)                              reset_by(no_reset);
      method                            rxn(pci_exp_rxn) enable((*inhigh*)en1)                              reset_by(no_reset);
      method pci_exp_txp                txp                                                                 reset_by(no_reset);
      method pci_exp_txn                txn                                                                 reset_by(no_reset);
   endinterface
   
   interface PCIE_TRN_X7 trn;
      output_clock                      clk(user_clk_out);
      output_reset                      reset(user_reset_out);
      method user_lnk_up                lnk_up                                                              clocked_by(no_clock) reset_by(no_reset); /* semi-static */
      method fc_ph                      fc_ph                                                               clocked_by(trn_clk)  reset_by(no_reset);
      method fc_pd                      fc_pd                                                               clocked_by(trn_clk)  reset_by(no_reset);
      method fc_nph                     fc_nph                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method fc_npd                     fc_npd                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method fc_cplh                    fc_cplh                                                             clocked_by(trn_clk)  reset_by(no_reset);
      method fc_cpld                    fc_cpld                                                             clocked_by(trn_clk)  reset_by(no_reset);
      method                            fc_sel(fc_sel)                               enable((*inhigh*)en01) clocked_by(trn_clk)  reset_by(no_reset);      
   endinterface
   
   interface PCIE_TX_X7 tx;
      method                            tdata(trn_td)                                enable((*inhigh*)en02) clocked_by(trn_clk)  reset_by(no_reset);
      method                            tsof(trn_tsof)                               enable((*inhigh*)en03) clocked_by(trn_clk)  reset_by(no_reset);
      method                            teof(trn_teof)                               enable((*inhigh*)en04) clocked_by(trn_clk)  reset_by(no_reset);
      method                            trem(trn_trem)                               enable((*inhigh*)en05) clocked_by(trn_clk)  reset_by(no_reset);
      method                            tecrc_gen(trn_tecrc_gen)                     enable((*inhigh*)en06) clocked_by(trn_clk)  reset_by(no_reset);
      method                            tstr(trn_tstr)                               enable((*inhigh*)en07) clocked_by(trn_clk)  reset_by(no_reset);
      method                            tdisc(trn_tsrc_dsc)                          enable((*inhigh*)en08) clocked_by(trn_clk)  reset_by(no_reset);
      method                            terrfwd(trn_terrfwd)                         enable((*inhigh*)en09) clocked_by(trn_clk)  reset_by(no_reset);
      method                            tvalid(trn_tsrc_rdy)                         enable((*inhigh*)en10) clocked_by(trn_clk)  reset_by(no_reset);
      method trn_tdst_rdy               tready                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method tx_buf_av                  tbuf_av                                                             clocked_by(trn_clk)  reset_by(no_reset);
      method tx_err_drop                terr_drop                                                           clocked_by(trn_clk)  reset_by(no_reset);
      method trn_tcfg_req               tcfg_req                                                            clocked_by(trn_clk)  reset_by(no_reset);
      method                            tcfg_gnt(trn_tcfg_gnt)                       enable((*inhigh*)en11) clocked_by(trn_clk)  reset_by(no_reset);
   endinterface
   
   interface PCIE_RX_X7 rx;
      method trn_rd                     rdata                                                               clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rrem                   rrem                                                                clocked_by(trn_clk)  reset_by(no_reset);
      method trn_reof                   reof                                                                clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rsof                   rsof                                                                clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rbar_hit               rhit                                                                clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rsrc_dsc               disc                                                                clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rerrfwd                errfwd                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method trn_recrc_err              ecrcerr                                                             clocked_by(trn_clk)  reset_by(no_reset);
      method trn_rsrc_rdy               rvalid                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method                            rready(trn_rdst_rdy)                         enable((*inhigh*)en20) clocked_by(trn_clk)  reset_by(no_reset);
      method                            rnp_ok(rx_np_ok)                             enable((*inhigh*)en21) clocked_by(trn_clk)  reset_by(no_reset);
      method                            rnp_req(rx_np_req)                           enable((*inhigh*)en22) clocked_by(trn_clk)  reset_by(no_reset);
   endinterface

   interface PCIE_PL_X7 pl;
      method pl_initial_link_width      initial_link_width                                                       clocked_by(trn_clk)  reset_by(no_reset);
      method pl_phy_lnk_up              phy_link_up                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method pl_lane_reversal_mode      lane_reversal_mode                                                       clocked_by(trn_clk)  reset_by(no_reset);
      method pl_link_gen2_cap           link_gen2_capable                                                        clocked_by(trn_clk)  reset_by(no_reset);
      method pl_link_partner_gen2_supported link_partner_gen2_supported                                          clocked_by(trn_clk)  reset_by(no_reset);
      method pl_link_upcfg_cap          link_upcfg_capable                                                       clocked_by(trn_clk)  reset_by(no_reset);
      method pl_sel_lnk_rate            sel_link_rate                                                            clocked_by(trn_clk)  reset_by(no_reset);
      method pl_sel_lnk_width           sel_link_width                                                           clocked_by(trn_clk)  reset_by(no_reset);
      method pl_ltssm_state             ltssm_state                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method pl_rx_pm_state             rx_pm_state                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method pl_tx_pm_state             tx_pm_state                                                              clocked_by(trn_clk)  reset_by(no_reset);
      method                            directed_link_auton(pl_directed_link_auton)       enable((*inhigh*)en30) clocked_by(trn_clk)  reset_by(no_reset);
      method                            directed_link_change(pl_directed_link_change)     enable((*inhigh*)en31) clocked_by(trn_clk)  reset_by(no_reset);
      method                            directed_link_speed(pl_directed_link_speed)       enable((*inhigh*)en32) clocked_by(trn_clk)  reset_by(no_reset);
      method                            directed_link_width(pl_directed_link_width)       enable((*inhigh*)en33) clocked_by(trn_clk)  reset_by(no_reset);
      method pl_directed_change_done    directed_change_done                                                     clocked_by(trn_clk)  reset_by(no_reset);
      method                            upstream_prefer_deemph(pl_upstream_prefer_deemph) enable((*inhigh*)en34) clocked_by(trn_clk)  reset_by(no_reset);
      method pl_received_hot_rst        received_hot_rst                                                         clocked_by(trn_clk)  reset_by(no_reset);
   endinterface
   
   interface PCIE_CFG_X7 cfg;
      method cfg_mgmt_do                dout                                                                     clocked_by(trn_clk) reset_by(no_reset);
      method cfg_mgmt_rd_wr_done        rd_wr_done                                                               clocked_by(trn_clk) reset_by(no_reset);
      method                            di(cfg_mgmt_di)                                   enable((*inhigh*)en40) clocked_by(trn_clk) reset_by(no_reset);
      method                            dwaddr(cfg_mgmt_dwaddr)                           enable((*inhigh*)en41) clocked_by(trn_clk) reset_by(no_reset);
      method                            byte_en(cfg_mgmt_byte_en)                         enable((*inhigh*)en42) clocked_by(trn_clk) reset_by(no_reset);
      method                            wr_en(cfg_mgmt_wr_en)                             enable((*inhigh*)en43) clocked_by(trn_clk) reset_by(no_reset);
      method                            rd_en(cfg_mgmt_rd_en)                             enable((*inhigh*)en44) clocked_by(trn_clk) reset_by(no_reset);
      method                            wr_readonly(cfg_mgmt_wr_readonly)                 enable((*inhigh*)en45) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_bus_number             bus_number                                                               clocked_by(no_clock) reset_by(no_reset);
      method cfg_device_number          device_number                                                            clocked_by(no_clock) reset_by(no_reset);
      method cfg_function_number        function_number                                                          clocked_by(no_clock) reset_by(no_reset);
      method cfg_status                 status                                                                   clocked_by(trn_clk) reset_by(no_reset);
      method cfg_command                command                                                                  clocked_by(trn_clk) reset_by(no_reset);
      method cfg_dstatus                dstatus                                                                  clocked_by(trn_clk) reset_by(no_reset);
      method cfg_dcommand               dcommand                                                                 clocked_by(trn_clk) reset_by(no_reset);
      method cfg_dcommand2              dcommand2                                                                clocked_by(trn_clk) reset_by(no_reset);
      method cfg_lstatus                lstatus                                                                  clocked_by(trn_clk) reset_by(no_reset);
      method cfg_lcommand               lcommand                                                                 clocked_by(trn_clk) reset_by(no_reset);
      method cfg_aer_ecrc_gen_en        aer_ecrc_gen_en                                                          clocked_by(trn_clk) reset_by(no_reset);
      method cfg_aer_ecrc_check_en      aer_ecrc_check_en                                                        clocked_by(trn_clk) reset_by(no_reset);
      method cfg_pcie_link_state        pcie_link_state                                                          clocked_by(trn_clk) reset_by(no_reset);
      method                            trn_pending(cfg_trn_pending)                      enable((*inhigh*)en46) clocked_by(trn_clk) reset_by(no_reset);
      method                            dsn(cfg_dsn)                                      enable((*inhigh*)en47) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_pmcsr_pme_en           pmcsr_pme_en                                                             clocked_by(trn_clk) reset_by(no_reset);
      method cfg_pmcsr_pme_status       pmcsr_pme_status                                                         clocked_by(trn_clk) reset_by(no_reset);
      method cfg_pmcsr_powerstate       pmcsr_powerstate                                                         clocked_by(trn_clk) reset_by(no_reset);
      method                            pm_halt_aspm_l0s(cfg_pm_halt_aspm_l0s)            enable((*inhigh*)en48) clocked_by(trn_clk) reset_by(no_reset);
      method                            pm_halt_aspm_l1(cfg_pm_halt_aspm_l1)              enable((*inhigh*)en49) clocked_by(trn_clk) reset_by(no_reset);
      method                            pm_force_state(cfg_pm_force_state)                enable((*inhigh*)en50) clocked_by(trn_clk) reset_by(no_reset);
      method                            pm_force_state_en(cfg_pm_force_state_en)          enable((*inhigh*)en51) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_received_func_lvl_rst  received_func_lvl_rst                                                    clocked_by(trn_clk) reset_by(no_reset);
      method cfg_vc_tcvc_map            vc_tcvc_map                                                              clocked_by(trn_clk) reset_by(no_reset);
      method cfg_to_turnoff             to_turnoff                                                               clocked_by(trn_clk) reset_by(no_reset);
      method                            turnoff_ok(cfg_turnoff_ok)                        enable((*inhigh*)en52) clocked_by(trn_clk) reset_by(no_reset);
      method                            pm_wake(cfg_pm_wake)                              enable((*inhigh*)en53) clocked_by(trn_clk) reset_by(no_reset);
   endinterface

   interface PCIE_INT_X7 cfg_interrupt;
      method                            req(cfg_interrupt)                                enable((*inhigh*)en60) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_rdy          rdy                                                                      clocked_by(trn_clk) reset_by(no_reset);
      method                            assrt(cfg_interrupt_assert)                       enable((*inhigh*)en61) clocked_by(trn_clk) reset_by(no_reset);
      method                            di(cfg_interrupt_di)                              enable((*inhigh*)en62) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_do           dout                                                                     clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_mmenable     mmenable                                                                 clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_msienable    msienable                                                                clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_msixenable   msixenable                                                               clocked_by(trn_clk) reset_by(no_reset);
      method cfg_interrupt_msixfm       msixfm                                                                   clocked_by(trn_clk) reset_by(no_reset);
      method                            pciecap_msgnum(cfg_pciecap_interrupt_msgnum)      enable((*inhigh*)en63) clocked_by(trn_clk) reset_by(no_reset);
      method                            stat(cfg_interrupt_stat)                          enable((*inhigh*)en64) clocked_by(trn_clk) reset_by(no_reset);
   endinterface
      
   interface PCIE_ERR_X7 cfg_err;
      method                            ecrc(cfg_err_ecrc)                           	  enable((*inhigh*)en70) clocked_by(trn_clk) reset_by(no_reset);
      method                            ur(cfg_err_ur)                               	  enable((*inhigh*)en71) clocked_by(trn_clk) reset_by(no_reset);
      method                            cpl_timeout(cfg_err_cpl_timeout)             	  enable((*inhigh*)en72) clocked_by(trn_clk) reset_by(no_reset);
      method                            cpl_unexpect(cfg_err_cpl_unexpect)           	  enable((*inhigh*)en73) clocked_by(trn_clk) reset_by(no_reset);
      method                            cpl_abort(cfg_err_cpl_abort)                 	  enable((*inhigh*)en74) clocked_by(trn_clk) reset_by(no_reset);
      method                            posted(cfg_err_posted)                       	  enable((*inhigh*)en75) clocked_by(trn_clk) reset_by(no_reset);
      method                            cor(cfg_err_cor)                             	  enable((*inhigh*)en76) clocked_by(trn_clk) reset_by(no_reset);
      method          			atomic_egress_blocked(cfg_err_atomic_egress_blocked) enable((*inhigh*)en77) clocked_by(trn_clk) reset_by(no_reset);
      method          			internal_cor(cfg_err_internal_cor)           	  enable((*inhigh*)en78) clocked_by(trn_clk) reset_by(no_reset);
      method          			internal_uncor(cfg_err_internal_uncor)       	  enable((*inhigh*)en79) clocked_by(trn_clk) reset_by(no_reset);
      method          			malformed(cfg_err_malformed)                 	  enable((*inhigh*)en80) clocked_by(trn_clk) reset_by(no_reset);
      method          			mc_blocked(cfg_err_mc_blocked)               	  enable((*inhigh*)en81) clocked_by(trn_clk) reset_by(no_reset);
      method          			poisoned(cfg_err_poisoned)                   	  enable((*inhigh*)en82) clocked_by(trn_clk) reset_by(no_reset);
      method          			no_recovery(cfg_err_norecovery)             	  enable((*inhigh*)en83) clocked_by(trn_clk) reset_by(no_reset);
      method                            tlp_cpl_header(cfg_err_tlp_cpl_header)       	  enable((*inhigh*)en84) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_err_cpl_rdy            cpl_rdy                                      	                         clocked_by(trn_clk) reset_by(no_reset);
      method                            locked(cfg_err_locked)                       	  enable((*inhigh*)en85) clocked_by(trn_clk) reset_by(no_reset);
      method         			aer_headerlog(cfg_err_aer_headerlog)         	  enable((*inhigh*)en86) clocked_by(trn_clk) reset_by(no_reset);
      method cfg_err_aer_headerlog_set  aer_headerlog_set                                                        clocked_by(trn_clk) reset_by(no_reset);
      method         			aer_interrupt_msgnum(cfg_aer_interrupt_msgnum)    enable((*inhigh*)en87) clocked_by(trn_clk) reset_by(no_reset);
      method         			acs(cfg_err_acs)                                  enable((*inhigh*)en88) clocked_by(trn_clk) reset_by(no_reset);
   endinterface
      
   schedule (trn_lnk_up, trn_fc_ph, trn_fc_pd, trn_fc_nph, trn_fc_npd, trn_fc_cplh, trn_fc_cpld, trn_fc_sel,
             pl_initial_link_width, pl_phy_link_up, pl_lane_reversal_mode,
	     pl_link_gen2_capable, pl_link_partner_gen2_supported, pl_link_upcfg_capable, pl_sel_link_rate, pl_sel_link_width,
	     pl_ltssm_state, pl_rx_pm_state, pl_tx_pm_state, pl_directed_link_auton, pl_directed_link_change, 
	     pl_directed_link_speed, pl_directed_link_width, pl_directed_change_done, pl_upstream_prefer_deemph, 
	     pl_received_hot_rst, cfg_dout, cfg_rd_wr_done, cfg_di, cfg_dwaddr, cfg_byte_en, cfg_wr_en, cfg_rd_en, 
	     cfg_wr_readonly, cfg_bus_number, cfg_device_number, cfg_function_number, cfg_status, cfg_command, cfg_dstatus,
	     cfg_dcommand, cfg_dcommand2, cfg_lstatus, cfg_lcommand, cfg_aer_ecrc_gen_en, cfg_aer_ecrc_check_en,
	     cfg_pcie_link_state, cfg_trn_pending, cfg_dsn, cfg_pmcsr_pme_en, cfg_pmcsr_pme_status, cfg_pmcsr_powerstate,
	     cfg_pm_halt_aspm_l0s, cfg_pm_halt_aspm_l1, cfg_pm_force_state, cfg_pm_force_state_en, cfg_received_func_lvl_rst,
	     cfg_vc_tcvc_map, cfg_to_turnoff, cfg_turnoff_ok, cfg_pm_wake, 
	     cfg_interrupt_req, cfg_interrupt_rdy,
	     cfg_interrupt_assrt, cfg_interrupt_di, cfg_interrupt_dout, cfg_interrupt_mmenable, cfg_interrupt_msienable,
	     cfg_interrupt_msixenable, cfg_interrupt_msixfm, cfg_interrupt_pciecap_msgnum, cfg_interrupt_stat,
	     cfg_err_ecrc, cfg_err_ur, cfg_err_cpl_timeout, cfg_err_cpl_unexpect, cfg_err_cpl_abort, cfg_err_posted,
	     cfg_err_cor, cfg_err_atomic_egress_blocked, cfg_err_internal_cor, cfg_err_internal_uncor, cfg_err_malformed,
	     cfg_err_mc_blocked, cfg_err_poisoned, cfg_err_no_recovery, cfg_err_tlp_cpl_header, cfg_err_cpl_rdy, cfg_err_locked,
	     cfg_err_aer_headerlog, cfg_err_aer_headerlog_set, cfg_err_aer_interrupt_msgnum, cfg_err_acs,
	     pcie_txp, pcie_txn, pcie_rxp, pcie_rxn,
	     rx_rready, rx_rnp_ok, rx_rnp_req, rx_rdata, rx_rrem, rx_reof,rx_rsof,rx_rhit,rx_disc,rx_errfwd,rx_ecrcerr,rx_rvalid,
             tx_tdata, tx_tsof, tx_teof, tx_trem, tx_tecrc_gen, tx_tstr, tx_tdisc, tx_terrfwd, tx_tvalid, tx_tcfg_gnt,
             tx_tready,tx_tbuf_av,tx_terr_drop,tx_tcfg_req
	     ) CF 
            (trn_lnk_up, trn_fc_ph, trn_fc_pd, trn_fc_nph, trn_fc_npd, trn_fc_cplh, trn_fc_cpld, trn_fc_sel,
	     pl_initial_link_width, pl_phy_link_up, pl_lane_reversal_mode,
	     pl_link_gen2_capable, pl_link_partner_gen2_supported, pl_link_upcfg_capable, pl_sel_link_rate, pl_sel_link_width,
	     pl_ltssm_state, pl_rx_pm_state, pl_tx_pm_state, pl_directed_link_auton, pl_directed_link_change, 
	     pl_directed_link_speed, pl_directed_link_width, pl_directed_change_done, pl_upstream_prefer_deemph, 
	     pl_received_hot_rst, cfg_dout, cfg_rd_wr_done, cfg_di, cfg_dwaddr, cfg_byte_en, cfg_wr_en, cfg_rd_en, 
	     cfg_wr_readonly, cfg_bus_number, cfg_device_number, cfg_function_number, cfg_status, cfg_command, cfg_dstatus,
	     cfg_dcommand, cfg_dcommand2, cfg_lstatus, cfg_lcommand, cfg_aer_ecrc_gen_en, cfg_aer_ecrc_check_en,
	     cfg_pcie_link_state, cfg_trn_pending, cfg_dsn, cfg_pmcsr_pme_en, cfg_pmcsr_pme_status, cfg_pmcsr_powerstate,
	     cfg_pm_halt_aspm_l0s, cfg_pm_halt_aspm_l1, cfg_pm_force_state, cfg_pm_force_state_en, cfg_received_func_lvl_rst,
	     cfg_vc_tcvc_map, cfg_to_turnoff, cfg_turnoff_ok, cfg_pm_wake, 
	     cfg_interrupt_req, cfg_interrupt_rdy,
	     cfg_interrupt_assrt, cfg_interrupt_di, cfg_interrupt_dout, cfg_interrupt_mmenable, cfg_interrupt_msienable,
	     cfg_interrupt_msixenable, cfg_interrupt_msixfm, cfg_interrupt_pciecap_msgnum, cfg_interrupt_stat,
	     cfg_err_ecrc, cfg_err_ur, cfg_err_cpl_timeout, cfg_err_cpl_unexpect, cfg_err_cpl_abort, cfg_err_posted,
	     cfg_err_cor, cfg_err_atomic_egress_blocked, cfg_err_internal_cor, cfg_err_internal_uncor, cfg_err_malformed,
	     cfg_err_mc_blocked, cfg_err_poisoned, cfg_err_no_recovery, cfg_err_tlp_cpl_header, cfg_err_cpl_rdy, cfg_err_locked,
	     cfg_err_aer_headerlog, cfg_err_aer_headerlog_set, cfg_err_aer_interrupt_msgnum, cfg_err_acs,
	     pcie_txp, pcie_txn, pcie_rxp, pcie_rxn,
	     rx_rready, rx_rnp_ok, rx_rnp_req, rx_rdata, rx_rrem, rx_reof,rx_rsof,rx_rhit,rx_disc,rx_errfwd,rx_ecrcerr,rx_rvalid,
             tx_tdata, tx_tsof, tx_teof, tx_trem, tx_tecrc_gen, tx_tstr, tx_tdisc, tx_terrfwd, tx_tvalid, tx_tcfg_gnt,
             tx_tready,tx_tbuf_av,tx_terr_drop,tx_tcfg_req
             );

endmodule: vMkXilinx7PCIExpress

////////////////////////////////////////////////////////////////////////////////
/// Pipe Clock
////////////////////////////////////////////////////////////////////////////////

(* always_ready, always_enabled *)
interface Xilinx7PciePipeClock#(numeric type lanes);
   method Action pclk_sel(Bit#(lanes) i);
   method Action gen3(Bool i);
   method Bool   mmcm_lock();
   interface Clock pclk;
   interface Clock rxuserclk;
   interface Clock dclk;
   interface Clock oobclk;
   interface Clock userclk1;
   interface Clock userclk2;
endinterface

import "BVI" pcie_7x_0_pipe_clock =
module mkXilinx7PciePipeClock#(Clock clk, Clock txoutclk, Integer user_clk_freq, Integer userclk2_freq)(Xilinx7PciePipeClock#(lanes));
    parameter PCIE_ASYNC_EN      = "FALSE";                 // PCIe async enable
    parameter PCIE_TXBUF_EN      = "FALSE";                 // PCIe TX buffer enable for Gen1/Gen2 only
    parameter PCIE_LANE          = valueOf(lanes);          // PCIe number of lanes
    parameter PCIE_LINK_SPEED    = 3;                       // PCIe link speed 
    parameter PCIE_REFCLK_FREQ   = 0;                       // PCIe reference clock frequency
    parameter PCIE_USERCLK1_FREQ = user_clk_freq + 1;       // PCIe user clock 1 frequency
    parameter PCIE_USERCLK2_FREQ = userclk2_freq + 1;       // PCIe user clock 2 frequency
    parameter PCIE_OOBCLK_MODE   = 1;                       // PCIe oob clock mode
   
   default_clock clk(CLK_CLK);
   input_clock txoutclk(CLK_TXOUTCLK) = txoutclk;
   default_reset rst(CLK_RST_N);
   
   method pclk_sel(CLK_PCLK_SEL) enable((*inhigh*)en0) reset_by(no_reset);
   method gen3(CLK_GEN3)        enable((*inhigh*)en1) reset_by(no_reset);

   output_clock pclk(CLK_PCLK);
   output_clock rxuserclk(CLK_RXUSRCLK);
   output_clock dclk(CLK_DCLK);
   output_clock oobclk(CLK_OOBCLK);
   output_clock userclk1 (CLK_USERCLK1);
   output_clock userclk2(CLK_USERCLK2);
   method CLK_MMCM_LOCK mmcm_lock() reset_by(no_reset);
   schedule (pclk_sel, gen3, mmcm_lock) CF (pclk_sel, gen3, mmcm_lock);

endmodule

////////////////////////////////////////////////////////////////////////////////
/// Gt Top
////////////////////////////////////////////////////////////////////////////////

interface PCIE_GT_X7_CLOCK#(numeric type lanes);
   interface Clock    pipe_txoutclk_out;
   method Action      pipe_mmcm_lock_in(Bool in);
   method Bit#(lanes) pipe_pclk_sel_out();
   method Bool        pipe_gen3_out();
endinterface

interface PCIE_GT_X7#(numeric type lanes);
   interface PCIE_EXP#(lanes) pcie;
   interface PCIE_GT_X7_CLOCK#(lanes) clocks;
endinterface   

typedef struct {
		Clock pipe_pclk_in;
		Clock pipe_rxuserclk_in;
		Clock pipe_dclk_in;
		Clock pipe_userclk1_in;
		Clock pipe_userclk2_in;
		Clock pipe_oobclk_in;
   } Xilinx7GtClocks;

import "BVI" pcie_7x_0_gt_top =
module vMkXilinx7GtTop#(Xilinx7GtClocks clocks)(PCIE_GT_X7#(lanes))
   provisos( Add#(1, z, lanes));

   parameter               LINK_CAP_MAX_LINK_WIDTH = 8; // 1 - x1 , 2 - x2 , 4 - x4 , 8 - x8
   parameter               REF_CLK_FREQ = 0;            // 0 - 100 MHz , 1 - 125 MHz , 2 - 250 MHz
   parameter               USER_CLK2_DIV2 = "FALSE";    // "FALSE" => user_clk2 = user_clk
                                                        // "TRUE" => user_clk2 = user_clk/2, where user_clk = 500 or 250 MHz.
   parameter  integer      USER_CLK_FREQ = 3;           // 0 - 31.25 MHz , 1 - 62.5 MHz , 2 - 125 MHz , 3 - 250 MHz , 4 - 500Mhz
   parameter               PL_FAST_TRAIN = "FALSE";     // Simulation Speedup
   parameter               PCIE_EXT_CLK  = "TRUE";      // Use External Clocking
   parameter               PCIE_USE_MODE = "3.0";       // 1.0 = K325T IES, 1.1 = VX485T IES, 3.0 = K325T GES
   parameter               PCIE_GT_DEVICE = "GTX";      // Select the GT to use (GTP for Artix-7, GTX for K7/V7)
   parameter               PCIE_PLL_SEL   = "CPLL";     // Select the PLL (CPLL or QPLL)
   parameter               PCIE_ASYNC_EN  = "FALSE";    // Asynchronous Clocking Enable
   parameter               PCIE_TXBUF_EN  = "FALSE";    // Use the Tansmit Buffer
   parameter               PCIE_CHAN_BOND = 0;


   // //-----------------------------------------------------------------------------------------------------------------//
   // // pl ltssm
   // input   wire [5:0]                pl_ltssm_state         ,
   // // Pipe Per-Link Signals
   // input   wire                      pipe_tx_rcvr_det       ,
   // input   wire                      pipe_tx_reset          ,
   // input   wire                      pipe_tx_rate           ,
   // input   wire                      pipe_tx_deemph         ,
   // input   wire [2:0]                pipe_tx_margin         ,
   // input   wire                      pipe_tx_swing          ,

   //-----------------------------------------------------------------------------------------------------------------//
   // Clock Inputs                                                                                                    //
   //-----------------------------------------------------------------------------------------------------------------//
   input_clock pipe_pclk_in(PIPE_PCLK_IN) = clocks.pipe_pclk_in;
   input_clock  pipe_rxuserclk_in(PIPE_RXUSERCLK_IN) = clocks.pipe_rxuserclk_in;
   input_clock pipe_dclk_in(PIPE_DCLK_IN) = clocks.pipe_dclk_in;
   input_clock pipe_userclk1_in(PIPE_USERCLK1_IN) = clocks.pipe_userclk1_in;
   input_clock pipe_userclk2_in(PIPE_USERCLK2_IN) = clocks.pipe_userclk2_in;
   input_clock pipe_oobclk_in(PIPE_OOBCLK_IN) = clocks.pipe_oobclk_in;

   interface PCIE_GT_X7_CLOCK#(lanes) clocks;
      method pipe_mmcm_lock_in(PIPE_MMCM_LOCK_IN);

      output_clock pipe_txoutclk_out(PIPE_TXOUTCLK_OUT);
      method PIPE_PCLK_SEL_OUT pipe_pclk_sel_out;
      method PIPE_GEN3_OUT pipe_gen3_out;
   endinterface

   // // Pipe Per-Lane Signals - Lane 0
   // output  wire [ 1:0]               pipe_rx0_char_is_k     ,
   // output  wire [15:0]               pipe_rx0_data          ,
   // output  wire                      pipe_rx0_valid         ,
   // output  wire                      pipe_rx0_chanisaligned ,
   // output  wire [ 2:0]               pipe_rx0_status        ,
   // output  wire                      pipe_rx0_phy_status    ,
   // output  wire                      pipe_rx0_elec_idle     ,
   // input   wire                      pipe_rx0_polarity      ,
   // input   wire                      pipe_tx0_compliance    ,
   // input   wire [ 1:0]               pipe_tx0_char_is_k     ,
   // input   wire [15:0]               pipe_tx0_data          ,
   // input   wire                      pipe_tx0_elec_idle     ,
   // input   wire [ 1:0]               pipe_tx0_powerdown     ,



   // PCI Express signals
   // output  wire [ (LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_txn            ,
   // output  wire [ (LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_txp            ,
   // input   wire [ (LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_rxn            ,
   // input   wire [ (LINK_CAP_MAX_LINK_WIDTH-1):0] pci_exp_rxp            ,

   // Non PIPE signals
   // input   wire                      sys_clk                ,
   // input   wire                      sys_rst_n              ,
   // input   wire                      PIPE_MMCM_RST_N        ,
   // output  wire                      pipe_clk               ,

   // output  wire                      phy_rdy_n

endmodule

////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////
interface PCIE_TRN_COMMON_X7;
   interface Clock       clk;
   interface Clock       clk2;
   interface Reset       reset_n;
   method    Bool        link_up;
endinterface
    
interface PCIE_TRN_XMIT_X7;
   method    Action      xmit(TLPData#(8) data);
   method    Action      discontinue(Bool i);
   method    Action      ecrc_generate(Bool i);
   method    Action      error_forward(Bool i);
   method    Action      cut_through_mode(Bool i);
   method    Bool        dropped;
   method    Bit#(6)     buffers_available;
   method    Bool        configuration_completion_request;
   method    Action      configuration_completion_grant(Bool i);
endinterface

interface PCIE_TRN_RECV_X7;
   method    ActionValue#(Tuple3#(Bool, Bool, TLPData#(8))) recv();
   method    Action      non_posted_ok(Bool i);
   method    Action      non_posted_req(Bool i);
endinterface

interface PCIExpressX7#(numeric type lanes);
   interface PCIE_EXP#(lanes)   pcie;
   interface PCIE_TRN_COMMON_X7 trn;
   interface PCIE_TRN_XMIT_X7   trn_tx;
   interface PCIE_TRN_RECV_X7   trn_rx;
   interface PCIE_CFG_X7        cfg;
   interface PCIE_INT_X7        cfg_interrupt;
   interface PCIE_ERR_X7        cfg_err;
   interface PCIE_PL_X7         pl;
endinterface   

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
///
/// Implementation
///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
typeclass SelectXilinx7PCIE#(numeric type lanes);
   module selectXilinx7PCIE(PCIEParams params, PCIE_X7#(lanes) ifc);
endtypeclass

instance SelectXilinx7PCIE#(8);
   module selectXilinx7PCIE(PCIEParams params, PCIE_X7#(8) ifc);
      let _ifc <- vMkXilinx7PCIExpress(params);
      return _ifc;
   endmodule
endinstance

instance SelectXilinx7PCIE#(4);
   module selectXilinx7PCIE(PCIEParams params, PCIE_X7#(4) ifc);
      let _ifc <- vMkXilinx7PCIExpress(params);
      return _ifc;
   endmodule
endinstance

instance SelectXilinx7PCIE#(1);
   module selectXilinx7PCIE(PCIEParams params, PCIE_X7#(1) ifc);
      let _ifc <- vMkXilinx7PCIExpress(params);
      return _ifc;
   endmodule
endinstance

module mkPCIExpressEndpointX7#(PCIEParams params)(PCIExpressX7#(lanes))
   provisos(Add#(1, z, lanes), SelectXilinx7PCIE#(lanes));
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Design Elements
   ////////////////////////////////////////////////////////////////////////////////
   let clk <- exposeCurrentClock;

   Xilinx7PciePipeClock#(8)                  pcie_pipe_clock     <- mkXilinx7PciePipeClock(clk, clk, 3, 3);
   PCIE_X7#(lanes)                           pcie_ep             <- selectXilinx7PCIE(params);

   Clock                                     user_clk             = pcie_ep.trn.clk;
   Reset                                     user_reset_n        <- mkResetInverter(pcie_ep.trn.reset);
   
   Wire#(Bool)                               wDiscontinue        <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wEcrcGen            <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wErrFwd             <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wCutThrough         <- mkDWire(False, clocked_by user_clk, reset_by noReset);

   Wire#(Bool)                               wTxValid            <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wTxSof              <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wTxEof              <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   Wire#(Bit#(1))                            wTxRem              <- mkDWire(0, clocked_by user_clk, reset_by noReset);
   Wire#(Bit#(64))                           wTxData             <- mkDWire(0, clocked_by user_clk, reset_by noReset);
   Wire#(Bit#(8))                            wTxKeep             <- mkDWire(0, clocked_by user_clk, reset_by noReset);
   FIFO#(AxiTx)                              fTx                 <- mkBypassFIFO(clocked_by user_clk, reset_by noReset);
   
   FIFOF#(AxiRx)                             fRx                 <- mkBypassFIFOF(clocked_by user_clk, reset_by noReset);
   Wire#(Bool)                               wRxReady            <- mkDWire(False, clocked_by user_clk, reset_by noReset);
   
   ClockGenerator7Params                     params               = defaultValue;
   params.clkin1_period    = 4.000;
   params.clkin_buffer     = False;
   params.clkfbout_mult_f  = 4.000;
   params.clkout0_divide_f = 8.000;
   ClockGenerator7                           clkgen              <- mkClockGenerator7(params, clocked_by user_clk, reset_by user_reset_n);
   Clock                                     user_clk_half        = clkgen.clkout0;
   
   ////////////////////////////////////////////////////////////////////////////////
   /// Rules
   ////////////////////////////////////////////////////////////////////////////////
   (* fire_when_enabled, no_implicit_conditions *)
   rule others;
      pcie_ep.trn.fc_sel(RECEIVE_BUFFER_AVAILABLE_SPACE);
   endrule
   
   (* fire_when_enabled, no_implicit_conditions *)
   rule drive_tx;
      pcie_ep.tx.tvalid(wTxValid);
      pcie_ep.tx.tsof(wTxSof);
      pcie_ep.tx.teof(wTxEof);
      pcie_ep.tx.trem(wTxRem);
      pcie_ep.tx.tdisc(wDiscontinue);
      pcie_ep.tx.tstr(wCutThrough);
      pcie_ep.tx.terrfwd(wErrFwd);
      pcie_ep.tx.tecrc_gen(wEcrcGen);
      pcie_ep.tx.tdata(wTxData);
   endrule
   
   (* fire_when_enabled *)
   rule drive_tx_info if (pcie_ep.tx.tready);
      let info <- toGet(fTx).get;
      wTxValid <= True;
      wTxSof   <= info.sof;
      wTxEof   <= info.eof;
      wTxRem   <= info.rem;
      wTxData  <= info.data;
   endrule
   
   (* fire_when_enabled, no_implicit_conditions *)
   rule drive_rx_ready;
      pcie_ep.rx.rready(fRx.notFull);
   endrule
   
   (* fire_when_enabled *)
   rule sink_rx if (pcie_ep.rx.rvalid);
      let info = AxiRx {
	 data:    pcie_ep.rx.rdata,
	 sof:     pcie_ep.rx.rsof,
	 eof:     pcie_ep.rx.reof,
         hit:     pcie_ep.rx.rhit,
	 rrem:    pcie_ep.rx.rrem,
	 errfwd:  pcie_ep.rx.errfwd,
	 ecrcerr: pcie_ep.rx.ecrcerr,
	 disc:    pcie_ep.rx.disc
	 };
      fRx.enq(info);
   endrule

   ////////////////////////////////////////////////////////////////////////////////
   /// Interface Connections / Methods
   ////////////////////////////////////////////////////////////////////////////////
   interface pcie = pcie_ep.pcie;
      
   interface PCIE_TRN_COMMON_X7 trn;
      interface clk     = user_clk;
      interface clk2    = user_clk_half;
      interface reset_n = user_reset_n;
      method    link_up = pcie_ep.trn.lnk_up;
   endinterface
      
   interface PCIE_TRN_XMIT_X7 trn_tx;
      method Action xmit(data);
         let rem = 0;
	 if (data.be == 8'hff)
	    rem = 1;
	 fTx.enq(AxiTx { sof: data.sof, eof: data.eof, rem: rem, data: data.data });
      endmethod
      method discontinue(i)                    = wDiscontinue._write(i);
      method ecrc_generate(i)          	       = wEcrcGen._write(i);
      method error_forward(i)          	       = wErrFwd._write(i);
      method cut_through_mode(i)       	       = wCutThrough._write(i);
      method dropped                   	       = pcie_ep.tx.terr_drop;
      method buffers_available         	       = pcie_ep.tx.tbuf_av;
      method configuration_completion_request  = pcie_ep.tx.tcfg_req;
      method configuration_completion_grant(i) = pcie_ep.tx.tcfg_gnt(i);
   endinterface
      
   interface PCIE_TRN_RECV_X7 trn_rx;
      method ActionValue#(Tuple3#(Bool, Bool, TLPData#(8))) recv();
	 let info <- toGet(fRx).get;
         Bit#(8) be = 0;
	 if (info.rrem == 0)
	    be = 8'h0f;
	 else
	    be = 8'hff;
	 TLPData#(8) retval = defaultValue;
	 retval.sof  = info.sof;
	 retval.eof  = info.eof;
	 retval.hit  = info.hit[6:0];
	 retval.be   = be;
	 retval.data = info.data;
	 return tuple3(info.errfwd, info.ecrcerr, retval);
      endmethod
      method non_posted_ok(i)  = pcie_ep.rx.rnp_ok(i);
      method non_posted_req(i) = pcie_ep.rx.rnp_req(i);
   endinterface
      
   interface pl = pcie_ep.pl;
   interface cfg = pcie_ep.cfg;
   interface cfg_interrupt = pcie_ep.cfg_interrupt;
   interface cfg_err = pcie_ep.cfg_err;
endmodule: mkPCIExpressEndpointX7

////////////////////////////////////////////////////////////////////////////////
/// Connection Instances
////////////////////////////////////////////////////////////////////////////////

// Basic TLPData#(8) connections to PCIE endpoint
instance Connectable#(Get#(TLPData#(8)), PCIE_TRN_XMIT_X7);
   module mkConnection#(Get#(TLPData#(8)) g, PCIE_TRN_XMIT_X7 p)(Empty);
      rule every;
         p.cut_through_mode(False);
         p.configuration_completion_grant(True);  // Core gets to choose
         p.error_forward(False);
	 p.ecrc_generate(False);
	 p.discontinue(False);
      endrule
      rule connect;
         let data <- g.get;
         p.xmit(data);
      endrule
   endmodule
endinstance

instance Connectable#(PCIE_TRN_XMIT_X7, Get#(TLPData#(8)));
   module mkConnection#(PCIE_TRN_XMIT_X7 p, Get#(TLPData#(8)) g)(Empty);
      mkConnection(g, p);
   endmodule
endinstance

instance Connectable#(Put#(TLPData#(8)), PCIE_TRN_RECV_X7);
   module mkConnection#(Put#(TLPData#(8)) p, PCIE_TRN_RECV_X7 r)(Empty);
      (* no_implicit_conditions, fire_when_enabled *)
      rule every;
         r.non_posted_ok(True);
	 r.non_posted_req(True);
      endrule
      rule connect;
         let data <- r.recv;
         p.put(tpl_3(data));
      endrule
   endmodule
endinstance

instance Connectable#(PCIE_TRN_RECV_X7, Put#(TLPData#(8)));
   module mkConnection#(PCIE_TRN_RECV_X7 r, Put#(TLPData#(8)) p)(Empty);
      mkConnection(p, r);
   endmodule
endinstance

// Connections between TLPData#(16) and a PCIE endpoint.
// These are all using the same clock, so the TLPData#(16) accesses
// will not be back-to-back.

instance Connectable#(Get#(TLPData#(16)), PCIE_TRN_XMIT_X7);
   module mkConnection#(Get#(TLPData#(16)) g, PCIE_TRN_XMIT_X7 t)(Empty);
      FIFO#(TLPData#(8)) outFifo <- mkFIFO();

      (* no_implicit_conditions, fire_when_enabled *)
      rule every;
         t.cut_through_mode(False);
         t.configuration_completion_grant(True);  // True means core gets to choose
         t.error_forward(False);
	 t.ecrc_generate(False);
	 t.discontinue(False);
      endrule

      rule connect;
         let data = outFifo.first; outFifo.deq;
         if (data.be != 0)
            t.xmit(data);
      endrule

      Put#(TLPData#(8)) p = fifoToPut(outFifo);
      mkConnection(g,p);
   endmodule
endinstance

instance Connectable#(PCIE_TRN_XMIT_X7, Get#(TLPData#(16)));
   module mkConnection#(PCIE_TRN_XMIT_X7 p, Get#(TLPData#(16)) g)(Empty);
      mkConnection(g, p);
   endmodule
endinstance

instance Connectable#(Put#(TLPData#(16)), PCIE_TRN_RECV_X7);
   module mkConnection#(Put#(TLPData#(16)) p, PCIE_TRN_RECV_X7 r)(Empty);
      FIFO#(TLPData#(8)) inFifo <- mkFIFO();

      (* no_implicit_conditions, fire_when_enabled *)
      rule every;
         r.non_posted_ok(True);
	 r.non_posted_req(True);
      endrule

      rule connect;
         let data <- r.recv;
         inFifo.enq(tpl_3(data));
      endrule

      Get#(TLPData#(8)) g = fifoToGet(inFifo);
      mkConnection(g,p);
   endmodule
endinstance

instance Connectable#(PCIE_TRN_RECV_X7, Put#(TLPData#(16)));
   module mkConnection#(PCIE_TRN_RECV_X7 r, Put#(TLPData#(16)) p)(Empty);
      mkConnection(p, r);
   endmodule
endinstance

// Connections between TLPData#(16) and a PCIE endpoint, using a gearbox
// to match data rates between the endpoint and design clocks.

instance ConnectableWithClocks#(PCIE_TRN_XMIT_X7, Get#(TLPData#(16)));
   module mkConnectionWithClocks#(PCIE_TRN_XMIT_X7 p, Get#(TLPData#(16)) g,
                                  Clock fastClock, Reset fastReset,
                                  Clock slowClock, Reset slowReset)(Empty);

      ////////////////////////////////////////////////////////////////////////////////
      /// Design Elements
      ////////////////////////////////////////////////////////////////////////////////
      FIFO#(TLPData#(8))                     outFifo             <- mkFIFO(clocked_by fastClock, reset_by fastReset);
      Gearbox#(2, 1, TLPData#(8))            fifoTxData          <- mkNto1Gearbox(slowClock, slowReset, fastClock, fastReset);

      ////////////////////////////////////////////////////////////////////////////////
      /// Rules
      ////////////////////////////////////////////////////////////////////////////////
      (* no_implicit_conditions, fire_when_enabled *)
      rule every;
         p.cut_through_mode(False);
         p.configuration_completion_grant(True);  // Means the core gets to choose
         p.error_forward(False);
	 p.ecrc_generate(False);
	 p.discontinue(False);
      endrule

      rule get_data;
         function Vector#(2, TLPData#(8)) split(TLPData#(16) in);
            Vector#(2, TLPData#(8)) v = defaultValue;
            v[0].sof  = in.sof;
            v[0].eof  = (in.be[7:0] == 0) ? in.eof : False;
            v[0].hit  = in.hit;
            v[0].be   = in.be[15:8];
            v[0].data = in.data[127:64];
            v[1].sof  = False;
            v[1].eof  = in.eof;
            v[1].hit  = in.hit;
            v[1].be   = in.be[7:0];
            v[1].data = in.data[63:0];
            return v;
         endfunction

         let data <- g.get;
         fifoTxData.enq(split(data));
      endrule

      rule process_outgoing_packets;
         let data = fifoTxData.first; fifoTxData.deq;
         outFifo.enq(head(data));
      endrule

      rule send_data;
         let data = outFifo.first; outFifo.deq;
         // filter out TLPs with 00 byte enable
         if (data.be != 0)
            p.xmit(data);
      endrule

   endmodule
endinstance

instance ConnectableWithClocks#(Get#(TLPData#(16)), PCIE_TRN_XMIT_X7);
   module mkConnectionWithClocks#(Get#(TLPData#(16)) g, PCIE_TRN_XMIT_X7 p,
                                  Clock fastClock, Reset fastReset,
                                  Clock slowClock, Reset slowReset)(Empty);

      mkConnectionWithClocks(p, g, fastClock, fastReset, slowClock, slowReset);
   endmodule
endinstance

instance ConnectableWithClocks#(Put#(TLPData#(16)), PCIE_TRN_RECV_X7);
   module mkConnectionWithClocks#(Put#(TLPData#(16)) p, PCIE_TRN_RECV_X7 g,
                                  Clock fastClock, Reset fastReset,
                                  Clock slowClock, Reset slowReset)(Empty);

      ////////////////////////////////////////////////////////////////////////////////
      /// Design Elements
      ////////////////////////////////////////////////////////////////////////////////
      FIFO#(TLPData#(8))                        inFifo              <- mkFIFO(clocked_by fastClock, reset_by fastReset);
      Gearbox#(1, 2, TLPData#(8))               fifoRxData          <- mk1toNGearbox(fastClock, fastReset, slowClock, slowReset);

      Reg#(Bool)                                rOddBeat            <- mkRegA(False, clocked_by fastClock, reset_by fastReset);
      Reg#(Bool)                                rSendInvalid        <- mkRegA(False, clocked_by fastClock, reset_by fastReset);

      ////////////////////////////////////////////////////////////////////////////////
      /// Rules
      ////////////////////////////////////////////////////////////////////////////////
      (* no_implicit_conditions, fire_when_enabled *)
      rule every;
         g.non_posted_ok(True);
	 g.non_posted_req(True);
      endrule

      rule accept_data;
         let data <- g.recv;
         inFifo.enq(tpl_3(data));
      endrule

      rule process_incoming_packets(!rSendInvalid);
         let data = inFifo.first; inFifo.deq;
         rOddBeat     <= !rOddBeat;
         rSendInvalid <= !rOddBeat && data.eof;
         Vector#(1, TLPData#(8)) v = defaultValue;
         v[0] = data;
         fifoRxData.enq(v);
      endrule

      rule send_invalid_packets(rSendInvalid);
         rOddBeat     <= !rOddBeat;
         rSendInvalid <= False;
         Vector#(1, TLPData#(8)) v = defaultValue;
         v[0].eof = True;
         v[0].be  = 0;
         fifoRxData.enq(v);
      endrule

      rule send_data;
         function TLPData#(16) combine(Vector#(2, TLPData#(8)) in);
            return TLPData {
                            sof:   in[0].sof,
                            eof:   in[1].eof,
                            hit:   in[0].hit,
                            be:    { in[0].be,   in[1].be },
                            data:  { in[0].data, in[1].data }
                            };
         endfunction

         fifoRxData.deq;
         p.put(combine(fifoRxData.first));
      endrule

   endmodule
endinstance

instance ConnectableWithClocks#(PCIE_TRN_RECV_X7, Put#(TLPData#(16)));
   module mkConnectionWithClocks#(PCIE_TRN_RECV_X7 g, Put#(TLPData#(16)) p,
                                  Clock fastClock, Reset fastReset,
                                  Clock slowClock, Reset slowReset)(Empty);
      mkConnectionWithClocks(p, g, fastClock, fastReset, slowClock, slowReset);
   endmodule
endinstance

// interface tie-offs


instance TieOff#(PCIE_CFG_X7);
   module mkTieOff#(PCIE_CFG_X7 ifc)(Empty);
      rule tie_off_inputs;
	 ifc.di(0);
	 ifc.dwaddr(0);
	 ifc.byte_en(0);
	 ifc.wr_en(0);
	 ifc.rd_en(0);
	 ifc.wr_readonly(0);
	 ifc.trn_pending(0);
	 ifc.dsn({ 32'h0000_0001, {{ 8'h1 } , 24'h000A35 }});
	 ifc.pm_halt_aspm_l0s(0);
	 ifc.pm_halt_aspm_l1(0);
	 ifc.pm_force_state(0);
	 ifc.pm_force_state_en(0);
	 ifc.turnoff_ok(0);
	 ifc.pm_wake(0);
      endrule
   endmodule
endinstance

instance TieOff#(PCIE_INT_X7);
   module mkTieOff#(PCIE_INT_X7 ifc)(Empty);
      rule tie_off_inputs;
	 ifc.req(0);
	 ifc.assrt(0);
	 ifc.di(0);
	 ifc.pciecap_msgnum(0);
	 ifc.stat(0);
      endrule
   endmodule
endinstance

instance TieOff#(PCIE_ERR_X7);
   module mkTieOff#(PCIE_ERR_X7 ifc)(Empty);
      rule tie_off_inputs;
	 ifc.ecrc(0);
	 ifc.ur(0);
	 ifc.cpl_timeout(0);
	 ifc.cpl_unexpect(0);
	 ifc.cpl_abort(0);
	 ifc.posted(0);
	 ifc.cor(0);
	 ifc.atomic_egress_blocked(0);
	 ifc.internal_cor(0);
	 ifc.internal_uncor(0);
	 ifc.malformed(0);
	 ifc.mc_blocked(0);
	 ifc.poisoned(0);
	 ifc.no_recovery(0);
	 ifc.tlp_cpl_header(0);
	 ifc.locked(0);
	 ifc.aer_headerlog(0);
	 ifc.aer_interrupt_msgnum(0);
	 ifc.acs(0);
      endrule
   endmodule
endinstance

instance TieOff#(PCIE_PL_X7);
   module mkTieOff#(PCIE_PL_X7 ifc)(Empty);
      rule tie_off_inputs;
	 ifc.directed_link_auton(0);
	 ifc.directed_link_change(0);
	 ifc.directed_link_speed(0);
	 ifc.directed_link_width(0);
	 ifc.upstream_prefer_deemph(1);
      endrule
   endmodule
endinstance

endpackage: XbsvXilinx7Pcie

