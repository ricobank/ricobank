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
import { Bank } from './bank.sol';

// price rate controller
// ensures that market price (mar) roughly tracks par
// note that price rate (way) can be less than 1
// this is how the system achieves negative effective borrowing rates
// if quantity rate is 1%/yr (fee > RAY) but price rate is -2%/yr (way < RAY)
// borrowers are rewarded about 1%/yr for borrowing and shorting rico
contract Vox is Bank {
    function way() external view returns (uint) {return getVoxStorage().way;}
    function how() external view returns (uint) {return getVoxStorage().how;}
    function cap() external view returns (uint) {return getVoxStorage().cap;}
    function tip() external view returns (address) {return getVoxStorage().tip;}
    function tag() external view returns (bytes32) {return getVoxStorage().tag;}
    function amp() external view returns (uint) {return AMP;}

    uint256 immutable AMP;

    constructor(uint256 _AMP) { AMP = _AMP; }

    function poke() _flog_ external {
        VoxStorage storage voxS = getVoxStorage();
        VatStorage storage vatS = getVatStorage();
        if (voxS.tau == block.timestamp) { return; }
        uint256 dt = block.timestamp - voxS.tau;
        voxS.tau = block.timestamp;

        // use previous `way` to grow `par` to keep par updates predictable
        uint256 par = grow(vatS.par, voxS.way, dt);
        vatS.par = par;

        (bytes32 mar_, uint256 ttl) = getBankStorage().fb.pull(voxS.tip, voxS.tag);
        uint256 mar = rmul(uint256(mar_), AMP);
        if (block.timestamp > ttl) { return; }

        // raise the price rate (way) when mar < par, lower when mar > par
        // this is how mar tracks par
        if (mar < par) {
            voxS.way = min(voxS.cap, grow(voxS.way, voxS.how, dt));
        } else if (mar > par) {
            voxS.way = max(rinv(voxS.cap), grow(voxS.way, rinv(voxS.how), dt));
        }
    }
}
