
library ieee;

use ieee.std_logic_1164.all;

package EventTypePackage is

type EventType is record
        sequenceNr: std_logic_vector(63 downto 0);
        timestamp : std_logic_vector(63 downto 0);
        data      : std_logic_vector(63 downto 0);
    end record EventType;

constant cNullEvent : EventType := (sequenceNr => (others => '0'), timestamp => (others => '0'), data => (others => '0'));

end EventTypePackage;
