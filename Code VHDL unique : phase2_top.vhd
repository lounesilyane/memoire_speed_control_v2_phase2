library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- MODULE : motor_driver (Phase 1 validé, inchangé)
-- ============================================================
entity motor_driver is
    port (
        clk        : in  STD_LOGIC;
        reset_n    : in  STD_LOGIC;
        duty_cycle : in  STD_LOGIC_VECTOR(7 downto 0);
        direction  : in  STD_LOGIC;
        pwm_out    : out STD_LOGIC;
        in1_out    : out STD_LOGIC;
        in2_out    : out STD_LOGIC
    );
end motor_driver;

architecture rtl of motor_driver is
    
    constant CLOCK_FREQ       : integer := 27_000_000;
    constant PWM_FREQ         : integer := 10_000;
    constant PERIOD_TICKS     : integer := CLOCK_FREQ / PWM_FREQ;
    constant PERIOD_WIDTH     : integer := 12;
    constant DEAD_TIME_CYCLES : integer := 100;
    
    signal counter        : unsigned(PERIOD_WIDTH-1 downto 0);
    signal duty_threshold : integer range 0 to PERIOD_TICKS;
    signal pwm_internal   : STD_LOGIC;
    
    signal direction_reg    : STD_LOGIC := '0';
    signal direction_sync   : STD_LOGIC;
    signal direction_prev   : STD_LOGIC;
    signal dead_time_cnt    : unsigned(7 downto 0);
    signal dead_time_active : STD_LOGIC;

begin

    duty_threshold <= (to_integer(unsigned(duty_cycle)) * PERIOD_TICKS) / 256;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            counter      <= (others => '0');
            pwm_internal <= '0';
        elsif rising_edge(clk) then
            if counter >= to_unsigned(PERIOD_TICKS - 1, PERIOD_WIDTH) then
                counter <= (others => '0');
            else
                counter <= counter + 1;
            end if;

            if to_integer(counter) < duty_threshold then
                pwm_internal <= '1';
            else
                pwm_internal <= '0';
            end if;
        end if;
    end process;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            direction_reg    <= '0';
            direction_sync   <= '0';
            direction_prev   <= '0';
            dead_time_cnt    <= (others => '0');
            dead_time_active <= '0';
        elsif rising_edge(clk) then
            direction_sync <= direction;
            direction_prev <= direction_sync;

            if dead_time_active = '0' then
                if direction_sync /= direction_reg then
                    dead_time_active <= '1';
                    dead_time_cnt <= to_unsigned(DEAD_TIME_CYCLES, dead_time_cnt'length);
                end if;
            else
                if dead_time_cnt = 0 then
                    dead_time_active <= '0';
                    direction_reg <= direction_sync;
                else
                    dead_time_cnt <= dead_time_cnt - 1;
                end if;
            end if;
        end if;
    end process;

    pwm_out <= pwm_internal when (dead_time_active = '0') else '0';
    in1_out <= direction_reg;
    in2_out <= not direction_reg;

end rtl;


-- ============================================================
-- TOP LEVEL : phase2_top
-- Rôle      : Contrôle manuel duty_cycle + direction
-- ============================================================
entity phase2_top is
    port (
        clk       : in  STD_LOGIC;     -- 27 MHz
        reset_n   : in  STD_LOGIC;     -- Actif bas
        btn_up    : in  STD_LOGIC;     -- +1 duty_cycle (pin 14)
        btn_down  : in  STD_LOGIC;     -- -1 duty_cycle (pin 15)
        btn_dir   : in  STD_LOGIC;     -- Bascule direction (pin 30)
        pwm_out   : out STD_LOGIC;     -- ENA (pin 27)
        in1_out   : out STD_LOGIC;     -- IN1 (pin 28)
        in2_out   : out STD_LOGIC      -- IN2 (pin 29)
    );
end phase2_top;

architecture structural of phase2_top is

    -- Paramètre anti-rebond : période d'échantillonnage
    constant TICK_10MS    : integer := 270_000;  -- 27 MHz * 10 ms
    constant TICK_WIDTH   : integer := 19;       -- log2(270000) ≈ 18.04
    
    -- Signaux internes
    signal duty_cycle     : unsigned(7 downto 0) := (others => '0');
    signal direction      : STD_LOGIC := '0';
    
    -- Génération tick 10 ms
    signal tick_cnt       : unsigned(TICK_WIDTH-1 downto 0);
    signal tick_10ms      : STD_LOGIC;
    
    -- Synchronisation métastabilité (2 registres @ 27 MHz)
    signal btn_up_meta    : STD_LOGIC_VECTOR(1 downto 0);
    signal btn_down_meta  : STD_LOGIC_VECTOR(1 downto 0);
    signal btn_dir_meta   : STD_LOGIC_VECTOR(1 downto 0);
    
    -- Échantillons boutons (valeur stable à 10 ms)
    signal btn_up_sample  : STD_LOGIC;
    signal btn_down_sample: STD_LOGIC;
    signal btn_dir_sample : STD_LOGIC;
    
    -- Détection front montant
    signal btn_up_prev    : STD_LOGIC;
    signal btn_down_prev  : STD_LOGIC;
    signal btn_dir_prev   : STD_LOGIC;
    signal btn_up_rise    : STD_LOGIC;
    signal btn_down_rise  : STD_LOGIC;
    signal btn_dir_rise   : STD_LOGIC;

begin

    -- =========================================================
    -- 1. Générateur d'impulsion toutes les 10 ms
    -- =========================================================
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            tick_cnt  <= (others => '0');
            tick_10ms <= '0';
        elsif rising_edge(clk) then
            tick_10ms <= '0';
            if tick_cnt >= to_unsigned(TICK_10MS - 1, TICK_WIDTH) then
                tick_cnt  <= (others => '0');
                tick_10ms <= '1';
            else
                tick_cnt <= tick_cnt + 1;
            end if;
        end if;
    end process;

    -- =========================================================
    -- 2. Synchronisation des entrées asynchrones (métastabilité)
    -- =========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            btn_up_meta   <= btn_up_meta(0)   & btn_up;
            btn_down_meta <= btn_down_meta(0) & btn_down;
            btn_dir_meta  <= btn_dir_meta(0)  & btn_dir;
        end if;
    end process;

    -- =========================================================
    -- 3. Échantillonnage boutons sur front 10 ms (anti-rebond)
    -- =========================================================
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            btn_up_sample   <= '0';
            btn_down_sample <= '0';
            btn_dir_sample  <= '0';
            btn_up_prev     <= '0';
            btn_down_prev   <= '0';
            btn_dir_prev    <= '0';
        elsif rising_edge(clk) then
            if tick_10ms = '1' then
                -- Échantillonnage des valeurs synchronisées
                btn_up_sample   <= btn_up_meta(1);
                btn_down_sample <= btn_down_meta(1);
                btn_dir_sample  <= btn_dir_meta(1);
                
                -- Mémorisation pour détection de front
                btn_up_prev   <= btn_up_sample;
                btn_down_prev <= btn_down_sample;
                btn_dir_prev  <= btn_dir_sample;
            end if;
        end if;
    end process;

    -- =========================================================
    -- 4. Détection de front montant (1 appui = 1 incrément)
    -- =========================================================
    btn_up_rise   <= '1' when (btn_up_prev   = '0' and btn_up_sample   = '1') else '0';
    btn_down_rise <= '1' when (btn_down_prev = '0' and btn_down_sample = '1') else '0';
    btn_dir_rise  <= '1' when (btn_dir_prev  = '0' and btn_dir_sample  = '1') else '0';

    -- =========================================================
    -- 5. Registre duty_cycle (saturé 0..255, pas de 1)
    -- =========================================================
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            duty_cycle <= (others => '0');
        elsif rising_edge(clk) then
            if tick_10ms = '1' then
                if btn_up_rise = '1' and duty_cycle < 255 then
                    duty_cycle <= duty_cycle + 1;
                elsif btn_down_rise = '1' and duty_cycle > 0 then
                    duty_cycle <= duty_cycle - 1;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================
    -- 6. Registre direction
    -- =========================================================
    process(clk, reset_n)
    begin
        if reset_n = '0' then
            direction <= '0';
        elsif rising_edge(clk) then
            if tick_10ms = '1' and btn_dir_rise = '1' then
                direction <= not direction;
            end if;
        end if;
    end process;

    -- =========================================================
    -- 7. Instance driver moteur (Phase 1 validé)
    -- =========================================================
    u_driver: entity work.motor_driver
        port map (
            clk        => clk,
            reset_n    => reset_n,
            duty_cycle => STD_LOGIC_VECTOR(duty_cycle),
            direction  => direction,
            pwm_out    => pwm_out,
            in1_out    => in1_out,
            in2_out    => in2_out
        );

end structural;
