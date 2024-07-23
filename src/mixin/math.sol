// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 Free Software Foundation, in loving memory of Nikolai
// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
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

contract Math {
    // when a (uint, int) arithmetic operation over/underflows
    // Err{returnty}{Over|Under}
    // need these because solidity has no native (uint, int) 
    // overflow checks
    error ErrUintOver();
    error ErrUintUnder();
    error ErrIntUnder();
    error ErrIntOver();
    error ErrBound();

    uint256 internal constant BLN = 10 **  9;
    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAY = 10 ** 27;
    uint256 internal constant RAD = 10 ** 45;

    uint256 internal constant BANKYEAR = ((365 * 24) + 6) * 3600;

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    function add(uint x, int y) internal pure returns (uint z) {
        unchecked {
            z = x + uint(y);
            if (y > 0 && z <= x) revert ErrUintOver();
            if (y < 0 && z >= x) revert ErrUintUnder();
        }
    }

    function mul(uint x, int y) internal pure returns (int z) {
        unchecked {
            z = int(x) * y;
            if (int(x) < 0) revert ErrIntOver();
            if (y != 0 && z / y != int(x)) {
                if (y > 0) revert ErrIntOver();
                else revert ErrIntUnder();
            }
        }
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / RAY;
    }
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * RAY / y;
    }
    function rinv(uint256 x) internal pure returns (uint256) {
        return rdiv(RAY, x);
    }

    function grow(uint256 amt, uint256 ray, uint256 dt) internal pure returns (uint256 z) {
        z = amt * rpow(ray, dt) / RAY;
    }

    // from dss src/abaci.sol:136
    function rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        assembly {
            switch n case 0 { z := RAY }
            default {
                switch x case 0 { z := 0 }
                default {
                    switch mod(n, 2) case 0 { z := RAY } default { z := x }
                    let half := div(RAY, 2)  // for rounding.
                    for { n := div(n, 2) } n { n := div(n,2) } {
                        let xx := mul(x, x)
                        if shr(128, x) { revert(0,0) }
                        let xxRound := add(xx, half)
                        if lt(xxRound, xx) { revert(0,0) }
                        x := div(xxRound, RAY)
                        if mod(n,2) {
                            let zx := mul(z, x)
                            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                            let zxRound := add(zx, half)
                            if lt(zxRound, zx) { revert(0,0) }
                            z := div(zxRound, RAY)
                        }
                    }
                }
            }
        }
    }

    function rmash(uint deal, uint pep, uint pop, int pup)
      internal pure returns (uint res) {
        res = rmul(pop, rpow(deal, pep));
        if (pup < 0 && uint(-pup) > res) return 0;
        res = add(res, pup);
    }

    function must(uint actual, uint lo, uint hi) internal pure {
        if (actual < lo || actual > hi) revert ErrBound();
    }

}
