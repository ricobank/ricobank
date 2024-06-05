// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;

import { Vat }  from "./vat.sol";
import { Vox }  from "./vox.sol";
import { Bank, Gem } from "./bank.sol";

// total system profit balancing mechanism
// triggers surplus (flap) auctions
contract Vow is Bank {
    function bel() external view returns (uint) { return getVowStorage().bel; }
    function gif() external view returns (uint) { return getVowStorage().gif; }
    function phi() external view returns (uint) { return getVowStorage().phi; }

    uint256 immutable public pex; // [ray] start price
    uint256 immutable public wel; // [ray] fraction of joy/flap
    uint256 immutable public dam; // [ray] per-second flap discount
    uint256 immutable public mop; // [ray] per-second gif decay
    uint256 immutable public lax; // [ray] mint-rate shift up (fraction of totalSupply)

    uint constant public LAX_MAX = 145929047899781146998; // ~100x/yr

    struct VowParams {
        uint256 wel;
        uint256 dam;
        uint256 pex;
        uint256 mop;
        uint256 lax;
    }

    constructor(BankParams memory bp, VowParams memory vp) Bank(bp) {
        (wel, dam, pex, mop, lax) = (vp.wel, vp.dam, vp.pex, vp.mop, vp.lax);

        must(wel, 0, RAY);
        must(dam, 0, RAY);
        must(pex, RAY, RAY * WAD);
        must(mop, 0, RAY);
        must(lax, 0, LAX_MAX);
    }

    error ErrReflop();

    function keep(bytes32[] calldata ilks) external payable _flog_ {
        VowStorage storage  vowS  = getVowStorage();
        VatStorage storage  vatS  = getVatStorage();

        for (uint256 i = 0; i < ilks.length;) {
            Vat(address(this)).drip(ilks[i]);
            unchecked {++i;}
        }

        // use equal scales for sin and joy
        uint joy   = vatS.joy;
        uint sin   = vatS.sin / RAY;
        // in case of deficit max price should always lead to decrease in way
        uint price = type(uint256).max;
        uint dt = block.timestamp - vowS.bel;

        if (joy > sin) {

            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) {
                // gas - don't zero sin
                joy = _heal(sin - 1);
            }

            // price decreases with time
            price = grow(pex, dam, dt);

            // buy-and-burn risk with remaining (`flap`) rico
            uint flap  = rmul(joy - 1, wel);
            uint earn  = rmul(flap, price);
            joy       -= flap;
            vatS.joy   = joy;
            emit NewPalm0("joy", bytes32(joy));

            // swap rico for RISK, pay protocol fee
            Gem(risk).burn(msg.sender, earn);
            Gem(rico).mint(msg.sender, flap);
        }
        vowS.bel = block.timestamp;
        emit NewPalm0("bel", bytes32(block.timestamp));
        Vox(address(this)).poke(price, dt);
    }

    function _heal(uint wad) internal returns (uint joy) {
        VatStorage storage vs = getVatStorage();

        vs.sin  = vs.sin  - (wad * RAY);
        emit NewPalm0("sin", bytes32(vs.sin));

        vs.joy  = (joy = vs.joy - wad);
        emit NewPalm0("joy", bytes32(joy));
    }

    // give msg.sender some RISK
    function mine() external {
        VowStorage storage vs = getVowStorage();
        uint elapsed = block.timestamp - vs.phi;

        vs.gif = grow(vs.gif, mop, elapsed);
        emit NewPalm0("gif", bytes32(vs.gif));

        vs.phi = block.timestamp;
        emit NewPalm0("phi", bytes32(block.timestamp));

        uint flate = vs.gif + rmul(risk.totalSupply(), lax);
        risk.mint(msg.sender, flate * elapsed);
    }

}
