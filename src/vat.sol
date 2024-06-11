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
    function urns(address u) external view returns (Urn memory) {
        return getVatStorage().urns[u];
    }
    function joy()  external view returns (uint) {return getVatStorage().joy;}
    function sin()  external view returns (uint) {return getVatStorage().sin;}
    function rest() external view returns (uint) {return getVatStorage().rest;}
    function par()  external view returns (uint) {return getVatStorage().par;}
    function tart() external view returns (uint) {return getVatStorage().tart;}
    function rack() external view returns (uint) {return getVatStorage().rack;}
    function line() external view returns (uint) {return getVatStorage().line;}
    function dust() external view returns (uint) {return getVatStorage().dust;}
    function fee()  external view returns (uint) {return getVatStorage().fee;}
    function rho()  external view returns (uint) {return getVatStorage().rho;}
    function chop() external view returns (uint) {return getVatStorage().chop;}
    function liqr() external view returns (uint) {return getVatStorage().liqr;}
    function plot() external view returns (Plx memory) {return getVatStorage().plot;}

    uint256 constant public FEE_MAX = 1000000072964521287979890107; // ~10x/yr

    uint256 constant SAFE = RAY;

    error ErrDebtCeil();
    error ErrNotSafe();
    error ErrSafeBail();
    error ErrUrnDust();
    error ErrWrongUrn();

    constructor(BankParams memory bp) Bank(bp) {}

    function safe(address u)
      public view returns (uint deal, uint tot)
    {
        VatStorage storage vs = getVatStorage();
        Urn storage urn = vs.urns[u];
        uint ink = urn.ink;

        // par acts as a multiplier for collateral requirements
        // par increase has same effect on cut as fee accumulation through rack
        // par decrease acts like a negative fee
        uint tab = urn.art * rmul(vs.par, vs.rack);
        uint cut = rdiv(ink, vs.liqr) * RAY;

        // min() used to prevent truncation hiding unsafe
        deal = tab > cut ? min(cut / (tab / RAY), SAFE - 1) : SAFE;
        tot  = ink * RAY;
    }

    // modify CDP
    function frob(address u, int dink, int dart)
      external payable _flog_
    {
        VatStorage storage vs = getVatStorage();
        Urn storage urn = vs.urns[u];

        uint _rack = _drip();

        // modify normalized debt
        uint256 art = add(urn.art, dart);
        urn.art     = art;
        emit NewPalm1("art", bytes32(bytes20(u)), bytes32(art));

        // keep track of total so it denorm doesn't exceed line
        vs.tart    = add(vs.tart, dart);
        emit NewPalm0("tart", bytes32(vs.tart));

        uint _rest;
        {
            // rico mint/burn amount increases with rack
            int dtab = mul(_rack, dart);
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
        emit NewPalm1("ink", bytes32(bytes20(u)), bytes32(ink));

        if (dink > 0) {
            // pull tokens from sender
            risk.burn(msg.sender, uint(dink));
        } else if (dink < 0) {
            // return tokens to urn holder
            risk.mint(u, uint(-dink));
        }

        // urn is safer, or it is safe
        if (dink < 0 || dart > 0) {
            (uint deal,) = safe(u);
            if (u != msg.sender)   revert ErrWrongUrn();
            if (deal < SAFE) revert ErrNotSafe();
        }

        // urn has no debt, or a non-dusty ink amount
        if (art != 0 && urn.ink < rmul(getVowStorage().wal, vs.dust)) {
            revert ErrUrnDust();
        }

        // either debt has decreased, or debt ceiling is not exceeded
        if (dart > 0) {
            if (vs.tart * _rack > vs.line) revert ErrDebtCeil();
        }
    }

    // liquidate CDP
    function bail(address u)
      external payable _flog_ returns (uint sell)
    {
        uint _rack = _drip();
        uint deal; uint tot; uint dtab;
        {
            (deal, tot) = safe(u);
            if (deal == SAFE) revert ErrSafeBail();
        }
        VatStorage storage vs = getVatStorage();
        Urn storage urn = vs.urns[u];

        {
            uint art = urn.art;
            urn.art = 0;
            emit NewPalm1("art", bytes32(bytes20(u)), bytes32(uint(0)));

            dtab = art * _rack;
            vs.tart -= art;
        }

        emit NewPalm0("tart", bytes32(vs.tart));

        // record the bad debt for vow to heal
        vs.sin += dtab;
        emit NewPalm0("sin", bytes32(vs.sin));

        // ink auction
        uint mash = rmash(deal, vs.plot.pep, vs.plot.pop, vs.plot.pup);
        uint earn = rmul(tot / RAY, mash);

        {
            // bill is the debt to attempt to cover when auctioning ink
            uint bill = rmul(vs.chop, dtab / RAY);
            // clamp `sell` so bank only gets enough to underwrite urn.
            if (earn > bill) {
                sell = (urn.ink * bill) / earn;
                earn = bill;
            } else {
                sell = urn.ink;
            }
        }

        vsync(earn, dtab / RAY);

        // update collateral balance
        unchecked {
            uint _ink = urn.ink -= sell;
            emit NewPalm1("ink", bytes32(bytes20(u)), bytes32(_ink));
        }

        // trade collateral with keeper for rico
        rico.burn(msg.sender, earn);
        risk.mint(msg.sender, sell);
    }

    // Update joy and possibly line. Workaround for stack too deep
    function vsync(uint earn, uint owed) internal {
        VatStorage storage vs = getVatStorage();

        if (earn < owed) {
            // drop line value as precaution
            uint prev = vs.line;
            uint loss = RAY * (owed - earn);
            uint next = loss > prev ? 0 : prev - loss;
            vs.line = next;
            emit NewPalm0("line", bytes32(next));
        }

        // update joy to help cancel out sin
        uint mood = vs.joy + earn;
        vs.joy = mood;
        emit NewPalm0("joy", bytes32(mood));
    }

    function drip() external payable _flog_ { _drip(); }

    // drip without flog
    function _drip() internal returns (uint _rack) {
        VatStorage storage vs = getVatStorage();
        // multiply rack by fee every second
        uint prev = vs.rack;

        if (block.timestamp == vs.rho) {
            return vs.rack;
        }

        // multiply rack by fee every second
        _rack = grow(prev, vs.fee, block.timestamp - vs.rho);

        // difference between current and previous rack determines interest
        uint256 delt = _rack - prev;
        uint256 rad  = vs.tart * delt;
        uint256 all  = vs.rest + rad;

        vs.rho      = block.timestamp;
        emit NewPalm0("rho", bytes32(block.timestamp));

        vs.rack     = _rack;
        emit NewPalm0("rack", bytes32(_rack));

        // tart * rack is a rad, interest is a wad, rest is the change
        vs.rest      = all % RAY;
        emit NewPalm0("rest", bytes32(vs.rest));

        vs.joy       = vs.joy + (all / RAY);
        emit NewPalm0("joy", bytes32(vs.joy));
    }

    function get(bytes32 key)
      external view returns (bytes32) {
        VatStorage storage vs = getVatStorage();
               if (key == "liqr") { return bytes32(vs.liqr);
        } else if (key == "pep")  { return bytes32(vs.plot.pep);
        } else if (key == "pop")  { return bytes32(vs.plot.pop);
        } else if (key == "pup")  { return bytes32(uint(vs.plot.pup));
        } else { revert ErrWrongKey(); }
    }
}
