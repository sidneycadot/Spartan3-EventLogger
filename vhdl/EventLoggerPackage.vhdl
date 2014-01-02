
library ieee;

use ieee.std_logic_1164.all;

package EventLoggerPackage is

    type EventType is record
            sequenceNr: std_logic_vector(63 downto 0);
            timestamp : std_logic_vector(63 downto 0);
            data      : std_logic_vector(63 downto 0);
        end record EventType;

end EventLoggerPackage;
