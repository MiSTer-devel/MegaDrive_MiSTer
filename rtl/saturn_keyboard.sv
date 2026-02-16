// Saturn Keyboard emulation
//
// Saturn keyboard packet (12 nibbles):
//   0: 0x3
//   1: 0x4
//   2: {Right, Left, Down, Up}
//   3: {Start, A, C, B}
//   4: {R, X, Y, Z}
//   5: {L, 0, 0, 0}
//   6: {0, Caps, Num, Scr}
//   7: {Make, 1, 1, Break}  (0xE make, 0x7 break, 0x6 none)
//   8: scancode[7:4]
//   9: scancode[3:0]
//  10: 0x0
//  11: 0x1
//
// Notes:
// - Many keys are identical to PS/2 set-2 scancodes.
// - Extended (E0) keys are remapped into the Saturn table assigned new codes.

module saturn_keyboard (
  input  logic        clk,
  input  logic        reset,
  input  logic        enable,

  // MiSTer ps2_key bus: [10]=toggle, [9]=pressed, [8]=E0, [7:0]=set2 code
  input  logic [10:0] ps2_key,
  output logic [2:0]  ps2_led,

  input  logic [6:0]  port_o,      // PB_o / PA_o
  input  logic [6:0]  port_d,      // PB_d / PA_d (1=input,0=output)
  input  logic [6:0]  port_i_in,   // normal md_io_portX to passthrough

  output logic [6:0]  port_i_out   // goes to PB_i / PA_i
);

  // Fixed tuning/constants
  localparam int FIFO_DEPTH = 16;
  localparam int ACK_DELAY  = 16;

  // -----------------------------
  // Direction match for Saturn KB mode.
  // In this core, TH/TR outputs => d[6:5]=00 for packet mode and 01 for ID mode.
  // Keep the gate tolerant and only require TH/TR direction.
  // -----------------------------
  logic [1:0] port_o_65_s1, port_o_65_s2;
  logic [1:0] port_d_65_s1, port_d_65_s2;

  wire cfg_ok        = (port_d_65_s2 == 2'b00);
  wire id_ok         = (port_d_65_s2 == 2'b01);
  wire kbd_active    = enable & cfg_ok;
  wire id_active     = enable & id_ok;

  // Host lines
  wire tr = port_o_65_s2[0];
  wire th = port_o_65_s2[1];
  wire idle_cmd = (th & tr); // host writes 0x60 to data to end/idle

  // -----------------------------
  // PS/2 capture
  // -----------------------------
  logic ps2_tgl_d;
  wire  ps2_evt     = (ps2_tgl_d != ps2_key[10]);
  wire  ps2_pressed = ps2_key[9];
  wire  ps2_ext     = ps2_key[8];
  wire [7:0] ps2_code = ps2_key[7:0];

  logic caps_lock, num_lock, scr_lock;
  assign ps2_led = {scr_lock, num_lock, caps_lock};
  
  logic btn_up, btn_down, btn_left, btn_right;
  logic btn_start, btn_a, btn_b, btn_c;
  logic btn_x, btn_y, btn_z, btn_l, btn_r;

  // FIFO: {make, scancode}
  localparam int F_AW = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
  localparam int ACK_W = (ACK_DELAY <= 0) ? 1 : $clog2(ACK_DELAY+1);
  logic [8:0] fifo [FIFO_DEPTH];
  logic [F_AW-1:0] wr_ptr, rd_ptr;
  logic [F_AW:0]   fifo_cnt;

  // current latched event for packet
  logic       ev_valid;
  logic       ev_make;
  logic [7:0] ev_sc;

  // -----------------------------
  // PS/2 set2 -> Saturn scancode mapping
  // Returns {valid, sat_scancode}
  // -----------------------------
  function automatic logic [8:0] map_ps2_to_saturn(input logic ext, input logic [7:0] code);
    logic v;
    logic [7:0] s;
    begin
      v = 1'b1;
      s = code; // most are identical

      if(ext) begin
        unique case(code)
          8'h11: s = 8'h17; // RAlt
          8'h14: s = 8'h18; // RCtrl
          8'h5A: s = 8'h19; // KP Enter
          8'h1F: s = 8'h1F; // LWin
          8'h27: s = 8'h27; // RWin
          8'h2F: s = 8'h2F; // Menu
          8'h4A: s = 8'h80; // KP /
          8'h70: s = 8'h81; // Insert
          8'h7C: s = 8'h84; // PrtScr
          8'h71: s = 8'h85; // Delete
          8'h6B: s = 8'h86; // Left
          8'h6C: s = 8'h87; // Home
          8'h69: s = 8'h88; // End
          8'h75: s = 8'h89; // Up
          8'h72: s = 8'h8A; // Down
          8'h7D: s = 8'h8B; // PgUp
          8'h7A: s = 8'h8C; // PgDn
          8'h74: s = 8'h8D; // Right
          default: v = 1'b0;
        endcase
      end
      else begin
        // ignore helper/meta bytes if they ever appear
        if(code == 8'h00 || code == 8'hE0 || code == 8'hE1 || code == 8'hF0) v = 1'b0;
      end

      map_ps2_to_saturn = {v, s};
    end
  endfunction

  // -----------------------------
  // Packet / ACK state
  // -----------------------------
  logic tr_d;
  logic ack;
  logic [ACK_W-1:0] ack_cnt;

  logic in_packet;
  logic [3:0] nib_idx;
  logic [3:0] nibble;
  
  logic [3:0] nib_dpad;
  logic [3:0] nib_start_abc;
  logic [3:0] nib_rxyz;
  logic [3:0] nib_lxxx;

  // Saturn packet button fields use active-low button bits.
  assign nib_dpad      = {~btn_right, ~btn_left, ~btn_down, ~btn_up};   // Right Left Down Up
  assign nib_start_abc = {~btn_start, ~btn_a, ~btn_c, ~btn_b};          // Start A C B
  assign nib_rxyz      = {~btn_r, ~btn_x, ~btn_y, ~btn_z};              // R X Y Z
  assign nib_lxxx      = {~btn_l, 3'b000};                              // L 0 0 0

  // nibble generator
  always_comb begin
    if(!in_packet) begin
      // Probe/read-idle phase: software expects low nibble == 1 after writing 0x20.
      nibble = 4'h1;
    end else begin
      unique case(nib_idx)
        4'd0:  nibble = 4'h3;
        4'd1:  nibble = 4'h4;
        4'd2:  nibble = nib_dpad;
        4'd3:  nibble = nib_start_abc;
        4'd4:  nibble = nib_rxyz;
        4'd5:  nibble = nib_lxxx;
        4'd6:  nibble = {1'b0, caps_lock, num_lock, scr_lock};
        4'd7:  nibble = { (ev_valid &  ev_make), 1'b1, 1'b1, (ev_valid & ~ev_make) };
        4'd8:  nibble = ev_sc[7:4];
        4'd9:  nibble = ev_sc[3:0];
        4'd10: nibble = 4'h0;
        4'd11: nibble = 4'h1;
        default: nibble = 4'h0;
      endcase
    end
  end

  // keyboard-driven pin image (bits6..0)
  wire [6:0] port_kbd_i = {2'b11, ack, nibble}; // TH/TR pulled up, TL=ack, data=nibble
  // Saturn peripheral ID response used by software detector (ID = 0x5).
  wire [6:0] port_id_i  = {2'b11, 1'b1, 4'h1};

  // passthrough mux
  assign port_i_out = id_active ? port_id_i : (kbd_active ? port_kbd_i : port_i_in);

  // -----------------------------
  // Sequential
  // -----------------------------
  logic kbd_active_d;

  always_ff @(posedge clk) begin
    if(reset) begin
      port_o_65_s1  <= 2'b11;
      port_o_65_s2  <= 2'b11;
      port_d_65_s1  <= 2'b11;
      port_d_65_s2  <= 2'b11;

      ps2_tgl_d    <= 1'b0;
      caps_lock    <= 1'b0;
      num_lock     <= 1'b0;
      scr_lock     <= 1'b0;

      {btn_up, btn_down, btn_left, btn_right, btn_start, btn_a, btn_b,
       btn_c, btn_x, btn_y, btn_z, btn_l, btn_r} <= '0;

      wr_ptr       <= '0;
      rd_ptr       <= '0;
      fifo_cnt     <= '0;

      ev_valid     <= 1'b0;
      ev_make      <= 1'b0;
      ev_sc        <= 8'h00;

      tr_d         <= 1'b1;
      ack          <= 1'b1;
      ack_cnt      <= '0;
      in_packet    <= 1'b0;
      nib_idx      <= 4'd0;

      kbd_active_d <= 1'b0;
    end else begin
      logic deq_evt, enq_evt;
      logic [8:0] mapped;

      deq_evt = 1'b0;
      enq_evt = 1'b0;
      mapped  = '0;

      port_o_65_s1  <= port_o[6:5];
      port_o_65_s2  <= port_o_65_s1;
      port_d_65_s1  <= port_d[6:5];
      port_d_65_s2  <= port_d_65_s1;

      ps2_tgl_d    <= ps2_key[10];
      kbd_active_d <= kbd_active;

      // On activation edge, sync to current TR so we don't "fake toggle"
      if(kbd_active && !kbd_active_d) begin
        tr_d      <= tr;
        ack       <= tr;
        ack_cnt   <= '0;
        in_packet <= 1'b0;
        nib_idx   <= 4'd0;
      end

      // If not active, keep neutral packet state (but still buffer PS/2)
      if(!kbd_active) begin
        in_packet <= 1'b0;
        ack       <= 1'b1;
        ack_cnt   <= '0;
        tr_d      <= tr;
      end else begin
        // End packet when host idles (writes 0x60)
        if(idle_cmd) begin
          in_packet <= 1'b0;
        end

        // Detect TR toggles
        if(tr != tr_d) begin
          tr_d    <= tr;

          // ACK behavior: briefly opposite, then match TR
          ack     <= ~tr;
          ack_cnt <= (ACK_DELAY > 0) ? ACK_DELAY[ACK_W-1:0] : '0;

          if(in_packet) begin
            if(nib_idx != 4'd11) nib_idx <= nib_idx + 1'd1;
          end else begin
            // Start packet on falling edge TR (1->0), which matches host sequence after probe
            if(tr_d == 1'b1 && tr == 1'b0 && !idle_cmd) begin
              in_packet <= 1'b1;
              nib_idx   <= 4'd0;

              // Latch one queued event for this packet
              if(fifo_cnt != 0) begin
                {ev_make, ev_sc} <= fifo[rd_ptr];
                rd_ptr   <= rd_ptr + 1'd1;
                deq_evt  = 1'b1;
                ev_valid <= 1'b1;
              end else begin
                ev_make  <= 1'b0;
                ev_sc    <= 8'h00;
                ev_valid <= 1'b0;
              end
            end
          end
        end else if(ack_cnt != 0) begin
          ack_cnt <= ack_cnt - 1'd1;
          if(ack_cnt == 1) ack <= tr;
        end
      end

      // Buffer PS/2 events into FIFO regardless of active state
      if(ps2_evt) begin
        mapped = map_ps2_to_saturn(ps2_ext, ps2_code);

        if(mapped[8]) begin
          // Keyboard packet held-button state fields (nibbles 3..6).
          // Decode once from mapped Saturn code to avoid a second ext+code decode tree.
          unique case(mapped[7:0])
            8'h76: btn_start <= ps2_pressed; // Esc -> Start
            8'h15: btn_l     <= ps2_pressed; // Q -> L
            8'h24: btn_r     <= ps2_pressed; // E -> R
            8'h1C: btn_x     <= ps2_pressed; // A -> X
            8'h1B: btn_y     <= ps2_pressed; // S -> Y
            8'h23: btn_z     <= ps2_pressed; // D -> Z
            8'h1A: btn_a     <= ps2_pressed; // Z -> A
            8'h22: btn_b     <= ps2_pressed; // X -> B
            8'h21: btn_c     <= ps2_pressed; // C -> C
            8'h86: btn_left  <= ps2_pressed; // E0 Left
            8'h8D: btn_right <= ps2_pressed; // E0 Right
            8'h89: btn_up    <= ps2_pressed; // E0 Up
            8'h8A: btn_down  <= ps2_pressed; // E0 Down
            default: ;
          endcase

          // lock toggles on MAKE
          if(ps2_pressed && !ps2_ext) begin
            unique case(mapped[7:0])
              8'h58: caps_lock <= ~caps_lock;
              8'h77: num_lock  <= ~num_lock;
              8'h7E: scr_lock  <= ~scr_lock;
              default: ;
            endcase
          end

          if((fifo_cnt < FIFO_DEPTH) || deq_evt) begin
            fifo[wr_ptr] <= {ps2_pressed, mapped[7:0]};
            wr_ptr   <= wr_ptr + 1'd1;
            enq_evt  = 1'b1;
          end
        end
      end

      case({deq_evt, enq_evt})
        2'b10: fifo_cnt <= fifo_cnt - 1'd1;
        2'b01: fifo_cnt <= fifo_cnt + 1'd1;
        default: ;
      endcase
    end
  end

endmodule
