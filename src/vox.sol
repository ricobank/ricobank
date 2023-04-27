// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

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

pragma solidity 0.8.19;

import { Math } from './mixin/math.sol';
import { Flog } from './mixin/flog.sol';

import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';

import { Vat } from './vat.sol';

// price rate controller
// ensures that market price (mar) roughly tracks par
// note that price rate (way) can be less than 1
// this is how the system achieves negative effective borrowing rates
// if quantity rate is 1%/yr (fee > RAY) but price rate is -2%/yr (way < RAY)
// borrowers are rewarded about 1%/yr for borrowing and shorting rico
contract Vox is Math, Ward, Flog {
    error ErrWrongKey();

    uint256 public immutable amp;

    Vat      public vat;
    Feedbase public fb;

    address public tip; // feedbase `src` address
    bytes32 public tag; // feedbase `tag` bytes32

    uint256 public way;  // [ray] System Rate (SP growth rate)
    uint256 public how;  // [ray] sensitivity paramater
    uint256 public tau;  // [sec] last poke
    uint256 public cap;  // [ray] `way` bound

    constructor(uint256 _amp) {
        amp = _amp;
        how = 1000000115170000000000000000;
        cap = 1000000022000000000000000000;
        tau = block.timestamp;
        way = RAY;
    }

    function poke() _flog_ external {
        if (tau == block.timestamp) { return; }
        uint256 dt = block.timestamp - tau;
        tau = block.timestamp;

        // use previous `way` to grow `par` to keep par updates predictable
        uint256 par = grow(vat.par(), way, dt);
        vat.prod(par);

        (bytes32 mar_, uint256 ttl) = fb.pull(tip, tag);
        uint256 mar = rmul(uint256(mar_), amp);
        if (block.timestamp > ttl) { return; }

        // raise the price rate (way) when mar < par, lower when mar > par
        // this is how mar tracks par
        if (mar < par) {
            way = min(cap, grow(way, how, dt));
        } else if (mar > par) {
            way = max(rinv(cap), grow(way, rinv(how), dt));
        }
    }

    function link(bytes32 key, address val) _ward_ _flog_ external
    {
             if (key == "vat") { vat = Vat(val); }
        else if (key == "fb") { fb = Feedbase(val); }
        else if (key == "tip") { tip = val; }
        else revert ErrWrongKey();
    }

    function file(bytes32 key, bytes32 val) _ward_ _flog_ external
    {
             if (key == "tag") { tag = val; }
        else if (key == "how") { how = uint256(val); }
        else if (key == "cap") { cap = uint256(val); }
        else if (key == "way") { way = uint256(val); }
        else revert ErrWrongKey();
    }

}
