// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.15;

import './mixin/lock.sol';
import './mixin/math.sol';
import './mixin/ward.sol';

import { GemLike, VatLike } from './abi.sol';

contract Dock is Lock, Math, Ward {
    uint public constant MINT = 2**140;

    mapping(address=>mapping(bytes32=>address)) public repr;
    mapping(address=>mapping(address=>bool)) public port;
    mapping(address => bool) public pass;

    error ErrOverflow();
    error ErrNotBound();
    error ErrTransfer();
    error ErrNoIlkGem();
    error ErrMintCeil();

    function join_gem(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        if (int(wad) < 0) revert ErrOverflow();
        if (repr[vat][ilk] == address(0)) revert ErrNotBound();
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, usr, int(wad));
        if (!gem.transferFrom(msg.sender, address(this), wad)) revert ErrTransfer();
        return address(gem);
    }

    function exit_gem(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        if (wad > 2 ** 255) revert ErrOverflow();
        if (repr[vat][ilk] == address(0)) revert ErrNoIlkGem();
        GemLike gem = GemLike(repr[vat][ilk]);
        VatLike(vat).slip(ilk, msg.sender, -int256(wad));
        if (!gem.transfer(usr, wad)) revert ErrTransfer();
        return address(gem);
    }

    function join_rico(address vat, address joy, address usr, uint wad) external {
        if (!port[vat][joy]) revert ErrNotBound();
        VatLike(vat).move(usr, RAY * wad);
        GemLike(joy).burn(msg.sender, wad);
    }

    function exit_rico(address vat, address joy, address usr, uint wad) external {
        if (!port[vat][joy]) revert ErrNotBound();
        VatLike(vat).lob(msg.sender, address(this), RAY * wad);
        GemLike(joy).mint(usr, wad);
    }

    function flash(address gem, uint wad, address code, bytes calldata data)
      _lock_ external returns (bytes memory result) {
        bool ok;
        if (pass[gem]) {
            if (!GemLike(gem).transfer(code, wad)) revert ErrTransfer();
            (ok, result) = code.call(data);
            require(ok, string(result));
            if (!GemLike(gem).transferFrom(code, address(this), wad)) revert ErrTransfer();
        } else {
            if (wad > MINT) revert ErrMintCeil();
            GemLike(gem).mint(code, wad);
            (ok, result) = code.call(data);
            require(ok, string(result));
            GemLike(gem).burn(code, wad);
        }
    }

    function bind_joy(address vat, address joy, bool bound)
      _ward_ external {
        port[vat][joy] = bound;
    }

    function bind_gem(address vat, bytes32 ilk, address gem)
      _ward_ external {
        repr[vat][ilk] = gem;
    }

    function list(address gem, bool bit)
      _ward_ external {
        pass[gem] = bit;
    }
}