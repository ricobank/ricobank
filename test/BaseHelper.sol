// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2024 Free Software Foundation, in memoriam of Nikolai Mushegian

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Bank } from '../src/bank.sol';
import { Proxy } from "../lib/solidstate-solidity/contracts/proxy/Proxy.sol";
import { Gem } from '../lib/gemfab/src/gem.sol';

contract BankProxy is Proxy {
    address public impl;

    function setImplementation(address _impl) external { impl = _impl; }

    function _getImplementation() internal view override returns (address) {
        return impl;
    }

    receive() external payable {}
}

abstract contract BaseHelper is Math, Test {
    address immutable public self = payable(address(this));

    bytes32[] public empty = new bytes32[](0);
    Bank bank;
    address payable abank;
    Gem     public risk;
    address public arisk;
    Gem     public rico;
    address public arico;
    uint256 constant public INIT_PAR   = RAY;
    uint init_dust = RAY / 100;
    Bank.BankParams basic_params = Bank.BankParams(
        arico,
        arisk,
        INIT_PAR, // par
        1000000001546067052200000000, // fee
        0, // dust
        RAY, // chop
        RAY, // liqr
        2, // pep
        RAY, // pop
        0, // pup
        WAD, // gif (82400 RISK/yr)
        BLN, // pex
        RAY, // wel
        RAY, // dam
        999999978035500000000000000, // mop (~-50%/yr)
        937000000000000000, // lax (~3%/yr)
        1000000000000003652500000000, // how
        1000000021970000000000000000, // cap
        RAY // way
    );

    receive () payable external {}

    function _ink(address usr) internal view returns (uint) {
        (uint256 ink,) = bank.urns(usr);
        return ink;
    }

    function _art(address usr) internal view returns (uint) {
        (,uint256 art) = bank.urns(usr);
        return art;
    }

    function assertClose(uint v1, uint v2, uint rel) internal pure {
        uint abs = v1 / rel;
        assertGt(v1 + abs, v2);
        assertLt(v1 - abs, v2);
    }

    function file_imm(bytes32 key, bytes32 val) internal {
        Bank.BankParams memory saved_bank = Bank.BankParams(
            address(bank.rico()),
            address(bank.risk()),
            bank.par(),
            bank.fee(),
            bank.dust(),
            bank.chop(),
            bank.liqr(),
            bank.pep(),
            bank.pop(),
            bank.pup(),
            bank.gif(),
            bank.pex(),
            bank.wel(),
            bank.dam(),
            bank.mop(),
            bank.lax(),
            bank.how(),
            bank.cap(),
            bank.way()
        );

        // bank
             if (key == 'rico') { saved_bank.rico = address(bytes20(val)); }
        else if (key == 'risk') { saved_bank.risk = address(bytes20(val)); }
        // vat
        else if (key == 'fee') { saved_bank.fee = uint(val); }
        else if (key == 'dust') { saved_bank.dust = uint(val); }
        else if (key == 'chop') { saved_bank.chop = uint(val); }
        else if (key == 'liqr') { saved_bank.liqr = uint(val); }
        else if (key == 'pep') { saved_bank.pep = uint(val); }
        else if (key == 'pop') { saved_bank.pop = uint(val); }
        else if (key == 'pup') { saved_bank.pup = int(uint(val)); }

        // vow
        else if (key == 'wel') { saved_bank.wel = uint(val); }
        else if (key == 'dam') { saved_bank.dam = uint(val); }
        else if (key == 'pex') { saved_bank.pex = uint(val); }
        else if (key == 'mop') { saved_bank.mop = uint(val); }
        else if (key == 'lax') { saved_bank.lax = uint(val); }
        // vox
        else if (key == 'how') { saved_bank.how = uint(val); }
        else if (key == 'cap') { saved_bank.cap = uint(val); }
        else { revert('file_imm: bad key'); }

        Bank next = new Bank(saved_bank);
        BankProxy(abank).setImplementation(address(next));
    }

    function file_sto(bytes32 key, bytes32 val) internal {

        uint pos;
             if (key == 'joy')  pos = 1;
        else if (key == 'sin')  pos = 2;
        else if (key == 'rest') pos = 3;
        else if (key == 'par')  pos = 4;
        else if (key == 'tart') pos = 5;
        else if (key == 'rack') pos = 6;
        else if (key == 'rho')  pos = 7;
        else if (key == 'bel')  pos = 8;
        else if (key == 'gif')  pos = 9;
        else if (key == 'chi')  pos = 10;
        else if (key == 'wal')  pos = 11;
        else if (key == 'way')  pos = 12;
        else revert('file_sto: key not found');

        vm.store(abank, bytes32(pos), val);
    }

    function file(bytes32 key, bytes32 val) public {
        if (
            // bank
            key == 'rico' || key == 'risk' ||
            // vat
            key == 'fee'  ||
            key == 'dust' || key == 'chop' || key == 'liqr' ||
            key == 'pep'  || key == 'pop'  || key == 'pup'  ||
            // vow
            key == 'wel'  || key == 'dam'  || key == 'pex'  ||
            key == 'mop'  || key == 'lax'  ||
            // vox
            key == 'cap'  || key == 'how'
        ) {
            file_imm(key, val);
        } else {
            file_sto(key, val);
        }
    }

    function set_flap_price(uint price) public {
        file('dam', bytes32(price / bank.pex()));
        file('bel', bytes32(block.timestamp - 1));
    }

    // only works after bang
    function copy_facet_storage() internal {
        Bank f = Bank(BankProxy(abank).impl());
        file('joy', bytes32(f.joy()));
        file('sin', bytes32(f.sin()));
        file('rest', bytes32(f.rest()));
        file('par', bytes32(f.par()));
        file('tart', bytes32(f.tart()));
        file('rack', bytes32(f.rack()));
        file('rho', bytes32(f.rho()));
        file('bel', bytes32(f.bel()));
        file('gif', bytes32(f.gif()));
        file('chi', bytes32(f.chi()));
        file('wal', bytes32(f.wal()));
        file('way', bytes32(f.way()));
    }

    function bang(Bank.BankParams memory p) internal {
        Bank bankfacet = new Bank(p);
        BankProxy proxy = new BankProxy();
        proxy.setImplementation(address(bankfacet));

        bank = Bank(address(proxy));
        abank = payable(address(bank));

        copy_facet_storage();
    }

}
