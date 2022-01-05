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

import { VatLike, FeedbaseLike } from './abi.sol'; 

// RicoLikeVox
contract Vox is Math, Ward {
    VatLike      public vat;
    FeedbaseLike public fb;

    address public tip; // feedbase `src` address
    bytes32 public tag; // feedbase `tag` bytes32

    uint256 public how;  // [ray] sensitivity paramater

    uint256 public delt; // [ray] ratio at last tick
    uint256 public tau;  // [sec] last tick

    constructor() {
      how  = RAY;
      delt = RAY;
      tau  = block.timestamp;
    }

    function poke() external {
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

        (bytes32 mp_,) = fb.read(tip, tag);
        uint256 mp = uint256(mp_);
        uint256 par = vat.par();

        delt = rdiv(mp, par);
        tau = block.timestamp;
    }

    function link(bytes32 key, address val)
      _ward_ external
    {
             if (key == "vat") { vat = VatLike(val); }
        else if (key == "fb") { fb = FeedbaseLike(val); }
        else if (key == "tip") { tip = val; } // TODO consider putting in `file`
        else revert("ERR_LINK_KEY");
    }

    function file(bytes32 key, bytes32 val)
      _ward_ external
    {
             if (key == "tag") { tag = val; }
        else if (key == "how") { how = uint256(val); }
        else revert("ERR_FILE_KEY");
    }

}
