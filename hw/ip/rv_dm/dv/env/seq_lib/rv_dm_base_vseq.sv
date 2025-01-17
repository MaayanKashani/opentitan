// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class rv_dm_base_vseq extends cip_base_vseq #(
    .RAL_T               (rv_dm_regs_reg_block),
    .CFG_T               (rv_dm_env_cfg),
    .COV_T               (rv_dm_env_cov),
    .VIRTUAL_SEQUENCER_T (rv_dm_virtual_sequencer)
  );
  `uvm_object_utils(rv_dm_base_vseq)
  `uvm_object_new

  // Randomize the initial inputs to the DUT.
  rand lc_ctrl_pkg::lc_tx_t   lc_hw_debug_en;
  rand prim_mubi_pkg::mubi4_t scanmode;
  rand logic [NUM_HARTS-1:0]  unavailable;

  // Handles for convenience.
  jtag_dtm_reg_block jtag_dtm_ral;
  jtag_dmi_reg_block jtag_dmi_ral;

  virtual function void set_handles();
    super.set_handles();
    jtag_dtm_ral = cfg.m_jtag_agent_cfg.jtag_dtm_ral;
    jtag_dmi_ral = cfg.jtag_dmi_ral;
  endfunction

  task pre_start();
    // Initialize the input signals with defaults at the start of the sim.
    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(lc_hw_debug_en)
    cfg.rv_dm_vif.lc_hw_debug_en <= lc_hw_debug_en;
    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(scanmode)
    cfg.rv_dm_vif.scanmode <= scanmode;
    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(unavailable)
    cfg.rv_dm_vif.unavailable <= unavailable;
    super.pre_start();
  endtask

  virtual task dut_init(string reset_kind = "HARD");
    super.dut_init();
    // TODO: Randomize the contents of the debug ROM & the program buffer once out of reset.

    // "Activate" the DM to facilitate ease of testing.
    csr_wr(.ptr(jtag_dmi_ral.dmcontrol.dmactive), .value(1), .blocking(1), .predict(1));
  endtask

  // Have scan reset also applied at the start.
  virtual task apply_reset(string kind = "HARD");
    fork
      if (kind inside {"HARD", "TRST"}) begin
        jtag_dtm_ral.reset("HARD");
        jtag_dmi_ral.reset("HARD");
        cfg.m_jtag_agent_cfg.vif.do_trst_n();
      end
      if (kind inside {"HARD", "SCAN"}) apply_scan_reset();
      super.apply_reset(kind);
    join
  endtask

  // Apply scan reset.
  virtual task apply_scan_reset();
    uint delay;
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(delay, delay inside {[0:1000]};) // ns
    #(delay * 1ns);
    cfg.rv_dm_vif.scan_rst_n <= 1'b0;
    // Wait for core clock cycles.
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(delay, delay inside {[2:50]};) // cycles
    cfg.clk_rst_vif.wait_clks(delay);
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(delay, delay inside {[0:1000]};) // ns
    cfg.rv_dm_vif.scan_rst_n <= 1'b1;
  endtask

  virtual task dut_shutdown();
    // Check for pending rv_dm operations and wait for them to complete.
    // TODO: Improve this later.
    cfg.clk_rst_vif.wait_clks(200);
  endtask

  // Spawns off a thread to auto-respond to incoming TL accesses on the SBA host interface.
  // TODO: Drive intg error on D channel.
  // TODO: Drive d_error.
  virtual task launch_tl_sba_device_seq(bit blocking = 1'b0);
    cip_tl_device_seq m_tl_sba_device_seq;
    m_tl_sba_device_seq = cip_tl_device_seq::type_id::create("m_tl_sba_device_seq");
    m_tl_sba_device_seq.max_rsp_delay = 80;
    m_tl_sba_device_seq.rsp_abort_pct = 25;
    `DV_CHECK_RANDOMIZE_FATAL(m_tl_sba_device_seq)
    if (blocking) begin
      m_tl_sba_device_seq.start(p_sequencer.tl_sba_sequencer_h);
    end else begin
      fork m_tl_sba_device_seq.start(p_sequencer.tl_sba_sequencer_h); join_none
      // To ensure the seq above starts executing before the code following it starts executing.
      #0;
    end
  endtask

endclass : rv_dm_base_vseq
