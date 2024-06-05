// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Rico CDP database

// Copyright (C) 2021-2024 halys
// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.25;

import { Bank, Gem } from "./bank.sol";

contract Vat is Bank {
    function ilks(bytes32 i) external view returns (Ilk memory) {
        return getVatStorage().ilks[i];
    }
    function urns(bytes32 i, address u) external view returns (Urn memory) {
        return getVatStorage().urns[i][u];
    }
    function joy()  external view returns (uint) {return getVatStorage().joy;}
    function sin()  external view returns (uint) {return getVatStorage().sin;}
    function rest() external view returns (uint) {return getVatStorage().rest;}
    function par()  external view returns (uint) {return getVatStorage().par;}

    uint256 constant public FEE_MAX = 1000000072964521287979890107; // ~10x/yr

    uint256 constant SAFE = RAY;

    error ErrDebtCeil();
    error ErrIlkInit();
    error ErrMultiIlk();
    error ErrNotSafe();
    error ErrSafeBail();
    error ErrUrnDust();
    error ErrWrongUrn();

    constructor(BankParams memory bp) Bank(bp) {}

    function init(bytes32 ilk)
      external payable onlyOwner _flog_
    {
        VatStorage storage vs = getVatStorage();
        if (vs.ilks[ilk].rack != 0) revert ErrMultiIlk();
        vs.ilks[ilk] = Ilk({
            tart: 0,
            rack: RAY,
            line: 0,
            dust: 0,
            fee : RAY,
            rho : block.timestamp,
            chop: 0,
            liqr: RAY,
            plot: Plx({
                pep: 0,
                pop: 0,
                pup: 0
            })
        });
        emit NewPalm1("tart", ilk, bytes32(uint(0)));
        emit NewPalm1("rack", ilk, bytes32(RAY));
        emit NewPalm1("line", ilk, bytes32(uint(0)));
        emit NewPalm1("dust", ilk, bytes32(uint(0)));
        emit NewPalm1("fee",  ilk, bytes32(RAY));
        emit NewPalm1("rho",  ilk, bytes32(block.timestamp));
        emit NewPalm1("chop", ilk, bytes32(uint(0)));
        emit NewPalm1("liqr", ilk, bytes32(RAY));
        emit NewPalm1("pep",  ilk, bytes32(0));
        emit NewPalm1("pop",  ilk, bytes32(0));
        emit NewPalm1("pup",  ilk, bytes32(0));
    }

    function safe(bytes32 i, address u)
      public view returns (uint deal, uint tot)
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        Urn storage urn = vs.urns[i][u];
        uint ink = urn.ink;

        // par acts as a multiplier for collateral requirements
        // par increase has same effect on cut as fee accumulation through rack
        // par decrease acts like a negative fee
        uint tab = urn.art * rmul(vs.par, ilk.rack);
        uint cut = rdiv(ink, ilk.liqr) * RAY;

        // min() used to prevent truncation hiding unsafe
        deal = tab > cut ? min(cut / (tab / RAY), SAFE - 1) : SAFE;
        tot  = ink * RAY;
    }

    // modify CDP
    function frob(bytes32 i, address u, int dink, int dart)
      external payable _flog_
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        Urn storage urn = vs.urns[i][u];

        uint rack = _drip(i);

        // modify normalized debt
        uint256 art = add(urn.art, dart);
        urn.art     = art;
        emit NewPalm2("art", i, bytes32(bytes20(u)), bytes32(art));

        // keep track of total so it denorm doesn't exceed line
        ilk.tart    = add(ilk.tart, dart);
        emit NewPalm1("tart", i, bytes32(ilk.tart));

        uint _rest;
        {
            // rico mint/burn amount increases with rack
            int dtab = mul(rack, dart);
            if (dtab > 0) {
                // borrow
                // dtab is a rad
                uint wad = uint(dtab) / RAY;

                // remainder is a ray
                _rest = vs.rest += uint(dtab) % RAY;
                emit NewPalm0("rest", bytes32(_rest));

                rico.mint(msg.sender, wad);
            } else if (dtab < 0) {
                // paydown
                // dtab is a rad, so burn one extra to round in system's favor
                uint wad = (uint(-dtab) / RAY) + 1;
                // accrue excess from rounding to rest
                _rest = vs.rest += add(wad * RAY, dtab);
                emit NewPalm0("rest", bytes32(_rest));

                rico.burn(msg.sender, wad);
            }
        }

        // update balance before transferring tokens
        uint ink = add(urn.ink, dink);
        urn.ink = ink;
        emit NewPalm2("ink", i, bytes32(bytes20(u)), bytes32(ink));

        if (dink > 0) {
            // pull tokens from sender
            risk.transferFrom(msg.sender, address(this), uint(dink));
        } else if (dink < 0) {
            // return tokens to urn holder
            risk.transfer(u, uint(-dink));
        }

        // urn is safer, or it is safe
        if (dink < 0 || dart > 0) {
            (uint deal,) = safe(i, u);
            if (u != msg.sender)   revert ErrWrongUrn();
            if (deal < SAFE) revert ErrNotSafe();
        }

        // urn has no debt, or a non-dusty ink amount
        if (art != 0 && urn.ink < rmul(risk.totalSupply(), ilk.dust)) {
            revert ErrUrnDust();
        }

        // either debt has decreased, or debt ceiling is not exceeded
        if (dart > 0) {
            if (ilk.tart * rack > ilk.line) revert ErrDebtCeil();
        }
    }

    // liquidate CDP
    function bail(bytes32 i, address u)
      external payable _flog_ returns (uint sell)
    {
        uint rack = _drip(i);
        uint deal; uint tot; uint dtab;
        {
            (deal, tot) = safe(i, u);
            if (deal == SAFE) revert ErrSafeBail();
        }
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        Urn storage urn = vs.urns[i][u];

        {
            uint art = urn.art;
            urn.art = 0;
            emit NewPalm2("art", i, bytes32(bytes20(u)), bytes32(uint(0)));

            dtab = art * rack;
            ilk.tart -= art;
        }

        emit NewPalm1("tart", i, bytes32(ilk.tart));

        // record the bad debt for vow to heal
        vs.sin += dtab;
        emit NewPalm0("sin", bytes32(vs.sin));

        // ink auction
        uint mash = rmash(deal, ilk.plot.pep, ilk.plot.pop, ilk.plot.pup);
        uint earn = rmul(tot / RAY, mash);

        {
            // bill is the debt to attempt to cover when auctioning ink
            uint bill = rmul(ilk.chop, dtab / RAY);
            // clamp `sell` so bank only gets enough to underwrite urn.
            if (earn > bill) {
                sell = (urn.ink * bill) / earn;
                earn = bill;
            } else {
                sell = urn.ink;
            }
        }

        vsync(i, earn, dtab / RAY);

        // update collateral balance
        unchecked {
            uint _ink = urn.ink -= sell;
            emit NewPalm2("ink", i, bytes32(bytes20(u)), bytes32(_ink));
        }

        // trade collateral with keeper for rico
        rico.burn(msg.sender, earn);
        risk.transfer(msg.sender, sell);
    }

    // Update joy and possibly line. Workaround for stack too deep
    function vsync(bytes32 i, uint earn, uint owed) internal {
        VatStorage storage vs = getVatStorage();

        if (earn < owed) {
            // drop line value for this ilk as precaution
            uint prev = vs.ilks[i].line;
            uint loss = RAY * (owed - earn);
            uint next = loss > prev ? 0 : prev - loss;
            vs.ilks[i].line = next;
            emit NewPalm1("line", i, bytes32(next));
        }

        // update joy to help cancel out sin
        uint mood = vs.joy + earn;
        vs.joy = mood;
        emit NewPalm0("joy", bytes32(mood));
    }

    function drip(bytes32 i) external payable _flog_ { _drip(i); }

    // drip without flog
    function _drip(bytes32 i) internal returns (uint rack) {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk       = vs.ilks[i];
        // multiply rack by fee every second
        uint prev = ilk.rack;
        if (prev == 0) revert ErrIlkInit();
 
        if (block.timestamp == ilk.rho) {
            return ilk.rack;
        }

        // multiply rack by fee every second
        rack = grow(prev, ilk.fee, block.timestamp - ilk.rho);

        // difference between current and previous rack determines interest
        uint256 delt = rack - prev;
        uint256 rad  = ilk.tart * delt;
        uint256 all  = vs.rest + rad;

        ilk.rho      = block.timestamp;
        emit NewPalm1("rho", i, bytes32(block.timestamp));

        ilk.rack     = rack;
        emit NewPalm1("rack", i, bytes32(rack));

        // tart * rack is a rad, interest is a wad, rest is the change
        vs.rest      = all % RAY;
        emit NewPalm0("rest", bytes32(vs.rest));

        vs.joy       = vs.joy + (all / RAY);
        emit NewPalm0("joy", bytes32(vs.joy));
    }

    function filk(bytes32 ilk, bytes32 key, bytes32 val)
      external payable onlyOwner _flog_
    {
        uint _val = uint(val);
        VatStorage storage vs = getVatStorage();
        Ilk storage i = vs.ilks[ilk];
               if (key == "line") { i.line = _val;
        } else if (key == "dust") {
            must(_val, 0, RAY);
            i.dust = _val;
        } else if (key == "pep")  { i.plot.pep = _val;
        } else if (key == "pop")  { i.plot.pop = _val;
        } else if (key == "pup")  { i.plot.pup = int(_val);
        } else if (key == "liqr") {
            must(_val, RAY, type(uint).max);
            i.liqr = _val;
        } else if (key == "chop") {
            must(_val, RAY, 10 * RAY);
            i.chop = _val;
        } else if (key == "fee") {
            must(_val, RAY, FEE_MAX);
            _drip(ilk);
            i.fee = _val;
        } else { revert ErrWrongKey(); }
        emit NewPalm1(key, ilk, bytes32(val));
    }

    function get(bytes32 ilk, bytes32 key)
      external view returns (bytes32) {
        VatStorage storage vs = getVatStorage();
        Ilk storage i = vs.ilks[ilk];
               if (key == "liqr") { return bytes32(i.liqr);
        } else if (key == "pep")  { return bytes32(i.plot.pep);
        } else if (key == "pop")  { return bytes32(i.plot.pop);
        } else if (key == "pup")  { return bytes32(uint(i.plot.pup));
        } else { revert ErrWrongKey(); }
    }
}
