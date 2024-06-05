// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

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

import { Bank } from "./bank.sol";
import { File } from "./file.sol";

// price rate controller
// ensures that market price (mar) roughly tracks par
// note that price rate (way) can be less than 1
// this is how the system achieves negative effective borrowing rates
// if quantity rate is 1%/yr (fee > RAY) but price rate is -2%/yr (way < RAY)
// borrowers are rewarded about 1%/yr for borrowing and shorting rico
contract Vox is Bank {
    function way() external view returns (uint256) {return getVoxStorage().way;}

    struct VoxParams {
        uint256 how;
        uint256 cap;
    }

    uint256 immutable public how;
    uint256 immutable public cap;

    uint constant public CAP_MAX = 1000000072964521287979890107; // ~10x/yr

    constructor(BankParams memory bp, VoxParams memory vp) Bank(bp) {
        how = vp.how;
        cap = vp.cap;

        must(how, RAY, type(uint).max);
        must(cap, RAY, CAP_MAX);
    }

    error ErrSender();

    // poke par and way
    function poke(uint mar, uint dt) external payable _flog_ {
        VatStorage storage vatS = getVatStorage();
        VoxStorage storage voxS = getVoxStorage();

        if (msg.sender != address(this)) revert ErrSender();

        if (dt == 0) return;

        // use previous `way` to grow `par` to keep par updates predictable
        uint par_ = vatS.par;
        uint way_ = voxS.way;
        par_      = grow(par_, way_, dt);
        vatS.par  = par_;
        emit NewPalm0("par", bytes32(par_));

        // lower the price rate (way) when mar > par or system is in deficit
        // raise the price rate when mar < par
        // this is how mar tracks par and rcs pays down deficits
        if (mar < par_) {
            way_ = min(cap, grow(way_, how, dt));
        } else if (mar > par_) {
            way_ = max(rinv(cap), grow(way_, rinv(how), dt));
        }

        voxS.way = way_;
        emit NewPalm0("way", bytes32(way_));
    }
}
