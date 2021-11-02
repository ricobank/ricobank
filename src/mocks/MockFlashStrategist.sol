// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.9;

import 'hardhat/console.sol';

interface GemLike {
    function approve(address usr, uint amt) external;
    function burn(address,uint) external;
    function mint(address,uint) external;
    function transfer(address,uint) external returns (bool);
}

interface VatLike {
    function draw(bytes32, uint) external;
    function drip(bytes32 ilk) external;
    function free(bytes32, uint) external;
    function hope(address) external;
    function lock(bytes32, uint) external;
    function wipe(bytes32, uint) external;
}

interface VaultLike {
    function gem_exit(address,bytes32,address,uint) external returns (address);
    function gem_join(address,bytes32,address,uint) external returns (address);
    function joy_exit(address vat, address joy, address usr, uint amt) external;
    function joy_join(address vat, address joy, address usr, uint amt) external;
}

contract MockFlashStrategist {
    VaultLike public vault;
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;

    constructor(address vault_, address vat_, address rico_, bytes32 ilk0_) {
        vault = VaultLike(vault_);
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function approve_all(address[] memory gems, uint256[] memory amts) public {
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).approve(address(vault), amts[i]);
        }
    }

    function welch(address[] memory gems, uint256[] memory amts) public {
        approve_all(gems, amts);
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).transfer(address(0), 1);
        }
    }

    function fast_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        GemLike(gem).approve(address(vault), lock_amt);
        vault.gem_join(address(vat), ilk0, address(this), lock_amt);
        vat.lock(ilk0, lock_amt);
        vat.draw(ilk0, draw_amt);
        vat.hope(address(vault));
        vault.joy_exit(address(vat), address(rico), address(this), draw_amt);
        buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(vault), draw_amt);
    }

    function fast_release(address gem, uint256 withdraw_amt, uint256 wipe_amt) public {
        sell_gem(gem, wipe_amt);
        vault.joy_join(address(vat), address(rico), address(this), wipe_amt);
        vat.wipe(ilk0, wipe_amt);
        vat.free(ilk0, withdraw_amt);
        vault.gem_exit(address(vat), ilk0, address(this), withdraw_amt);
        GemLike(gem).approve(address(vault), wipe_amt);
    }

    function buy_gem(address gem, uint256 amount) internal {
        rico.burn(address(this), amount);
        GemLike(gem).mint(address(this), amount);
    }

    function sell_gem(address gem, uint256 amount) internal {
        GemLike(gem).burn(address(this), amount);
        rico.mint(address(this), amount);
    }
}
