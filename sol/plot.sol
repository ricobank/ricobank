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
    struct Feed {
        address src;
        bytes32 tag;
    }

    FeedbaseLike public fb;
    VatLike      public vat;
    
    // ilk -> Feed
    mapping( bytes32 => Feed ) public routes;

    function poke(bytes32 ilk) external {
        Feed storage feed = routes[ilk];
        (bytes32 val, uint256 ttl) = fb.read(feed.src, feed.tag);
        uint wad = block.timestamp < ttl ? uint(val) : 0;
        vat.plot(ilk, wad * BLN);
    }

    function wire(bytes32 ilk, address src, bytes32 tag) external {
        ward();
        routes[ilk] = Feed({src: src, tag: tag});
    }

    function file_fb(address fbl) external {
        ward();
        fb = FeedbaseLike(fbl);
    }

    function file_vat(address vl) external {
        ward();
        vat = VatLike(vl);
    }
}

