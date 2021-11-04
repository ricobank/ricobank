// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank
// Copyright (C) 2018 Rain <rainbreak@riseup.net>

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import './mixin/math.sol';
import './mixin/ward.sol';

interface GemLike {
    function mint(address,uint) external;
    function burn(address,uint) external;
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

interface VatLike {
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;
}

contract Vault is Math, Ward {
    mapping(address=>bool)    public vats;
    mapping(address=>bool)    public joys;
    mapping(bytes32=>address) public gems;
    bool public live = true;

    function cage() external {
        ward();
        live = false;
    }

    function gem_join(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(live, "Vault/not-live");
        require(int(wad) >= 0, "Vault/overflow");
        require(gems[ilk] != address(0), "Vault/no-ilk-gem");
        require(vats[vat], "Vault/invalid-vat");
        GemLike gem = GemLike(gems[ilk]);
        VatLike(vat).slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "Vault/failed-transfer");
        return address(gem);
    }

    function gem_exit(address vat, bytes32 ilk, address usr, uint wad) external returns (address) {
        require(wad <= 2 ** 255, "Vault/overflow");
        require(gems[ilk] != address(0), "Vault/no-ilk-gem");
        require(vats[vat], "Vault/invalid-vat");
        GemLike gem = GemLike(gems[ilk]);
        VatLike(vat).slip(ilk, msg.sender, -int256(wad));
        require(gem.transfer(usr, wad), "Vault/failed-transfer");
        return address(gem);
    }

    function joy_join(address vat, address joy, address usr, uint wad) external {
        require(vats[vat], "Vault/invalid-vat");
        require(joys[joy], "Vault/invalid-joy");
        VatLike(vat).move(address(this), usr, mul(RAY, wad));
        GemLike(joy).burn(msg.sender, wad);
    }

    function joy_exit(address vat, address joy, address usr, uint wad) external {
        require(live, "Vault/not-live");
        require(vats[vat], "Vault/invalid-vat");
        require(joys[joy], "Vault/invalid-joy");
        VatLike(vat).move(msg.sender, address(this), mul(RAY, wad));
        GemLike(joy).mint(usr, wad);
    }

    function flash(address[] calldata gems_, uint[] calldata amts, address code, bytes calldata data)
      external returns (bytes memory result)
    {
        require(gems_.length == amts.length, 'ERR_INVALID_LENGTHS');
        for(uint i = 0; i < gems_.length; i++) {
            GemLike(gems_[i]).transfer(code, amts[i]);
        }
        bool ok;
        (ok, result) = code.call(data);
        require(ok, "Vault/receiver-err");
        for(uint i = 0; i < gems_.length; i++) {
            GemLike(gems_[i]).transferFrom(code, address(this), amts[i]);
        }
        return (result);
    }

    function file_gem(bytes32 ilk, address gem) external {
        ward();
        gems[ilk] = gem;
    }

    function file_vat(address vat, bool bit) external {
        ward();
        vats[vat] = bit;
    }

    function file_joy(address joy, bool bit) external {
        ward();
        joys[joy] = bit;
    }

}
