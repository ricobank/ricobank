// SPDX-License-Identifier: AGPL-3.0-or-later
// copyright (c) 2023 the bank
pragma solidity 0.8.19;

import { Math } from '../../mixin/math.sol';
import { Flog } from '../../mixin/flog.sol';
import { Lock } from '../../mixin/lock.sol';
import { Gem } from '../../../lib/gemfab/src/gem.sol';

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
}

interface Flowback {
    function flowback(uint256 aid, uint refund) external;
}

interface NFTHook {
    function grant(uint tokenId) external;
}

// similar to gem dutch flower, but for NFTs
contract DutchNFTFlower is Math, Lock, Flog {
    struct Ramp {
        uint256 fel;  // [ray] rate of change in asking price/second
        uint256 gel;  // [ray] multiply by basefee for creator reward
        uint256 uel;  // [ray] multiply by wam for starting ask
    }

    struct Auction {
        address vow;  // vow
        address flo;  // client
        uint[]  hat;  // have tokenIds
        uint256 wam;  // want amount
        uint256 ask;  // starting ask price
        uint256 gun;  // starting timestamp
        address payable gir;  // keeper
        uint256 gim;  // keeper eth reward
        uint256 valid; // 2 good, 1 bad
    }

    enum Valid { UNINITIALIZED, INVALID, VALID }

    mapping (address usr => Ramp) ramps;
    mapping (uint256 aid => Auction) public auctions;

    error ErrCurbKey();
    error ErrEmptyAid();
    error ErrTransfer();
    error ErrHighStep();
    error ErrTinyFlow();

    uint256 internal constant delay = 5;

    IERC721 internal immutable nft;
    Gem     internal immutable rico;

    uint256   public count;
    uint256[] public aids;

    constructor(address _nft, address _rico) {
        nft = IERC721(_nft);
        rico = Gem(_rico);
    }

    function flow(
        address   vow,
        uint[]    calldata hat,
        uint      wam,
        address payable gir
    ) _lock_ _flog_ external returns (uint256 aid) {
        address flo = msg.sender;
        Ramp storage ramp = ramps[flo];
        if (aids.length > 0) {
            aid = aids[aids.length - 1];
            aids.pop();
        } else {
            aid = ++count;
        }
        Auction storage auction = auctions[aid];
        auction.vow = vow;
        auction.flo = flo;
        auction.hat = hat;
        auction.wam = wam;
        auction.ask = rmul(wam, ramp.uel);
        auction.gun = block.timestamp + delay;
        auction.gir = gir;
        auction.gim = rmul(block.basefee, ramp.gel);
        auction.valid = uint(Valid.VALID);
    }

    // reverse dutch auction where price for entire lot is lowered with time
    // flowback what's unused
    function glug(uint256 aid) _lock_ _flog_ payable external {
        Auction storage auction = auctions[aid];

        if (uint(Valid.VALID) != auction.valid) revert ErrEmptyAid();

        uint256 price = curp(aid, block.timestamp);
        uint256 wam   = auction.wam;
        uint256 rest  = price > wam ? price - wam : 0;
        address vow   = auction.vow;
        address flo   = auction.flo;

        rico.transferFrom(msg.sender, vow, price - rest);
        // difference from ERC20 Dutch Flower:
        // this one flows back rico, ERC20 Dutch flowed back `hag`
        rico.transferFrom(msg.sender, flo, rest);
        uint ntoks = auction.hat.length;
        uint i;
        while (true) {
            uint id = auction.hat[i];
            NFTHook(flo).grant(id);
            nft.transferFrom(flo, msg.sender, id);
            unchecked{ i++; }
            if (i >= ntoks) break;
        }

        Flowback(flo).flowback(aid, rest);

        // pay whomever paid the gas to create the auction
        uint256 gim = auction.gim;
        if (msg.value < gim) revert ErrTransfer();
        auction.gir.send(gim);
        auction.valid = uint(Valid.INVALID);
        aids.push(aid);
    }

    // auction's asking price at `time`
    function curp(uint aid, uint time) public view returns (uint) {
        Auction storage auction = auctions[aid];
        Ramp storage ramp = ramps[auction.flo];
        uint fel = ramp.fel;
        // fel < RAY, so price decreases with time
        return grow(auction.ask, fel, time - auction.gun);
    }

    function curb(bytes32 key, uint val) _flog_ external {
        Ramp storage ramp = ramps[msg.sender];
        if (key == 'fel') {
            if (val > RAY) revert ErrHighStep();
            ramp.fel = val;
        } else if (key == 'gel') {
            ramp.gel = val;
        } else if (key == 'uel') {
            ramp.uel = val;
        } else { revert ErrCurbKey(); }
    }

}
