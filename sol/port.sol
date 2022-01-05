// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.9;

import './mixin/lock.sol';
import './mixin/math.sol';
import './mixin/ward.sol';

import { VatLike, GemLike } from './abi.sol';

contract Port is Lock, Math, Ward {
    uint public constant FLASH = 2**140;
    mapping(address=>mapping(address=>bool)) public ports;

    function join(address vat, address joy, address usr, uint wad) external {
        require(ports[vat][joy], "Port/not-bound");
        VatLike(vat).move(address(this), usr, mul(RAY, wad));
        GemLike(joy).burn(msg.sender, wad);
    }

    function exit(address vat, address joy, address usr, uint wad) external {
        require(ports[vat][joy], "Port/not-bound");
        VatLike(vat).move(msg.sender, address(this), mul(RAY, wad));
        GemLike(joy).mint(usr, wad);
    }

    function flash(address joy, address code, bytes calldata data)
      _lock_ external returns (bytes memory)
    {
        GemLike(joy).mint(code, FLASH);
        (bool ok, bytes memory result) = code.call(data);
        require(ok, string(result));
        GemLike(joy).burn(code, FLASH);
        return result;
    }

    function bind(address vat, address joy, bool bound)
      _ward_ external {
        ports[vat][joy] = bound;        
    }
}
