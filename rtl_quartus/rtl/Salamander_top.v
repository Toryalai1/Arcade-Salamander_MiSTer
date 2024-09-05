module Salamander_top (
    input   wire            i_EMU_CLK72M,
    input   wire            i_EMU_CLK57M,
    input   wire            i_EMU_INITRST_n,
    input   wire            i_EMU_SOFTRST_n,

    //video syncs
    output  reg             o_HBLANK, //NOT the original blanking signal
    output  wire            o_VBLANK,
    output  wire            o_HSYNC,
    output  wire            o_VSYNC,
    output  wire            o_VIDEO_CEN, //video clock enable
    output  wire            o_VIDEO_DEN, //video data enable

    output  wire    [4:0]   o_VIDEO_R,
    output  wire    [4:0]   o_VIDEO_G,
    output  wire    [4:0]   o_VIDEO_B,

    //sound
    output  wire signed      [15:0]  o_SND_L,
    output  wire signed      [15:0]  o_SND_R,

    //user inputs
    input   wire    [7:0]   i_IN0, i_IN1, i_IN2, i_DIPSW1, i_DIPSW2,

    //SDRAM requests
    output  wire    [16:0]  o_EMU_DATAROM_ADDR,
    input   wire    [15:0]  i_EMU_DATAROM_DATA,
    output  wire            o_EMU_DATAROM_RDRQ,

    output  wire    [15:0]  o_EMU_PROGROM_ADDR,
    input   wire    [15:0]  i_EMU_PROGROM_DATA,
    output  wire            o_EMU_PROGROM_RDRQ,

    output  wire    [16:0]  o_EMU_PCMROM_ADDR,
    input   wire    [7:0]   i_EMU_PCMROM_DATA,
    output  wire            o_EMU_PCMROM_RDRQ,

    //PROM programming
    input   wire    [15:0]  i_EMU_PROM_ADDR,
    input   wire    [7:0]   i_EMU_PROM_DATA,
    input   wire            i_EMU_PROM_WR,
    
    input   wire            i_EMU_PROM_SNDROM_CS,
    input   wire            i_EMU_PROM_VLMROM_CS
);


///////////////////////////////////////////////////////////
//////  CLOCK DIVIDER
////

/*
            0   4   8   12  16  20
    CLK18M  _|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|_|¯|
    CLK9M   ¯¯¯|___|¯¯¯|___|¯¯¯|___|¯¯¯|___|¯¯¯|___|¯¯¯|___|
    CLK6M   ¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯|___|¯¯¯¯¯¯¯|___|
*/

reg     [3:0]   clk18m_cen_sr = 4'd1;
reg     [7:0]   clk9m_cen_sr = 8'd1;
reg     [11:0]  clk6m_cen_sr = 12'd1;
always @(posedge i_EMU_CLK72M) begin
    if(!i_EMU_INITRST_n) begin
        clk18m_cen_sr <= 4'd1;
        clk9m_cen_sr <= 8'd1;
        clk6m_cen_sr <= 12'd1;
    end
    else begin
        clk18m_cen_sr[3:1] <= clk18m_cen_sr[2:0];
        clk18m_cen_sr[0] <= clk18m_cen_sr[3];
        clk9m_cen_sr[7:1] <= clk9m_cen_sr[6:0];
        clk9m_cen_sr[0] <= clk9m_cen_sr[7];
        clk6m_cen_sr[11:1] <= clk6m_cen_sr[10:0];
        clk6m_cen_sr[0] <= clk6m_cen_sr[11];
    end
end

//clock enables, generated by shift register(for better performance);
wire            clk18m_ncen = clk18m_cen_sr[3];
wire            clk9m_ncen = clk9m_cen_sr[3];
wire            clk9m_pcen = clk9m_cen_sr[7];
wire            clk6m_ncen = clk6m_cen_sr[7];
wire            clk6m_pcen = clk6m_cen_sr[11];

reg             debug_clk9m, debug_clk6m;
always @(posedge i_EMU_CLK72M) begin
    if(clk9m_ncen) debug_clk9m <= 1'b0;
    else if(clk9m_pcen) debug_clk9m <= 1'b1;

    if(clk6m_ncen) debug_clk6m <= 1'b0;
    else if(clk6m_pcen) debug_clk6m <= 1'b1;
end

//sound clock
reg     [15:0]  clk3m58_cen_sr = 16'd1;
always @(posedge i_EMU_CLK57M) begin
    if(!i_EMU_INITRST_n) begin
        clk3m58_cen_sr <= 16'd1;
    end
    else begin
        clk3m58_cen_sr[15:1] <= clk3m58_cen_sr[14:0];
        clk3m58_cen_sr[0] <= clk3m58_cen_sr[15];
    end
end

wire            clk3m58_ncen = clk3m58_cen_sr[7];
wire            clk3m58_pcen = clk3m58_cen_sr[15];


///////////////////////////////////////////////////////////
//////  BOARD INTERCONNECTION
////

wire            gfx_scrollram_cs, gfx_videoram_cs, gfx_colorram_cs, gfx_charram_cs, gfx_objram_cs;
wire    [14:0]  gfx_addr;
wire    [15:0]  gfx_do, gfx_di;
wire            gfx_r_nw, gfx_uds_n, gfx_lds_n;
wire            abs_1h_n, abs_2h, gfx_frameparity;
wire            gfx_hflip, gfx_vflip;
wire            gfx_blk;
wire    [10:0]  gfx_cd;
wire            gfx_hblank_n, gfx_vblank_n, gfx_vsync_n, gfx_hsync_n;
wire    [7:0]   snd_code;
wire            snd_int;

assign  o_VBLANK = ~gfx_vblank_n;
assign  o_HSYNC = ~gfx_hsync_n;
assign  o_VSYNC = ~gfx_vsync_n;
assign  o_VIDEO_CEN = clk6m_pcen;
assign  o_VIDEO_DEN = gfx_blk;

wire    [15:0]  debug_video = {1'b0, o_VIDEO_B, o_VIDEO_G, o_VIDEO_R};
wire    [8:0]   hcounter;
wire    [8:0]   vcounter;


///////////////////////////////////////////////////////////
//////  CPU BOARD
////

Salamander_cpu u_cpuboard (
    .i_EMU_MCLK                 (i_EMU_CLK72M               ),
    .i_EMU_CLK9M_PCEN           (clk9m_pcen                 ),
    .i_EMU_CLK9M_NCEN           (clk9m_ncen                 ),
    .i_EMU_CLK6M_PCEN           (clk6m_pcen                 ),
    .i_EMU_CLK6M_NCEN           (clk6m_ncen                 ),

    .i_EMU_INITRST_n            (i_EMU_INITRST_n            ),
    .i_EMU_SOFTRST_n            (i_EMU_SOFTRST_n            ),

    .o_GFX_ADDR                 (gfx_addr                   ),
    .i_GFX_DO                   (gfx_do                     ),
    .o_GFX_DI                   (gfx_di                     ), 
    .o_GFX_RnW                  (gfx_r_nw                   ),
    .o_GFX_UDS_n                (gfx_uds_n                  ),
    .o_GFX_LDS_n                (gfx_lds_n                  ),

    .o_VZCS_n                   (gfx_scrollram_cs           ),
    .o_VCS1_n                   (gfx_videoram_cs            ),
    .o_VCS2_n                   (gfx_colorram_cs            ),
    .o_CHACS_n                  (gfx_charram_cs             ),
    .o_OBJRAM_n                 (gfx_objram_cs              ),

    .o_HFLIP                    (gfx_hflip                  ),
    .o_VFLIP                    (gfx_vflip                  ),

    .i_ABS_1H_n                 (abs_1h_n                   ),
    .i_ABS_2H                   (abs_2h                     ),
    
    .i_VBLANK_n                 (gfx_vblank_n               ), //470pF+LS244 10ns? delay
    .i_FRAMEPARITY              (gfx_frameparity            ), //same as above

    .i_BLK                      (gfx_blk                    ),

    .i_CD                       (gfx_cd                     ),

    .o_SNDCODE                  (snd_code                   ),
    .o_SNDINT                   (snd_int                    ),

    .i_IN0                      (i_IN0                      ),
    .i_IN1                      (i_IN1                      ),
    .i_IN2                      (i_IN2                      ),
    .i_DIPSW1                   (i_DIPSW1                   ),
    .i_DIPSW2                   (i_DIPSW2                   ),

    .o_VIDEO_R                  (o_VIDEO_R                  ),
    .o_VIDEO_G                  (o_VIDEO_G                  ),
    .o_VIDEO_B                  (o_VIDEO_B                  ),

    .o_EMU_DATAROM_ADDR         (o_EMU_DATAROM_ADDR         ),
    .i_EMU_DATAROM_DATA         (i_EMU_DATAROM_DATA         ),
    .o_EMU_DATAROM_RDRQ         (o_EMU_DATAROM_RDRQ         ),

    .o_EMU_PROGROM_ADDR         (o_EMU_PROGROM_ADDR         ),
    .i_EMU_PROGROM_DATA         (i_EMU_PROGROM_DATA         ),
    .o_EMU_PROGROM_RDRQ         (o_EMU_PROGROM_RDRQ         )
);



///////////////////////////////////////////////////////////
//////  VIDEO BOARD
////

GX400_video u_gx400_video (
    .i_EMU_MCLK                 (i_EMU_CLK72M               ),

    .i_EMU_CLK18M_NCEN          (clk18m_ncen                ),
    .i_EMU_CLK6M_PCEN           (clk6m_pcen                 ),
    .i_EMU_CLK6M_NCEN           (clk6m_ncen                 ),

    .i_MRST_n                   (i_EMU_INITRST_n            ),

    .i_GFX_ADDR                 (gfx_addr                   ),
    .o_GFX_DO                   (gfx_do                     ),
    .i_GFX_DI                   (gfx_di                     ), 
    .i_GFX_RnW                  (gfx_r_nw                   ),
    .i_GFX_UDS_n                (gfx_uds_n                  ),
    .i_GFX_LDS_n                (gfx_lds_n                  ),

    .i_VZCS_n                   (gfx_scrollram_cs           ),
    .i_VCS1_n                   (gfx_videoram_cs            ),
    .i_VCS2_n                   (gfx_colorram_cs            ),
    .i_CHACS_n                  (gfx_charram_cs             ),
    .i_OBJRAM_n                 (gfx_objram_cs              ),

    .i_HFLIP                    (gfx_hflip                  ),
    .i_VFLIP                    (gfx_vflip                  ),

    .o_HBLANK_n                 (gfx_hblank_n               ),
    .o_VBLANK_n                 (gfx_vblank_n               ),
    .o_HSYNC_n                  (gfx_hsync_n                ),
    .o_VSYNC_n                  (gfx_vsync_n                ),

    .o_ABS_1H_n                 (abs_1h_n                   ),
    .o_ABS_2H                   (abs_2h                     ),
    .o_FRAMEPARITY              (gfx_frameparity            ),

    .o_BLK                      (gfx_blk                    ),

    .o_CD                       (gfx_cd                     ),

    .o_DEBUG_HCNTR              (hcounter                   ),
    .o_DEBUG_VCNTR              (vcounter                   )
);

always @(posedge i_EMU_CLK72M) begin
    if(!i_EMU_INITRST_n) begin
        o_HBLANK <= 1'b0;
    end
    else begin if(clk6m_pcen) begin
        if(hcounter == 9'd149) o_HBLANK <= 1'b1;
        else if(hcounter == 9'd277) o_HBLANK <= 1'b0;
    end end
end



///////////////////////////////////////////////////////////
//////  SOUND SECTION
////

Salamander_sound u_sound (
    .i_EMU_MCLK                 (i_EMU_CLK57M               ),
    .i_EMU_CLK3M58_PCEN         (clk3m58_pcen               ),
    .i_EMU_CLK3M58_NCEN         (clk3m58_ncen               ),

    .i_EMU_INITRST_n            (i_EMU_INITRST_n            ),
    .i_EMU_SOFTRST_n            (i_EMU_SOFTRST_n            ),

    .i_SNDCODE                  (snd_code                   ),
    .i_SNDINT                   (snd_int                    ),

    .o_SND_L                    (o_SND_L                    ),
    .o_SND_R                    (o_SND_R                    ),

    .o_EMU_PCMROM_ADDR          (o_EMU_PCMROM_ADDR          ),
    .i_EMU_PCMROM_DATA          (i_EMU_PCMROM_DATA          ),
    .o_EMU_PCMROM_RDRQ          (o_EMU_PCMROM_RDRQ          ),

    .i_EMU_PROM_CLK             (i_EMU_CLK72M               ),
    .i_EMU_PROM_ADDR            (i_EMU_PROM_ADDR            ),
    .i_EMU_PROM_DATA            (i_EMU_PROM_DATA            ),
    .i_EMU_PROM_WR              (i_EMU_PROM_WR              ),
    
    .i_EMU_PROM_SNDROM_CS       (i_EMU_PROM_SNDROM_CS       ),
    .i_EMU_PROM_VLMROM_CS       (i_EMU_PROM_VLMROM_CS       )
);


endmodule