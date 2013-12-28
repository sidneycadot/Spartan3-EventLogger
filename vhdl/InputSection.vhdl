library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

use work.EventLoggerPackage.EventType;

entity InputSection is
    port (
        CLK              : in  std_logic;
        RESET            : in  boolean;
        MONITOR_DATA     : in  std_logic_vector(63 downto 0);
        EVENT_DATA       : out EventType;
        EVENT_DATA_VALID : out boolean
    );
end entity InputSection;

architecture arch of InputSection is

type Registers is record
        lastData        : std_logic_vector(63 downto 0);
        timestamp       : unsigned(63 downto 0);
        sequenceNr      : unsigned(63 downto 0);
        lastEmittedData : std_logic_vector(63 downto 0);
        eventData       : EventType;
        eventDataValid  : boolean;
    end record Registers;

constant cInitRegisters : Registers := (
        lastData        => (others => '-'),
        timestamp       => (others => '1'),
        sequenceNr      => (others => '0'),
        lastEmittedData => (others => '-'),
        eventData       => (sequenceNr => (others => '-'), timestamp => (others => '-'), data => (others => '-')),
        eventDataValid  => false
    );

signal rCurrent : Registers := cInitRegisters;

signal sNext : Registers;

begin

    combinatorial : process (rCurrent, MONITOR_DATA, RESET) is

    variable vNext : Registers;

    begin

        vNext := rCurrent;

        if rCurrent.timestamp = 0 or (rCurrent.timestamp > 0 and rCurrent.lastData /= rCurrent.lastEmittedData) then

            vNext.eventData.sequenceNr := std_logic_vector(rCurrent.sequenceNr);
            vNext.eventData.timestamp  := std_logic_vector(rCurrent.timestamp);
            vNext.eventData.data       := rCurrent.lastData;

            vNext.lastEmittedData      := rCurrent.lastData;
            vNext.sequenceNr           := rCurrent.sequenceNr + 1;

            vNext.eventDataValid := true;        

        else
            vNext.eventDataValid := false;        
        end if;

        vNext.lastData  := MONITOR_DATA;
        vNext.timestamp := vNext.timestamp + 1;

        if RESET then
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

    EVENT_DATA       <= rCurrent.eventData;
    EVENT_DATA_VALID <= rCurrent.eventDataValid;

end architecture arch;
