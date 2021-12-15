// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import './mixin/math.sol';

import './swap.sol';

interface GemLike {
    function mint(address usr, uint amt) external;
    function burn(address usr, uint amt) external;
    function approve(address usr, uint amt) external;
    function balanceOf(address usr) external returns (uint);
    function transfer(address usr, uint amt) external;
    function totalSupply() external returns(uint);
}

interface Flipper {
    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external;
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

abstract contract Clipper {
    struct Ramp {
        uint256 vel;  // Stream speed wei/sec       [wad]
        uint256 rel;  // Speed relative to supply   [wad]
        uint256 bel;  // Sec allowance last emptied [sec]
        uint256 cel;  // Sec to recharge            [sec]
    }
}

contract RicoFlowerV1 is Math, BalancerSwapper
                       , Flipper, Flapper, Flopper, Clipper
{
    mapping(address=>Ramp) public ramps;
    address public RICO;
    address public RISK;
    address public vow;

    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external {
        trade(gem, RICO);
    }

    function flap(uint surplus) external {
        trade(RICO, RISK);
    }

    function flop(uint debt) external {
        _swap(RISK, address(this), debt, RICO, vow);
    }

    function trade(address tokIn, address tokOut) internal {
        Ramp storage ramp = ramps[tokIn];
        uint bal = GemLike(tokIn).balanceOf(address(this));
        uint tot = GemLike(tokIn).totalSupply();
        uint lot = clip(ramp, bal, tot);
        _swap(tokIn, address(this), lot, tokOut, vow);
    }

    function clip(Ramp storage ramp, uint due, uint supply) internal returns (uint lot) {
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

    function file(bytes32 key, address val) external {
        ward();
               if (key == "rico")  { RICO  = val;
        } else if (key == "risk")  { RISK  = val;
        } else if (key == "vow")   { vow   = val;
        } else { revert("ERR_FILE_KEY"); }
    }
    function file_ramp(address gem, Ramp memory ramp) external {
        ward();
        ramps[gem] = ramp;
    }
}
