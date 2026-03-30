// MD+ CDDA Overlay support for MiSTer MegaDrive core
//
// Intercepts 68K bus writes to the MD+ overlay region ($3F7F6-$3FFFF)
// and decodes MD+ CDDA commands.
//
// MD+ Protocol:
//   Open overlay:  write $CD54 to $3F7FA (word)
//   Command port:  write to $3F7FE (word) - high byte = cmd, low byte = param
//   Result port:   read $3F7FC (word)
//   Close overlay: write anything != $CD54 to $3F7FA
//   ID ports:      $3F7F6 = $4241 ("BA"), $3F7F8 = $5445 ("TE")
//
// Commands:
//   $11XX - play track XX once
//   $12XX - play track XX and loop
//   $13XX - stop/fade (XX=0: immediate, XX>0: fade over XX sectors @ 75/sec)
//   $1400 - resume after pause
//   $15XX - set volume (XX = 0-255)
//   $17XX - read sector (data commands, not needed for audio)
//   $18XX - transfer sector
//   $19XX - read next sector

module md_plus
(
    input             clk,
    input             reset,

    input      [23:1] cart_addr,
    input      [15:0] cart_data_wr,
    input             cart_cs,
    input             cart_oe,
    input             cart_lwr,
    input             cart_uwr,

    output reg        mdp_data_en,
    output reg [15:0] mdp_data_out,
    output            mdp_dtack,

    output reg        mdp_track_request,
    output reg  [7:0] mdp_track_num,
    output reg        mdp_track_loop,
    output reg        mdp_stop_request,
    output reg  [7:0] mdp_fade_sectors,
    output reg        mdp_resume_request,
    output reg  [7:0] mdp_volume,
    output reg        mdp_volume_request,

    input             mdp_playing,
    input       [7:0] mdp_current_track,

    output reg        mdp_active,
    output reg [15:0] mdp_last_cmd
);

// Address decode
// Word addresses (cart_addr is [23:1], so byte addr = {cart_addr, 1'b0})

localparam [23:1] ADDR_ID0     = 23'h1FBFB;  // $3F7F6
localparam [23:1] ADDR_ID1     = 23'h1FBFC;  // $3F7F8
localparam [23:1] ADDR_CONTROL = 23'h1FBFD;  // $3F7FA
localparam [23:1] ADDR_RESULT  = 23'h1FBFE;  // $3F7FC
localparam [23:1] ADDR_COMMAND = 23'h1FBFF;  // $3F7FE

localparam [15:0] OVERLAY_MAGIC = 16'hCD54;
localparam [15:0] ID_PORT_0     = 16'h4241;  // "BA"
localparam [15:0] ID_PORT_1     = 16'h5445;  // "TE"

// Overlay state

reg overlay_open;
reg cmd_written;

wire addr_in_overlay = (cart_addr >= ADDR_ID0) && (cart_addr <= ADDR_COMMAND);
wire is_write = cart_lwr | cart_uwr;
wire is_read  = cart_oe;

// Edge detect to avoid re-triggering on held writes
reg old_write;
wire write_pulse = is_write & addr_in_overlay & ~old_write;

always @(posedge clk) begin
    old_write <= is_write & addr_in_overlay;
end

// Command processing

always @(posedge clk) begin
    if (reset) begin
        overlay_open        <= 0;
        mdp_active          <= 0;
        mdp_track_request   <= 0;
        mdp_stop_request    <= 0;
        mdp_resume_request  <= 0;
        mdp_volume_request  <= 0;
        mdp_volume          <= 8'hFF;
        mdp_track_num       <= 0;
        mdp_track_loop      <= 0;
        mdp_fade_sectors    <= 0;
        mdp_last_cmd        <= 0;
        cmd_written         <= 0;
    end
    else begin
        mdp_track_request   <= 0;
        mdp_stop_request    <= 0;
        mdp_resume_request  <= 0;
        mdp_volume_request  <= 0;

        // Neodev patches poll command port high byte for $00 to confirm
        // command completion. We dispatch instantly, so clear on next cycle.
        if (cmd_written) begin
            mdp_last_cmd <= 0;
            cmd_written  <= 0;
        end

        if (write_pulse) begin
            case (cart_addr)
                ADDR_CONTROL: begin
                    if (cart_data_wr == OVERLAY_MAGIC)
                        overlay_open <= 1;
                    else
                        overlay_open <= 0;
                end

                ADDR_COMMAND: begin
                    if (overlay_open) begin
                        mdp_last_cmd <= cart_data_wr;
                        cmd_written  <= 1;

                        case (cart_data_wr[15:8])
                            8'h11: begin
                                mdp_track_num     <= cart_data_wr[7:0];
                                mdp_track_loop    <= 0;
                                mdp_track_request <= 1;
                            end
                            8'h12: begin
                                mdp_track_num     <= cart_data_wr[7:0];
                                mdp_track_loop    <= 1;
                                mdp_track_request <= 1;
                            end
                            8'h13: begin
                                mdp_fade_sectors   <= cart_data_wr[7:0];
                                mdp_stop_request   <= 1;
                            end
                            8'h14: begin
                                mdp_resume_request <= 1;
                            end
                            8'h15: begin
                                mdp_volume         <= cart_data_wr[7:0];
                                mdp_volume_request <= 1;
                            end
                            default: ;
                        endcase
                    end
                end

                default: ;
            endcase
        end

        mdp_active <= overlay_open;
    end
end

// Read data mux

always @(posedge clk) begin
    mdp_data_en  <= 0;
    mdp_data_out <= 16'hFFFF;

    if (is_read & addr_in_overlay & overlay_open) begin
        case (cart_addr)
            ADDR_ID0: begin
                mdp_data_en  <= 1;
                mdp_data_out <= ID_PORT_0;
            end
            ADDR_ID1: begin
                mdp_data_en  <= 1;
                mdp_data_out <= ID_PORT_1;
            end
            ADDR_RESULT: begin
                mdp_data_en  <= 1;
                // {current_track[7:0], 7'b0, playing}
                mdp_data_out <= {mdp_current_track, 7'b0, mdp_playing};
            end
            ADDR_CONTROL: begin
                mdp_data_en  <= 1;
                mdp_data_out <= overlay_open ? OVERLAY_MAGIC : 16'h0000;
            end
            ADDR_COMMAND: begin
                mdp_data_en  <= 1;
                mdp_data_out <= mdp_last_cmd;
            end
            default: begin
                // Data area $3F800-$3FFFF — return zeros for now
                if (cart_addr > ADDR_COMMAND) begin
                    mdp_data_en  <= 1;
                    mdp_data_out <= 16'h0000;
                end
            end
        endcase
    end
end

assign mdp_dtack = mdp_data_en;

endmodule
