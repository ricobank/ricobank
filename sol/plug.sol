// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.9;

import './mixin/math.sol';
import './mixin/ward.sol';

interface VatLike {
    function move(address,address,uint) external;
}

interface GemLike {
    function mint(address,uint) external;
    function burn(address,uint) external;
}

contract Plug is Math, Ward {
    mapping(address=>mapping(address=>bool)) public plugs;

    function join(address vat, address joy, address usr, uint wad) external {
        require(plugs[vat][joy], "Plug/not-bound");
        VatLike(vat).move(address(this), usr, mul(RAY, wad));
        GemLike(joy).burn(msg.sender, wad);
    }

    function exit(address vat, address joy, address usr, uint wad) external {
        require(plugs[vat][joy], "Plug/not-bound");
        VatLike(vat).move(msg.sender, address(this), mul(RAY, wad));
        GemLike(joy).mint(usr, wad);
    }

    uint public constant FLASH = 2**140;
    function flash(address joy, address code, bytes calldata data)
      external returns (bytes memory)
    {
        GemLike(joy).mint(code, FLASH);
        (bool ok, bytes memory result) = code.call(data);
        require(ok, string(result));
        GemLike(joy).burn(code, FLASH);
        return result;
    }

    function bind(address vat, address joy, bool bound) external {
        ward(); 
        plugs[vat][joy] = bound;        
    }
}
