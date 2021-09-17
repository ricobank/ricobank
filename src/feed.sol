
// sneed's read 'n feed

import './mixin/ward.sol';

pragma solidity 0.8.6;

interface FeedbaseLike {
    function read(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}
interface VatLike {
    function feed(bytes32 ilk, uint256 ray) external;
}

contract Feeder is Ward {
    struct Feed {
        address src;
        bytes32 tag;
    }

    FeedbaseLike fb;
    VatLike      vat;
    
    // ilk -> Feed
    mapping( bytes32 => Feed ) public routes;

    function poke(bytes32 ilk) external {
        Feed storage feed = routes[ilk];
        (bytes32 val, uint256 ttl) = fb.read(feed.src, feed.tag);
        uint wad = block.timestamp < ttl ? uint(val) : 0;
        vat.feed(ilk, wad);
    }

    function wire(bytes32 i, address src, bytes32 tag) external {
      ward();
      routes[i] = Feed({src: src, tag: tag});
    }
}
