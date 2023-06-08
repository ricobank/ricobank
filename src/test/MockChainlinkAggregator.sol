/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import { Feedbase } from "../../lib/feedbase/src/Feedbase.sol";

contract MockChainlinkAggregator {
    Feedbase public fb;
    address public src;
    bytes32 public tag;
    uint public decimals;

    constructor(address _fb, address _src, bytes32 _tag, uint _decimals) {
        fb = Feedbase(_fb);
        src = _src;
        tag = _tag;
        decimals = _decimals;
    }

    function latestRoundData() view external returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {

        (bytes32 val, uint ttl) = fb.pull(src, tag);

        // only care about val and ttl
        return (0, int(uint(val)), ttl, ttl, 0);
    }
}
