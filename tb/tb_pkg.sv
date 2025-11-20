package tb_pkg;
    // Test params: change these to change tb params
    localparam integer HIGH_PERF = 1; // NOTE: dont change this, since only this design exists.
    localparam integer SEC_LEVEL = 2;
    localparam integer TOTAL_TV_NUM = 100;
    localparam integer NUM_TV_TO_EXEC = 5;
    localparam integer INITIAL_TV = 0;
    localparam string TV_BASE_PATH = "/home/franos/projects/dilithium-rtl/tb/kat/";
    localparam string RESULTS_DIR = "/home/franos/projects/dilithium-rtl/tb/results/";
    localparam string ZETAS_PATH = "/home/franos/projects/dilithium-rtl/data/zetas.txt";

    // Calculated params
    localparam integer SEED_SIZE = 256;
    localparam integer S1_SIZE = (SEC_LEVEL == 2) ? 3072
                        : (SEC_LEVEL == 3 ? 5120 : 5376);
    localparam integer S2_SIZE = (SEC_LEVEL == 2) ? 3072
                        : (SEC_LEVEL == 3 ? 6144 : 6144);
    localparam integer T1_SIZE = (SEC_LEVEL == 2) ? 10240
                         : (SEC_LEVEL == 3 ? 15360 : 20480);
    localparam integer T0_SIZE = (SEC_LEVEL == 2) ? 13312
                        : (SEC_LEVEL == 3 ? 19968 : 26624);
    localparam integer Z_SIZE = (SEC_LEVEL == 2) ? 18432
                        : (SEC_LEVEL == 3 ? 25600 : 35840);
    localparam integer H_SIZE = (SEC_LEVEL == 2) ? 672
                        : (SEC_LEVEL == 3 ? 488 : 664);
    localparam integer MSG_SIZE = 3300*8; // NOTE: Largest msg size from test vector
    localparam integer MSG_LEN_SIZE = $clog2(MSG_SIZE);

    // Ceil division for words
    localparam integer W = (HIGH_PERF) ? 64 : 32;
    localparam integer SEED_WORDS_NUM = (SEED_SIZE + W - 1) / W;
    localparam integer S1_WORDS_NUM = (S1_SIZE + W - 1) / W;
    localparam integer S2_WORDS_NUM = (S2_SIZE + W - 1) / W;
    localparam integer T0_WORDS_NUM = (T0_SIZE + W - 1) / W;
    localparam integer T1_WORDS_NUM = (T1_SIZE + W - 1) / W;
    localparam integer Z_WORDS_NUM = (Z_SIZE + W - 1) / W;
    localparam integer H_WORDS_NUM = (H_SIZE + W - 1) / W;

    // Path params
    localparam string TV_SHARED_PATH = {TV_BASE_PATH, "shared/"};
    localparam string TV_PATH = {TV_BASE_PATH, (SEC_LEVEL == 2 ? "2/" : (SEC_LEVEL == 3 ? "3/" : "5/"))};

    // Some useful global params
    localparam integer P = 10;
    localparam logic[1:0] KEYGEN_MODE = 2'b00;
    localparam logic[1:0] SIGN_MODE = 2'b10;
    localparam logic[1:0] VERIFY_MODE = 2'b01;
endpackage