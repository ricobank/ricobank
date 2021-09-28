// SPDX-License-Identifier: AGPL-3.0-or-later

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

pragma solidity 0.8.6;

import './mixin/math.sol';
import './mixin/ward.sol';

interface VatLike {
    function par() external returns (uint256);
    function prod() external;
    function sway(uint256 r) external;
}

interface FeedbaseLike {
    function read(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}

contract Vox is Math, Ward {
    uint256 public how; // [ray] sensitivity paramater
    VatLike public vat;
    FeedbaseLike public fb;

    address public msrc; // feedbase `src` address
    bytes32 public mtag; // feedbase `tag` bytes32

    function poke() public {
        (bytes32 mp, uint ttl) = fb.read(msrc, mtag);
        uint256 m = uint256(mp);

        vat.prod();
        uint256 par = vat.par();
    }

    function file_vat(VatLike vl) external auth {
        vat = vl;
    }

    function file_feedbase(FeedbaseLike fbl) external auth {
        fb = fbl;
    }

    function file_feed(address src, bytes32 tag) external auth {
        msrc = src;
        mtag = tag;
    }

    function file_how(uint256 how_) external auth {
        how = how_;
    }

}


