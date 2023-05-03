// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

import { Math } from './mixin/math.sol';
import { Lock } from './mixin/lock.sol';
import { Flog } from './mixin/flog.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';

interface Flowback {
    function flowback(uint256 aid, uint refund) external;
}

contract DutchFlower is Math, Lock, Flog {
    struct Ramp {
        uint256 fade; // [ray] rate of change in asking price/second
        uint256 tiny; // min ham
        uint256 fuel; // [ray] mul by basefee for creator reward
        uint256 gain; // [ray] mul by feed price or wam/ham for starting ask
        address feed; // Feedbase for price if applicable
        address fsrc;
        bytes32 ftag;
    }

    struct Auction {
        address vow;  // vow
        address vip;  // client
        address hag;  // have gem
        uint256 ham;  // have amount
        address wag;  // want gem
        uint256 wam;  // want amount
        uint256 ask;  // ask price
        uint256 gun;  // starting timestamp
        address payable gir;  // keeper
        uint256 gim;  // keeper eth reward
        uint256 valid; // 2 good, 1 bad
    }

    enum Valid { UNINITIALIZED, INVALID, VALID }

    mapping (address usr => mapping (address hag => Ramp)) ramps;
    mapping (uint256 aid => Auction) public auctions;

    error ErrCurbKey();
    error ErrEmptyAid();
    error ErrTransfer();
    error ErrHighStep();
    error ErrTinyFlow();
    error ErrStale();

    uint256 internal constant DELAY = 5;
    uint256 internal constant FLIP_DUST = 0;

    uint256 public count;
    uint256[] public aids;

    function flow(
        address vow,
        address hag, 
        uint    ham,
        address wag,
        uint    wam,
        address payable gir
    ) _lock_ _flog_ external returns (uint256 aid) {
        address vip = msg.sender;
        Ramp storage ramp = ramps[vip][hag];
        uint256 tiny = ramp.tiny;
        if (tiny > FLIP_DUST) {
            if (ham < tiny) revert ErrTinyFlow();
            // preload the hags instead of doing transferFrom in glug
            if (!Gem(hag).transferFrom(msg.sender, address(this), ham)) {
                revert ErrTransfer();
            }
        }

        // avoid cold sstores when possible
        if (aids.length > 0) {
            aid = aids[aids.length - 1];
            aids.pop();
        } else {
            aid = ++count;
        }

        Auction storage auction = auctions[aid];
        auction.vow = vow;
        auction.vip = vip;
        auction.hag = hag;
        auction.ham = ham;
        auction.wag = wag;
        auction.wam = wam;

        // feed pull for keep (flop+flap), wam/ham for bail (flip)
        uint p;
        if (auctions[aid].wam == type(uint).max) {
            (bytes32 _p, uint ttl) = Feedbase(ramp.feed).pull(ramp.fsrc, ramp.ftag);
            if (ttl < block.timestamp) revert ErrStale();
            p = uint(_p);
        } else {
            p = rdiv(wam, ham);
        }
        auction.ask = rmul(p, ramp.gain);

        auctions[aid].gun = block.timestamp + DELAY;
        auctions[aid].gir = gir;
        auctions[aid].gim = rmul(block.basefee, ramp.fuel);
        auctions[aid].valid = uint(Valid.VALID);
    }

    function glug(uint256 aid) _lock_ _flog_ payable external {
        Auction storage auction = auctions[aid];

        if (uint(Valid.VALID) != auction.valid) revert ErrEmptyAid();

        uint price = deal(aid, block.timestamp);

        (uint makers, uint takers) = clip(auction.ham, auction.wam, price);
        uint rest  = auction.ham - takers;

        address vip = auction.vip;
        if (!Gem(auction.wag).transferFrom(msg.sender, auction.vow, makers)) revert ErrTransfer();
        if (ramps[vip][auction.hag].tiny > FLIP_DUST) {
            // hag preloaded, use transfer and send back what's left
            if (!Gem(auction.hag).transfer(msg.sender, takers)) revert ErrTransfer();
            if (!Gem(auction.hag).transfer(vip, rest)) revert ErrTransfer();
        } else {
            // hag still in vip, use transferFrom, may need to hook.grant(hag) for this to work
            if (!Gem(auction.hag).transferFrom(vip, msg.sender, takers)) revert ErrTransfer();
        }

        Flowback(vip).flowback(aid, rest);

        // pay whomever paid the gas to create the auction
        if (msg.value < auction.gim) revert ErrTransfer();
        auction.gir.send(auction.gim);

        auctions[aid].valid = uint(Valid.INVALID);
        aids.push(aid);
    }

    // makers -- amount bidder gives to system
    // takers -- amount system gives to bidder
    function clip(uint ham, uint wam, uint price) public pure returns (uint makers, uint takers) {
        takers = ham;
        makers = rmul(takers, price);
        if (wam < makers) {
            // ham at price is worth more than wam, lower makers so taker buys ~ham
            takers = rmul(takers, rdiv(wam, makers));
            makers = wam;
        }
    }

    // auction's asking price at `time`
    function deal(uint aid, uint time) public view returns (uint) {
        Auction storage auction = auctions[aid];
        uint fade = ramps[auction.vip][auction.hag].fade;
        // fade < RAY, so price decreases with time
        return grow(auction.ask, fade, time - auction.gun);
    }

    function curb(address gem, bytes32 key, uint val) _flog_ external {
        Ramp storage ramp = ramps[msg.sender][gem];
        if (key == 'feed') {
            ramp.feed = address(uint160(val));
        } else if (key == 'fsrc') {
            ramp.fsrc = address(uint160(val));
        } else if (key == 'ftag') {
            ramp.ftag = bytes32(val);
        } else if (key == 'fade') {
            if (val > RAY) revert ErrHighStep();
            ramp.fade = val;
        } else if (key == 'tiny') {
            ramp.tiny = val;
        } else if (key == 'fuel') {
            ramp.fuel = val;
        } else if (key == 'gain') {
            ramp.gain = val;
        } else { revert ErrCurbKey(); }
    }

}
