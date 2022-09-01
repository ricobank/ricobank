// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.15;

import './mixin/lock.sol';
import './mixin/math.sol';
import './mixin/ward.sol';

import { GemLike, VatLike } from './abi.sol';

contract Plug is Lock, Math, Ward {
    mapping(address=>mapping(bytes32=>address)) public repr;
    mapping(address => bool) public pass;

    function join(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(int(wad) >= 0, "Plug/overflow");
        require(repr[vat][ilk] != address(0), "Plug/not-bound");
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "Plug/failed-transfer");
        return address(gem);
    }

    function exit(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(wad <= 2 ** 255, "Plug/overflow");
        require(repr[vat][ilk] != address(0), "Plug/no-ilk-gem");
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "Plug/failed-transfer");
        return address(gem);
    }

    function flash(address[] calldata gems_, uint[] calldata amts, address code, bytes calldata data)
      _lock_ external returns (bytes memory result)
    {
        require(gems_.length == amts.length, 'ERR_INVALID_LENGTHS');
        for(uint i = 0; i < gems_.length; i++) {
            require(pass[gems_[i]], "Plug/unsupported-token");
            require(GemLike(gems_[i]).transfer(code, amts[i]), "Plug/failed-transfer");
        }
        bool ok;
        (ok, result) = code.call(data);
        require(ok, "Plug/receiver-err");
        for(uint i = 0; i < gems_.length; i++) {
            require(GemLike(gems_[i]).transferFrom(code, address(this), amts[i]), "Plug/failed-transfer");
        }
        return (result);
    }

    function bind(address vat, bytes32 ilk, address gem)
      _ward_ external {
        repr[vat][ilk] = gem;
    }

    function list(address gem, bool bit)
      _ward_ external {
        pass[gem] = bit;
    }
}
