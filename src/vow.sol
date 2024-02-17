// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.19;

import { Vat }  from "./vat.sol";
import { Bank, Gem } from "./bank.sol";
import 'forge-std/Test.sol';

// total system profit/loss balancing mechanism
// triggers surplus (flap), and deficit (flop) auctions
contract Vow is Bank {
    function RISK() external view returns (Gem) {return getVowStorage().risk;}
    function ramp() external view returns (Ramp memory) {
        return getVowStorage().ramp;
    }
    function loot() external view returns (uint) { return getVowStorage().loot; }
    function dam() external view returns (uint) { return getVowStorage().dam; }
    function dom() external view returns (uint) { return getVowStorage().dom; }
    function TUG_MAX() external pure returns (uint) { return _TUG_MAX; }
    uint constant public _TUG_MAX = RAY * WAD;

    error ErrReflop();
    error ErrOutDated();

    function keep(bytes32[] calldata ilks) external payable _flog_ {
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
        uint joy = vatS.joy;
        uint sin = vatS.sin / RAY;

        if (joy > sin) {

            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) {
                // gas - don't zero sin
                joy = _heal(sin - 1);
            }

            // price decreases with time
            uint price = grow(
                _TUG_MAX, vowS.dam, block.timestamp - vowS.ramp.bel
            );

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

            vowS.ramp.bel = block.timestamp;
            emit NewPalm0("bel", bytes32(block.timestamp));

        } else if (sin > joy) {

            // mint-and-sell risk to cover `under`
            uint under = sin - joy;

            // pay down as much sin as possible
            if (joy > 1) {
                // gas - don't zero joy
                joy = _heal(joy - 1);
            }

            // price decreases with time
            uint bel   = vowS.ramp.bel;
            uint price = grow(_TUG_MAX, vowS.dom, block.timestamp - bel);

            // rate-limit flop
            uint elapsed = min(block.timestamp - bel, vowS.ramp.cel);
            uint flop    = elapsed * rmul(vowS.ramp.rel, risk.totalSupply());
            if (0 == flop) revert ErrReflop();

            // swap RISK for rico to cover sin
            uint earn = rmul(flop, price);
            bel       = block.timestamp;
            if (earn > under) {
                // always advances >= 1s from max(vowS.bel, timestamp - cel)
                bel  -= wmul(elapsed, WAD - wdiv(under, earn));
                flop  = (flop * under) / earn;
                earn  = under;
            }

            // update last flop stamp
            vowS.ramp.bel = bel;
            emit NewPalm0("bel", bytes32(bel));

            Gem(rico).burn(msg.sender, earn);
            Gem(risk).mint(msg.sender, flop);

            // new joy will heal some sin in next flop
            joy     += earn;
            vatS.joy = joy;
            emit NewPalm0("joy", bytes32(joy));

        }

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
