library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity phase2_top is
    port (
        clk       : in  STD_LOGIC;
        reset_n   : in  STD_LOGIC;
        btn_up    : in  STD_LOGIC;
        btn_down  : in  STD_LOGIC;
        btn_dir   : in  STD_LOGIC;
        pwm_out   : out STD_LOGIC;
        in1_out   : out STD_LOGIC;
        in2_out   : out STD_LOGIC
    );
end phase2_top;

architecture rtl of phase2_top is

    constant CLOCK_FREQ       : integer := 27_000_000;
    constant PWM_FREQ         : integer := 10_000;
    constant PERIOD_TICKS     : integer := CLOCK_FREQ / PWM_FREQ;
    constant PERIOD_WIDTH     : integer := 12;
    constant DEAD_TIME_CYCLES : integer := 100;
    constant TICK_10MS_MAX    : integer := 270_000;
    constant TICK_CNT_WIDTH   : integer := 19;
    
    signal counter            : unsigned(PERIOD_WIDTH-1 downto 0);
    signal duty_threshold     : integer range 0 to PERIOD_TICKS;
    signal pwm_internal       : STD_LOGIC;
    signal direction_reg      : STD_LOGIC;
    signal direction_target   : STD_LOGIC;
    signal dead_time_cnt      : unsigned(7 downto 0);
    signal dead_time_active   : STD_LOGIC;
    signal duty_cycle         : unsigned(7 downto 0);
    signal tick_counter       : unsigned(TICK_CNT_WIDTH-1 downto 0);
    signal tick_pulse         : STD_LOGIC;
    signal btn_up_meta        : STD_LOGIC_VECTOR(1 downto 0);
    signal btn_down_meta      : STD_LOGIC_VECTOR(1 downto 0);
    signal btn_dir_meta       : STD_LOGIC_VECTOR(1 downto 0);
    signal btn_up_sample      : STD_LOGIC;
    signal btn_down_sample    : STD_LOGIC;
    signal btn_dir_sample     : STD_LOGIC;
    signal btn_up_prev        : STD_LOGIC;
    signal btn_down_prev      : STD_LOGIC;
    signal btn_dir_prev       : STD_LOGIC;
    signal btn_up_rise        : STD_LOGIC;
    signal btn_down_rise      : STD_LOGIC;
    signal btn_dir_rise       : STD_LOGIC;

begin

    duty_threshold <= (to_integer(duty_cycle) * PERIOD_TICKS) / 256;

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
            direction_target <= '0';
            dead_time_cnt    <= (others => '0');
            dead_time_active <= '0';
        elsif rising_edge(clk) then
            if tick_pulse = '1' and btn_dir_rise = '1' then
                direction_target <= not direction_target;
            end if;
            
            if dead_time_active = '0' then
                if direction_target /= direction_reg then
                    dead_time_active <= '1';
                    dead_time_cnt <= to_unsigned(DEAD_TIME_CYCLES, dead_time_cnt'length);
                end if;
            else
                if dead_time_cnt = 0 then
                    dead_time_active <= '0';
                    direction_reg <= direction_target;
                else
                    dead_time_cnt <= dead_time_cnt - 1;
                end if;
            end if;
        end if;
    end process;

    pwm_out <= pwm_internal when (dead_time_active = '0') else '0';
    in1_out <= direction_reg;
    in2_out <= not direction_reg;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            tick_counter <= (others => '0');
            tick_pulse   <= '0';
        elsif rising_edge(clk) then
            tick_pulse <= '0';
            if tick_counter >= to_unsigned(TICK_10MS_MAX - 1, TICK_CNT_WIDTH) then
                tick_counter <= (others => '0');
                tick_pulse   <= '1';
            else
                tick_counter <= tick_counter + 1;
            end if;
        end if;
    end process;

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            btn_up_meta   <= (others => '0');
            btn_down_meta <= (others => '0');
            btn_dir_meta  <= (others => '0');
        elsif rising_edge(clk) then
            btn_up_meta   <= btn_up_meta(0)   & btn_up;
            btn_down_meta <= btn_down_meta(0) & btn_down;
            btn_dir_meta  <= btn_dir_meta(0)  & btn_dir;
        end if;
    end process;

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
            if tick_pulse = '1' then
                btn_up_sample   <= btn_up_meta(1);
                btn_down_sample <= btn_down_meta(1);
                btn_dir_sample  <= btn_dir_meta(1);
                btn_up_prev   <= btn_up_sample;
                btn_down_prev <= btn_down_sample;
                btn_dir_prev  <= btn_dir_sample;
            end if;
        end if;
    end process;

    -- COMBINATOIRE : visible immédiatement pendant tick_pulse
    btn_up_rise   <= '1' when (btn_up_prev   = '0' and btn_up_sample   = '1') else '0';
    btn_down_rise <= '1' when (btn_down_prev = '0' and btn_down_sample = '1') else '0';
    btn_dir_rise  <= '1' when (btn_dir_prev  = '0' and btn_dir_sample  = '1') else '0';

    process(clk, reset_n)
    begin
        if reset_n = '0' then
            duty_cycle <= (others => '0');
        elsif rising_edge(clk) then
            if tick_pulse = '1' then
                if btn_up_rise = '1' and duty_cycle <= 245 then
                    duty_cycle <= duty_cycle + 10;
                elsif btn_down_rise = '1' and duty_cycle >= 10 then
                    duty_cycle <= duty_cycle - 10;
                else
                    duty_cycle <= duty_cycle;
                end if;
            end if;
        end if;
    end process;

end rtl;
