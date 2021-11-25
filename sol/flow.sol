// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

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

contract RicoFlowerV1 is BalancerSwapper
                       , Flipper, Flapper, Flopper
{
    function flap(uint surplus) external {
        // swap(RICO, msg.sender, surplus, RISK, msg.sender);
    }
    function flop(uint debt) external {
    }
    function flip(bytes32 ilk, address urn, address gem, uint ink, uint art, uint chop) external {
    }
}
