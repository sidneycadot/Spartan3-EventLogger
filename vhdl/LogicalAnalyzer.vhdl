library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

use work.EventTypePackage.EventType;

entity LogicalAnalyzer is
    port (
        CLK_50MHz    : in  std_logic;
        SWITCH       : in  std_logic_vector(7 downto 0);
        BUTTON       : in  std_logic_vector(3 downto 0);
        LED          : out std_logic_vector(7 downto 0);
        SSEG_SELECT  : out std_logic_vector(3 downto 0);
        SSEG_SEGMENT : out std_logic_vector(7 downto 0);
        RS232_OUT    : out std_logic;
        B1_IN        : in  std_logic_vector(3 downto 0);
        A2_OUT       : out std_logic
    );
end entity LogicalAnalyzer;

architecture arch of LogicalAnalyzer is

type Registers is record
        reset   : boolean;
        counter : unsigned(7 downto 0);
    end record Registers;

constant cInitRegisters : Registers := (
        reset   => false,
        counter => to_unsigned(0, 7)
    );

signal CLK : std_logic;

signal rCurrent : Registers := cInitRegisters;
signal sNext : Registers;

signal sMonitorData : std_logic_vector(63 downto 0);

signal sInputSectionEventData      : EventType;
signal sInputSectionEventDataValid : boolean;

signal sFifoEventData      : EventType;
signal sFifoEventDataValid : boolean;

signal sLinePrinterReadyToReceive  : boolean;

signal sLinePrinterSerialData      : std_logic_vector(7 downto 0);
signal sLinePrinterSerialDataValid : boolean;

signal sSerialTransmitterReadyToReceive : boolean;

begin

    CLK <= CLK_50MHz;

    combinatorial : process (rCurrent) is
    variable vNext : Registers;
    begin

        vNext := rCurrent;

        vNext.reset   := (BUTTON(3) = '1');
        vNext.counter := vNext.counter + 1;

        if rCurrent.reset then
            vNext := cInitRegisters;
        end if;

        sNext <= vNext;

    end process combinatorial;

    sequential : process (CLK) is
    begin
        if rising_edge(CLK) then
            rCurrent <= sNext;
        end if;
    end process sequential;

    LED <= BUTTON & B1_IN;

    SSEG_SELECT  <= not BUTTON;
    SSEG_SEGMENT <= not SWITCH;

    sMonitorData <= "000000000000000000000000000000000000000000000000000000000000" & B1_IN;

    with SWITCH select
        A2_OUT <=
            '0'                 when "00000000",
            CLK                 when "00000001",
            rCurrent.counter(0) when "01000000",
            rCurrent.counter(1) when "01000001",
            rCurrent.counter(2) when "01000010",
            rCurrent.counter(3) when "01000011",
            rCurrent.counter(4) when "01000100",
            rCurrent.counter(5) when "01000101",
            rCurrent.counter(6) when "01000110",
            rCurrent.counter(7) when "01000111",
        not '0'                 when "10000000",
        not CLK                 when "10000001",
        not rCurrent.counter(0) when "11000000",
        not rCurrent.counter(1) when "11000001",
        not rCurrent.counter(2) when "11000010",
        not rCurrent.counter(3) when "11000011",
        not rCurrent.counter(4) when "11000100",
        not rCurrent.counter(5) when "11000101",
        not rCurrent.counter(6) when "11000110",
        not rCurrent.counter(7) when "11000111",
            '0'                 when others;

    InputSection_instance : entity work.InputSection
        port map (
            CLK              => CLK,
            RESET            => rCurrent.reset,
            MONITOR_DATA     => sMonitorData,
            EVENT_DATA       => sInputSectionEventData,
            EVENT_DATA_VALID => sInputSectionEventDataValid
        );

    SynchronousFifo_instance : entity SynchronousFifo
        port map (
            CLK            => CLK,
            RESET          => rCurrent.reset,
            DATA_IN        => sInputSectionEventData,
            DATA_IN_VALID  => sInputSectionEventDataValid,
            DATA_IN_READY  => open,
            DATA_OUT       => sFifoEventData,
            DATA_OUT_VALID => sFifoEventDataValid,
            DATA_OUT_READY => sLinePrinterReadyToReceive
        );

    LinePrinter_instance : entity work.LinePrinter
        port map (
            CLK          => CLK,
            RESET        => rCurrent.reset,
            DATA_I       => sFifoEventData,
            DATA_I_VALID => sFifoEventDataValid,
            DATA_I_READY => sLinePrinterReadyToReceive,
            DATA_O       => sLinePrinterSerialData,
            DATA_O_VALID => sLinePrinterSerialDataValid,
            DATA_O_READY => sSerialTransmitterReadyToReceive
        );

    SerialTransmitter_instance : entity work.SerialTransmitter
        port map (
            CLK         => CLK,
            RESET       => rCurrent.reset,
            OCTET       => sLinePrinterSerialData,
            OCTET_VALID => sLinePrinterSerialDataValid,
            OCTET_READY => sSerialTransmitterReadyToReceive,
            SERIAL_OUT  => RS232_OUT
        );

end architecture arch;
