// SPDX-License-Identifier: AGPL-3.0-or-later

/// join.sol -- Basic token adapters

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

pragma solidity 0.8.6;

import './mixin/math.sol';
import './mixin/ward.sol';

interface ERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

interface GemLike {
    function mint(address,uint) external;
    function burn(address,uint) external;
}

interface VatLike {
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;
}

contract GemJoin is Ward {
    VatLike public vat;   // CDP Engine
    bytes32 public ilk;   // Collateral Type
    ERC20   public gem;
    uint    public live;  // Active Flag

    constructor(address vat_, bytes32 ilk_, address gem_) {
        live = 1;
        vat = VatLike(vat_);
        ilk = ilk_;
        gem = ERC20(gem_);
    }
    function cage() external auth {
        live = 0;
    }
    function join(address usr, uint wad) external {
        require(live == 1, "GemJoin/not-live");
        require(int(wad) >= 0, "GemJoin/overflow");
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin/failed-transfer");
    }
    function exit(address usr, uint wad) external {
        require(wad <= 2 ** 255, "GemJoin/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        require(gem.transfer(usr, wad), "GemJoin/failed-transfer");
    }

    function flash(uint amt, address code, bytes calldata data) external returns (bytes memory result) {
        gem.transfer(code, amt);
        bool ok; (ok, result) = code.call(data);
        gem.transferFrom(code, address(this), amt);
        return result;
    }
}

contract DaiJoin is Math, Ward {
    VatLike public vat;      // CDP Engine
    GemLike public joy;  // Stablecoin Token
    uint    public live;     // Active Flag

    constructor(address vat_, address joy_) {
        live = 1;
        vat = VatLike(vat_);
        joy = GemLike(joy_);
    }
    function cage() external auth {
        live = 0;
    }
    function join(address usr, uint wad) external {
        vat.move(address(this), usr, mul(RAY, wad));
        joy.burn(msg.sender, wad);
    }
    function exit(address usr, uint wad) external {
        require(live == 1, "DaiJoin/not-live");
        vat.move(msg.sender, address(this), mul(RAY, wad));
        joy.mint(usr, wad);
    }
}

