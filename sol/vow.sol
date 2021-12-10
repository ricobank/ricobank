// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import './mixin/math.sol';
import './mixin/ward.sol';

import './flow.sol';

interface VatLike {
    function joy(address) external returns (uint);
    function sin(address) external returns (uint);
    function heal(uint amt) external;
    function drip(bytes32 ilk) external;
    function hope(address) external;
    function rake() external returns (uint);
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,address,address,int,int) external returns (uint);
}

interface VaultLike {
    function gem_join(address,bytes32,address,uint) external returns (address);
    function gem_exit(address,bytes32,address,uint) external returns (address);
    function joy_exit(address vat, address joy, address usr, uint amt) external;
    function joy_join(address vat, address joy, address usr, uint amt) external;
}

contract Vow is Math, Ward, Clipper {
    VatLike public vat;
    VaultLike public vault;
    GemLike public RICO;
    GemLike public RISK;
    Flopper public flopper;
    Flapper public flapper;
    Ramp public drop;  // Recharge flops.
    mapping(bytes32=>address) public flippers;
    uint256 public bar;  // Surplus buffer          [rad]

    function bail(bytes32 ilk, address urn) external {
        require( !vat.safe(ilk, urn), 'ERR_SAFE' );
        address flipper = flippers[ilk];
        (uint ink, uint art) = vat.urns(ilk, urn);
        uint bill = vat.grab(ilk, urn, address(this), address(this), -int(ink), -int(art));
        address gem = vault.gem_exit(address(vat), ilk, flipper, ink);
        Flipper(flipper).flip(ilk, urn, gem, ink, bill);
    }

    function plop(bytes32 ilk, address urn, address gem, uint amt) external {
        ward();
        vault.gem_join(address(vat), ilk, urn, amt);
    }

    function keep() external {
        uint rico = RICO.balanceOf(address(this));
        uint risk = RISK.balanceOf(address(this));

        vat.rake();
        RISK.burn(address(this), risk);
        vault.joy_join(address(vat), address(RICO), address(this), rico);

        uint sin = vat.sin(address(this));
        uint joy = vat.joy(address(this));

        if (joy > sin + bar) {
            vat.heal(sin);
            uint gain = (joy - sin - bar) / RAY;
            vault.joy_exit(address(vat), address(RICO), address(flapper), gain);
            flapper.flap(0);
        } else if (sin > joy) {
            vat.heal(joy);
            flopper.flop(yank());
        } else if (sin != 0) {
            vat.heal(min(joy, sin));
        } else {} // joy == sin == 0
    }

    function yank() internal returns (uint lot) {
        uint slope = min(drop.vel, wmul(drop.rel, RISK.totalSupply()));
        lot = slope * min(drop.cel, block.timestamp - drop.bel);
        RISK.mint(address(flopper), lot);
        drop.bel = block.timestamp;
    }

    function reapprove() external {
        vat.hope(address(vault));
        RICO.approve(address(vault), type(uint256).max);
    }

    function reapprove_gem(address gem) external {
        GemLike(gem).approve(address(vault), type(uint256).max);
    }

    function file(bytes32 key, address val) external {
        ward();
               if (key == "flapper") { flapper = Flapper(val);
        } else if (key == "flopper") { flopper = Flopper(val);
        } else if (key == "rico") { RICO = GemLike(val);
        } else if (key == "risk") { RISK = GemLike(val);
        } else if (key == "vat") { vat = VatLike(val);
        } else if (key == "vault") { vault = VaultLike(val);
        } else { revert("ERR_FILE_KEY"); }
    }
    function file(bytes32 key, uint val) external {
        ward();
        if (key == "bar") { bar = val;
        } else { revert("ERR_FILE_KEY"); }
    }
    function filk(bytes32 ilk, bytes32 key, address val) external {
        ward();
        if (key == "flipper") { flippers[ilk] = val;
        } else { revert("ERR_FILK_KEY"); }
    }
    function file_drop(Ramp memory ramp) external {
        ward();
        drop = ramp;
    }
}
