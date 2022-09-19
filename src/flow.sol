// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import './mixin/math.sol';
import "./swap.sol";
import { Flow, Flowback, GemLike, VowLike } from './abi.sol';

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
        address vow;
        address hag; // token in (or 0 if deficit auction)
        uint256 ham; // [wad] amount in
        address wag; // token out
        uint256 wam; // amount out needed to finish the auction early
    }

    mapping (address => mapping (address => Ramp)) public ramps;  // client -> gem -> ramp
    mapping (bytes32 => Auction) public auctions;
    uint256 public count;
    address public RISK;

    function flow(address hag, uint ham, address wag, uint wam) external returns (bytes32 aid) {
        address realhag = hag;
        if (address(0) == hag) {
            realhag = VowLike(msg.sender).RISK();
        }
        GemLike(realhag).transferFrom(msg.sender, address(this), ham);
        aid = _next();
        auctions[aid].vow = msg.sender;
        auctions[aid].hag = hag;
        auctions[aid].ham = ham;
        auctions[aid].wag = wag;
        auctions[aid].wam = wam;
    }

    function glug(bytes32 aid) external {
        Auction storage auction = auctions[aid];
        (bool last, uint hunk, uint bel) = _clip(auction.vow, auction.hag, auction.ham);
        ramps[auction.vow][auction.hag].bel = bel;
        uint cost = SWAP_ERR;
        uint gain;

        address hag = address(0) == auction.hag ? VowLike(auction.vow).RISK() : auction.hag;
        if (auction.wam != type(uint256).max) {
            cost = _swap(hag, auction.wag, auction.vow, SwapKind.GIVEN_OUT, auction.wam, hunk);
        }

        if (cost != SWAP_ERR) {
            gain = auction.wam;
            last = true;
        } else {
            gain = _swap(hag, auction.wag, auction.vow, SwapKind.GIVEN_IN, hunk, 0);
            require(gain != SWAP_ERR, 'Flow/swap');
            cost = hunk;
        }
        uint rest = auction.ham - cost;

        if (last) {
            GemLike(hag).transfer(auction.vow, rest);
            Flowback(auction.vow).flowback(aid, hag, rest);
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

    function _clip(address back, address _gem, uint top) internal view returns (bool, uint, uint) {
        Ramp storage ramp = ramps[back][_gem];
        require(address(0) != back, 'Flow/vow');
        address gem = address(0) == _gem ? VowLike(back).RISK() : _gem;
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

    // TODO ward
    function approve_gem(address gem) external {
        GemLike(gem).approve(address(bvault), type(uint256).max);
    }

    // Flow handles all flow rate limits for vow or other clients, based on flopback requesting amount
    // TODO ward
    function curb(address gem, bytes32 key, uint val) external {
               if (key == "vel") { ramps[msg.sender][gem].vel = val;
        } else if (key == "rel") { ramps[msg.sender][gem].rel = val;
        } else if (key == "bel") { ramps[msg.sender][gem].bel = val;
        } else if (key == "cel") { ramps[msg.sender][gem].cel = val;
        } else if (key == "del") { ramps[msg.sender][gem].del = val;
        } else { revert("ERR_CURB_KEY"); }
    }
}
