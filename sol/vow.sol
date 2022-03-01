// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.10;

import 'hardhat/console.sol';

import './mixin/math.sol';
import './mixin/ward.sol';

import './flow.sol';

import { GemLike, PlugLike, PortLike, VatLike } from './abi.sol';

contract Vow is Math, Ward {
    struct Ramp {
        uint256 vel;  // [wad] Stream speed wei/sec
        uint256 rel;  // [wad] Speed relative to supply
        uint256 bel;  // [sec] Sec allowance last emptied
        uint256 cel;  // [sec] Sec to recharge
    }

    VatLike  public vat;
    PlugLike public plug;
    PortLike public port;

    GemLike public RICO;
    GemLike public RISK;

    Flopper public flopper;
    Flapper public flapper;
    mapping(bytes32=>address) public flippers;

    Ramp    public drop; // Recharge flops.
    uint256 public bar;  // [rad] Surplus buffer

    function bail(bytes32 ilk, address[] calldata gems, address urn) external {
        require( !vat.safe(ilk, urn), 'ERR_SAFE' );
        address flipper = flippers[ilk];
        (uint ink, uint art) = vat.urns(ilk, urn);
        uint bill = vat.grab(ilk, urn, address(this), address(this), -int(ink), -int(art));
        for(uint i = 0; i < gems.length && ink > 0; i++) {
            uint take = min(ink, GemLike(gems[i]).balanceOf(address(plug)));
            ink -= take;
            plug.exit(address(vat), ilk, gems[i], flipper, take);
            Flipper(flipper).flip(ilk, urn, gems[i], take, bill);
        }
        require(ink == 0, 'MISSING_GEM');
    }

    function plop(bytes32 ilk, address gem, address urn, uint amt)
      _ward_ external
    {
        plug.join(address(vat), ilk, gem, urn, amt);
    }

    function keep() external {
        uint rico = RICO.balanceOf(address(this));
        uint risk = RISK.balanceOf(address(this));

        vat.rake();
        RISK.burn(address(this), risk);
        port.join(address(vat), address(RICO), address(this), rico);

        uint sin = vat.sin(address(this));
        uint joy = vat.joy(address(this));

        if (joy > sin + bar) {
            vat.heal(sin);
            uint gain = (joy - sin - bar) / RAY;
            port.exit(address(vat), address(RICO), address(flapper), gain);
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
        vat.trust(address(port), true);
    }

    function reapprove_gem(address gem) external {
        GemLike(gem).approve(address(plug), type(uint256).max);
    }

    function file(bytes32 key, uint val)
      _ward_ external
    {
               if (key == "bar") { bar = val;
        } else if (key == "vel") { drop.vel = val;
        } else if (key == "rel") { drop.rel = val;
        } else if (key == "bel") { drop.bel = val;
        } else if (key == "cel") { drop.cel = val;
        } else { revert("ERR_FILE_KEY"); }
    }

    function link(bytes32 key, address val)
      _ward_ external
    {
               if (key == "flapper") { flapper = Flapper(val);
        } else if (key == "flopper") { flopper = Flopper(val);
        } else if (key == "rico") { RICO = GemLike(val);
        } else if (key == "risk") { RISK = GemLike(val);
        } else if (key == "vat") { vat = VatLike(val);
        } else if (key == "plug") { plug = PlugLike(val);
        } else if (key == "port") { port = PortLike(val);
        } else { revert("ERR_LINK_KEY"); }
    }

    function lilk(bytes32 ilk, bytes32 key, address val)
      _ward_ external
    {
        if (key == "flipper") { flippers[ilk] = val;
        } else { revert("ERR_LILK_KEY"); }
    }
}
