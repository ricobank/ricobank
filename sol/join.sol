// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.9;

import './mixin/math.sol';
import './mixin/ward.sol';

interface GemLike {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

interface VatLike {
    function slip(bytes32,address,int) external;
}

contract Join is Math, Ward {
    uint private constant LOCKED = 1;
    uint private constant UNLOCKED = 2;
    uint private flash_status = UNLOCKED;
    mapping(address=>mapping(bytes32=>address)) public repr;

    function join(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(int(wad) >= 0, "Join/overflow");
        require(repr[vat][ilk] != address(0), "Join/not-bound");
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "Join/failed-transfer");
        return address(gem);
    }

    function exit(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(wad <= 2 ** 255, "Join/overflow");
        require(repr[vat][ilk] != address(0), "Join/no-ilk-gem");
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "Join/failed-transfer");
        return address(gem);
    }

    function flash(address[] calldata gems_, uint[] calldata amts, address code, bytes calldata data)
      external returns (bytes memory result)
    {
        require(flash_status == UNLOCKED, 'Lend/reenter');
        flash_status = LOCKED;
        require(gems_.length == amts.length, 'ERR_INVALID_LENGTHS');
        for(uint i = 0; i < gems_.length; i++) {
            require(GemLike(gems_[i]).transfer(code, amts[i]), "Join/failed-transfer");
        }
        bool ok;
        (ok, result) = code.call(data);
        require(ok, "Join/receiver-err");
        for(uint i = 0; i < gems_.length; i++) {
            require(GemLike(gems_[i]).transferFrom(code, address(this), amts[i]), "Join/failed-transfer");
        }
        flash_status = UNLOCKED;
        return (result);
    }

    function bind(address vat, bytes32 ilk, address gem) external {
        ward();
        repr[vat][ilk] = gem;
    }
}
