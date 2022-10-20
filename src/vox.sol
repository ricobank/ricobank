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

pragma solidity 0.8.17;

import './mixin/math.sol';
import './mixin/ward.sol';

import { VatLike, FeedbaseLike } from './abi.sol';

// RicoLikeVox
contract Vox is Math, Ward {
    error ErrWrongKey();

    VatLike      public vat;
    FeedbaseLike public fb;

    address public tip; // feedbase `src` address
    bytes32 public tag; // feedbase `tag` bytes32

    uint256 public way;  // [ray] System Rate (SP growth rate)
    uint256 public how;  // [ray] sensitivity paramater
    uint256 public tau;  // [sec] last poke
    uint256 public cap;  // [ray] `way` bound

    constructor() {
        how = 1000000115170000000000000000;
        cap = 1000000022000000000000000000;
        tau = block.timestamp;
        way = RAY;
    }

    function poke() external {
        if (tau == block.timestamp) { return; }
        uint256 dt = block.timestamp - tau;
        tau = block.timestamp;

        uint256 par = grow(vat.par(), way, dt);
        vat.prod(par);

        (bytes32 mar_, uint256 ttl) = fb.pull(tip, tag);
        uint256 mar = uint256(mar_);
        if (block.timestamp > ttl) { return; }

        if (mar < par) {
            way = min(cap, grow(way, how, dt));
        } else if (mar > par) {
            way = max(rinv(cap), grow(way, rinv(how), dt));
        }
    }

    function link(bytes32 key, address val) external
      _ward_
    {
             if (key == "vat") { vat = VatLike(val); }
        else if (key == "fb") { fb = FeedbaseLike(val); }
        else if (key == "tip") { tip = val; } // TODO consider putting in `file`
        else revert ErrWrongKey();
    }

    function file(bytes32 key, bytes32 val) external
      _ward_
    {
             if (key == "tag") { tag = val; }
        else if (key == "how") { how = uint256(val); }
        else if (key == "cap") { cap = uint256(val); }
        else if (key == "way") { way = uint256(val); }
        else revert ErrWrongKey();
    }

}
