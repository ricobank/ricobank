// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;

import { Vat }  from "./vat.sol";
import { Vox }  from "./vox.sol";
import { Bank, Gem } from "./bank.sol";

// total system profit balancing mechanism
// triggers surplus (flap) auctions
contract Vow is Bank {
    function RISK() external view returns (Gem) {return getVowStorage().risk;}
    function loot() external view returns (uint) { return getVowStorage().loot; }
    function ramp() external view returns (Ramp memory) { return getVowStorage().ramp; }
    function dam() external view returns (uint) { return getVowStorage().dam; }
    function pex() external pure returns (uint) { return _pex; }
    uint constant public _pex = RAY * WAD;

    error ErrReflop();

    function keep(bytes32[] calldata ilks) external payable _flog_ _lock_ {
        VowStorage storage  vowS  = getVowStorage();
        VatStorage storage  vatS  = getVatStorage();
        BankStorage storage bankS = getBankStorage();

        for (uint256 i = 0; i < ilks.length;) {
            Vat(address(this)).drip(ilks[i]);
            unchecked {++i;}
        }

        Gem rico = bankS.rico;
        Gem risk = vowS.risk;

        // use equal scales for sin and joy
        uint joy   = vatS.joy;
        uint sin   = vatS.sin / RAY;
        // in case of deficit max price should always lead to decrease in way
        uint price = type(uint256).max;
        uint dt = block.timestamp - vowS.ramp.bel;

        if (joy > sin) {

            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) {
                // gas - don't zero sin
                joy = _heal(sin - 1);
            }

            // price decreases with time
            price = grow(_pex, vowS.dam, dt);

            // buy-and-burn risk with remaining (`flap`) rico
            uint flap  = rmul(joy - 1, vowS.ramp.wel);
            joy       -= flap;
            vatS.joy   = joy;
            emit NewPalm0("joy", bytes32(joy));

            uint sell  = rmul(flap, vowS.loot);
            uint earn  = rmul(sell, price);

            // swap rico for RISK, pay protocol fee
            Gem(risk).burn(msg.sender, earn);
            Gem(rico).mint(msg.sender, sell);
            if (sell < flap) Gem(rico).mint(owner(), flap - sell);
        }
        vowS.ramp.bel = block.timestamp;
        emit NewPalm0("bel", bytes32(block.timestamp));
        Vox(address(this)).poke(price, dt);
    }

    function _heal(uint wad) internal returns (uint joy) {
        VatStorage storage vs = getVatStorage();

        vs.sin  = vs.sin  - (wad * RAY);
        emit NewPalm0("sin", bytes32(vs.sin));

        vs.joy  = (joy = vs.joy - wad);
        emit NewPalm0("joy", bytes32(joy));

        vs.debt = vs.debt - wad;
        emit NewPalm0("debt", bytes32(vs.debt));
    }

}
