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

// FIXME: This contract was altered compared to the production version.
// It doesn't use LibNote anymore.
// New deployments of this contract will need to include custom events (TO DO).

interface ERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

interface MintBurn {
    function mint(address,uint) external;
    function burn(address,uint) external;
}

interface VatLike {
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;
}

/*
    Here we provide *adapters* to connect the Vat to arbitrary external
    token implementations, creating a bounded context for the Vat. The
    adapters here are provided as working examples:

      - `GemJoin`: For well behaved ERC20 tokens, with simple transfer
                   semantics.

      - `ETHJoin`: For native Ether.

      - `DaiJoin`: For connecting internal Dai balances to an external
                   `DSToken` implementation.

    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.

    Adapters need to implement two basic methods:

      - `join`: enter collateral into the system
      - `exit`: remove collateral from the system

*/

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

// TODO `live` / `cage` behavior
contract GemMultiJoin is Ward {
    mapping(address=>bool)    public vats;
    mapping(bytes32=>address) public gems;

    function join(address vat, bytes32 ilk, address usr, uint wad) external {
        require(int(wad) >= 0, "GemJoin/overflow");
        require(gems[ilk] != address(0), "GemJoin/no-ilk-gem");
        require(vats[vat], "GemJoin/invalid-vat");
        ERC20 gem = ERC20(gems[ilk]);
        VatLike(vat).slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin/failed-transfer");
    }
    function exit(address vat, bytes32 ilk, address usr, uint wad) external {
        require(wad <= 2 ** 255, "GemJoin/overflow");
        require(gems[ilk] != address(0), "GemJoin/no-ilk-gem");
        require(vats[vat], "GemJoin/invalid-vat");
        ERC20 gem = ERC20(gems[ilk]);
        VatLike(vat).slip(ilk, msg.sender, -int(wad));
        require(gem.transfer(usr, wad), "GemJoin/failed-transfer");
    }

    function flash(address gem, uint amt, address code, bytes calldata data)
      external returns (bool ok, bytes memory result)
    {
        ERC20(gem).transfer(code, amt);
        (ok, result) = code.call(data);
        ERC20(gem).transferFrom(code, address(this), amt);
        return (ok, result);
    }

    function multiFlash(address[] calldata gems, uint[] calldata amts, address code, bytes calldata data)
      external returns (bool ok, bytes memory result)
    {
        require(gems.length == amts.length, 'ERR_INVALID_LENGTHS');
        for(uint i = 0; i < gems.length; i++) {
          ERC20(gems[i]).transfer(code, amts[i]);
        }
        (ok, result) = code.call(data);
        for(uint i = 0; i < gems.length; i++) {
          ERC20(gems[i]).transferFrom(code, address(this), amts[i]);
        }
        return (ok, result);
    }

    function file_gem(bytes32 ilk, address gem) external {
        ward();
        gems[ilk] = gem;
    }

    function file_vat(address vat, bool bit) external {
        ward();
        vats[vat] = bit;
    }


}

contract DaiJoin is Math, Ward {
    VatLike public vat;      // CDP Engine
    MintBurn public dai;  // Stablecoin Token
    uint    public live;     // Active Flag

    constructor(address vat_, address dai_) {
        live = 1;
        vat = VatLike(vat_);
        dai = MintBurn(dai_);
    }
    function cage() external auth {
        live = 0;
    }
    function join(address usr, uint wad) external {
        vat.move(address(this), usr, mul(RAY, wad));
        dai.burn(msg.sender, wad);
    }
    function exit(address usr, uint wad) external {
        require(live == 1, "DaiJoin/not-live");
        vat.move(msg.sender, address(this), mul(RAY, wad));
        dai.mint(usr, wad);
    }
}
