
import './swap.sol';

interface Flipper {
    function flip(bytes32 ilk, address urn, address gem, uint ink, uint art, uint chop) external;
}

interface Flapper {
    function flap(uint surplus) external;
}

interface Flopper {
    function flop(uint debt) external;
}

interface Plopper {
    function plop(bytes32 ilk, address urn, uint amt) external;
}

contract RicoFlowerV1 is BalancerSwapper, Flapper {
    function flap(uint surplus) external {
        // swap(RICO, msg.sender, surplus, RISK, msg.sender);
    }
}
