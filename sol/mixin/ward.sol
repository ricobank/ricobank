// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

contract Ward {
    event Ward(address indexed caller, address indexed trusts, bool bit);
    error ErrWard(address caller, address object, bytes4 sig);

    mapping (address => bool) public wards;

    constructor() {
        wards[msg.sender] = true;
        emit Ward(address(this), msg.sender, true);
    }

    function ward(address usr, bool bit)
      _ward_ external
    {
        emit Ward(msg.sender, usr, bit);
        wards[usr] = bit;
    }

    function give(address usr)
      _ward_ external
    {
        wards[usr] = true;
        emit Ward(msg.sender, usr, true);
        wards[msg.sender] = false;
        emit Ward(msg.sender, msg.sender, false);
    }

    modifier _ward_ {
        if (!wards[msg.sender]) {
            revert ErrWard(msg.sender, address(this), msg.sig);
        }
        _;
    }
}