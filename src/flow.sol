// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import 'hardhat/console.sol';

import './mixin/math.sol';

import './swap.sol';

import { GemLike, Flipper, Flapper, Flopper } from './abi.sol';

contract RicoFlowerV1 is Math, BalancerSwapper
                       , Flipper, Flapper, Flopper
{
    struct Ramp {
        uint256 vel;  // [wad] Stream speed wei/sec
        uint256 rel;  // [wad] Speed relative to supply
        uint256 bel;  // [sec] Sec allowance last emptied
        uint256 cel;  // [sec] Sec to recharge
    }

    mapping(address=>Ramp) public ramps;
    address public RICO;
    address public RISK;
    address public vow;

    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external {
        _trade(gem, RICO);
    }

    function flap(uint surplus) external {
        _trade(RICO, RISK);
    }

    function flop(uint debt) external {
        _swap(RISK, address(this), debt, RICO, vow);
    }

    function _trade(address tokIn, address tokOut) internal {
        Ramp storage ramp = ramps[tokIn];
        uint bal = GemLike(tokIn).balanceOf(address(this));
        uint tot = GemLike(tokIn).totalSupply();
        uint lot = _clip(ramp, bal, tot);
        _swap(tokIn, address(this), lot, tokOut, vow);
    }

    function _clip(Ramp storage ramp, uint due, uint supply) internal returns (uint lot) {
        uint slope = min(ramp.vel, wmul(ramp.rel, supply));
        uint allowance = slope * min(ramp.cel, block.timestamp - ramp.bel);
        lot = min(allowance, due);
        ramp.bel = block.timestamp - (allowance - lot) / slope;
    }

    function reapprove() external {
        GemLike(RICO).approve(address(bvault), type(uint256).max);
        GemLike(RISK).approve(address(bvault), type(uint256).max);
    }

    function approve_gem(address gem) external {
        GemLike(gem).approve(address(bvault), type(uint256).max);
    }

    function link(bytes32 key, address val)
      _ward_ external
    {
               if (key == "rico")  { RICO  = val;
        } else if (key == "risk")  { RISK  = val;
        } else if (key == "vow")   { vow   = val;
        } else { revert("ERR_LINK_KEY"); }
    }

    function filem(address gem, bytes32 key, uint val)
      _ward_ external
    {
               if (key == "vel") { ramps[gem].vel = val;
        } else if (key == "rel") { ramps[gem].rel = val;
        } else if (key == "bel") { ramps[gem].bel = val;
        } else if (key == "cel") { ramps[gem].cel = val;
        } else { revert("ERR_FILEM_KEY"); }
    }
}
