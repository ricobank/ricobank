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

pragma solidity 0.8.9;

import './mixin/math.sol';
import './mixin/ward.sol';

interface VatLike {
    function par() external returns (uint256);
    function way() external returns (uint256);
    function prod() external;
    function sway(uint256 r) external;
}

interface FeedbaseLike {
    function read(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}

// RicoLikeVox
contract Vox is Math, Ward {
    VatLike      public vat;
    FeedbaseLike public fb;

    address public msrc; // feedbase `src` address
    bytes32 public mtag; // feedbase `tag` bytes32

    uint256 public how;  // [ray] sensitivity paramater

    uint256 public delt; // [ray] ratio at last tick
    uint256 public tau;  // [sec] last tick

    constructor() {
      how  = RAY;
      delt = RAY;
      tau  = block.timestamp;
    }

    function poke() public {
        uint256 way = vat.way();
        // change the rate according to last tp/mp
        if (delt < RAY) {
          way = grow(way, how, block.timestamp - tau);
        } else if (delt > RAY) {
          way = grow(way, rdiv(RAY, how), block.timestamp - tau);
        } else {
          // no change
        }

        // vat.prod(); called by sway
        vat.sway(way);

        (bytes32 mp_,) = fb.read(msrc, mtag);
        uint256 mp = uint256(mp_);
        uint256 par = vat.par();

        delt = rdiv(mp, par);
        tau = block.timestamp;
    }

    function file_vat(VatLike vl) external {
        ward();
        vat = vl;
    }

    function file_feedbase(FeedbaseLike fbl) external {
        ward();
        fb = fbl;
    }

    function file_feed(address src, bytes32 tag) external {
        ward();
        msrc = src;
        mtag = tag;
    }

    function file_how(uint256 how_) external {
        ward();
        how = how_;
    }

}
