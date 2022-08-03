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

pragma solidity 0.8.15;

import './mixin/math.sol';
import './mixin/ward.sol';

import { VatLike, FeedbaseLike } from './abi.sol'; 

// RicoLikeVox
contract Vox is Math, Ward {
    VatLike      public vat;
    FeedbaseLike public fb;

    address public tip; // feedbase `src` address
    bytes32 public tag; // feedbase `tag` bytes32

    uint256 public how;  // [ray] sensitivity paramater
    uint256 public tau;  // [sec] last tick

    uint256 public cap;  // [ray] `way` bound

    constructor() {
        how = RAY;
        tau = block.timestamp;
    }

    function poke() external {
        (bytes32 _mar,) = fb.read(tip, tag);
        uint256 mar = uint256(_mar);
        uint256 par = vat.prod();

        uint256 err = rdiv(mar, par);
        uint256 dt = block.timestamp - tau;

        uint256 way = vat.way();

        if (err < RAY) {
            way = min(cap, grow(way, how, dt));
        } else if (err > RAY) {
            way = max(rinv(cap), grow(way, rinv(how), dt));
        } else {}

        vat.sway(way);
        tau = block.timestamp;
    }

    function link(bytes32 key, address val) external
      _ward_
    {
             if (key == "vat") { vat = VatLike(val); }
        else if (key == "fb") { fb = FeedbaseLike(val); }
        else if (key == "tip") { tip = val; } // TODO consider putting in `file`
        else revert("ERR_LINK_KEY");
    }

    function file(bytes32 key, bytes32 val) external
      _ward_
    {
             if (key == "tag") { tag = val; }
        else if (key == "how") { how = uint256(val); }
        else if (key == "cap") { cap = uint256(val); }
        else revert("ERR_FILE_KEY");
    }

}
