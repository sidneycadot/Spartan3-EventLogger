library ieee;

use ieee.std_logic_1164.all,
    ieee.numeric_std.all;

use work.EventLoggerPackage.all;

entity EventFifo is
    port (
        CLK            : in  std_logic;
        RESET          : in  boolean;
        DATA_IN        : in  EventType;
        DATA_IN_VALID  : in  boolean;
        DATA_IN_READY  : out boolean;
        DATA_OUT       : out EventType;
        DATA_OUT_VALID : out boolean;
        DATA_OUT_READY : in  boolean
    );
end entity EventFifo;

architecture arch of EventFifo is

signal sDataIn  : std_logic_vector(191 downto 0);
signal sDataOut : std_logic_vector(191 downto 0);

begin

    sDataIn <= DATA_IN.sequenceNr & DATA_IN.timestamp & DATA_IN.data;

    BlockRamFifo_instance: entity BlockRamFifo
        port map (
            CLK            => CLK,
            RESET          => RESET,
            DATA_IN        => sDataIn,
            DATA_IN_VALID  => DATA_IN_VALID,
            DATA_IN_READY  => DATA_IN_READY,
            DATA_OUT       => sDataOut,
            DATA_OUT_VALID => DATA_OUT_VALID,
            DATA_OUT_READY => DATA_OUT_READY
        );

    DATA_OUT <= (
        sequenceNr => sDataOut(191 downto 128),
        timestamp  => sDataOut(127 downto  64),
        data       => sDataOut( 63 downto   0)
    );

end architecture arch;
