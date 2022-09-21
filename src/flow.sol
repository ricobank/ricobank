// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import './mixin/math.sol';
import "./swap.sol";
import { Flow, Flowback, GemLike } from './abi.sol';

contract BalancerFlower is Math, BalancerSwapper, Flow
{
    struct Ramp {
        uint256 vel;  // [wad] Stream speed wei/sec
        uint256 rel;  // [wad] Speed relative to supply
        uint256 bel;  // [sec] Started charging
        uint256 cel;  // [sec] Sec to recharge
        uint256 del;  // [wad] Dust threshold
    }

    struct Auction {
        address vow;  // client
        address hag;  // have gem
        uint256 ham;  // have amount
        address wag;  // want gem
        uint256 wam;  // want amount
    }

    mapping (address => mapping (address => Ramp)) public ramps;  // client -> gem -> ramp
    mapping (bytes32 => Auction) public auctions;
    uint256 public count;

    function flow(address hag, uint ham, address wag, uint wam) external returns (bytes32 aid) {
        GemLike(hag).transferFrom(msg.sender, address(this), ham);
        aid = _next();
        auctions[aid].vow = msg.sender;
        auctions[aid].hag = hag;
        auctions[aid].ham = ham;
        auctions[aid].wag = wag;
        auctions[aid].wam = wam;
    }

    function glug(bytes32 aid) external {
        Auction storage auction = auctions[aid];
        address hag = auction.hag;
        address vow = auction.vow;
        (bool last, uint hunk, uint bel) = _clip(vow, hag, auction.ham);
        ramps[vow][hag].bel = bel;
        uint cost = SWAP_ERR;
        uint gain;

        if (auction.wam != type(uint256).max) {
            cost = _swap(hag, auction.wag, vow, SwapKind.GIVEN_OUT, auction.wam, hunk);
        }

        if (cost != SWAP_ERR) {
            gain = auction.wam;
            last = true;
        } else {
            gain = _swap(hag, auction.wag, vow, SwapKind.GIVEN_IN, hunk, 0);
            require(gain != SWAP_ERR, 'Flow/swap');
            cost = hunk;
        }
        uint rest = auction.ham - cost;

        if (last) {
            GemLike(hag).transfer(vow, rest);
            Flowback(vow).flowback(aid, hag, rest);
            delete auctions[aid];
        } else {
            auction.ham = rest;
            if (auction.wam != type(uint256).max){
                auction.wam -= gain;
            }
        }
    }

    function clip(address gem, uint max) external view returns (uint, uint) {
        (, uint res,) = _clip(msg.sender, gem, max);
        return (res, ramps[msg.sender][gem].del);
    }

    function _clip(address back, address gem, uint top) internal view returns (bool, uint, uint) {
        Ramp storage ramp = ramps[back][gem];
        require(address(0) != back, 'Flow/vow');
        uint supply = GemLike(gem).totalSupply();
        uint slope = min(ramp.vel, wmul(ramp.rel, supply));
        uint charge = slope * min(ramp.cel, block.timestamp - ramp.bel);
        uint lot = min(charge, top);
        uint remainder = top - lot;
        uint bel;
        if (0 < remainder && remainder < ramp.del) {
            bel = block.timestamp + remainder / slope;
            lot += remainder;
            remainder = 0;
        } else {
            bel = block.timestamp - (charge - lot) / slope;
        }
        return (remainder == 0, lot, bel);
    }

    function _next() internal returns (bytes32) {
        return bytes32(++count);
    }

    function approve_gem(address gem) external {
        GemLike(gem).approve(address(bvault), type(uint256).max);
    }

    function curb(address gem, bytes32 key, uint val) external {
               if (key == "vel") { ramps[msg.sender][gem].vel = val;
        } else if (key == "rel") { ramps[msg.sender][gem].rel = val;
        } else if (key == "bel") { ramps[msg.sender][gem].bel = val;
        } else if (key == "cel") { ramps[msg.sender][gem].cel = val;
        } else if (key == "del") { ramps[msg.sender][gem].del = val;
        } else { revert("ERR_CURB_KEY"); }
    }
}
