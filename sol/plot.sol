// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

import './mixin/ward.sol';
import './mixin/math.sol';

interface FeedbaseLike {
    function read(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}
interface VatLike {
    function plot(bytes32 ilk, uint256 ray) external;
}

contract Plotter is Ward, Math {
    FeedbaseLike public fb;
    address      public tip;
    VatLike      public vat;
    
    // ilk -> tag
    mapping( bytes32 => bytes32 ) public tags;

    function poke(bytes32 ilk) external {
        bytes32 tag = tags[ilk];
        require(tag != 0x0, 'ERR_TAG');
        (bytes32 val, uint256 ttl) = fb.read(tip, tag);
        require(block.timestamp < ttl, 'ERR_TTL');
        uint wad = uint256(val);
        vat.plot(ilk, wad * BLN);
    }

    function wire(bytes32 ilk, bytes32 tag) external {
        ward();
        tags[ilk] = tag;
    }

    function link(bytes32 key, address val) external {
        ward();
             if (key == "fb") { fb = FeedbaseLike(val); }
        else if (key == "vat") { vat = VatLike(val); }
        else if (key == "tip") { tip = val; }
        else revert("ERR_LINK");
    }
}

