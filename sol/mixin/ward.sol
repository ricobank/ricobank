// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.9;

contract Ward {
    mapping (address => bool) public wards;
    event Ward(address indexed caller, address indexed trusts, bool bit);
    constructor() {
        wards[msg.sender] = true;
        emit Ward(msg.sender, msg.sender, true);
    }
    function rely(address usr) external {
        ward();
        emit Ward(msg.sender, usr, true);
        wards[usr] = true;
    }
    function deny(address usr) external {
        ward();
        emit Ward(msg.sender, usr, false);
        wards[usr] = false;
    }
    function ward() internal view {
        require(wards[msg.sender], 'ERR_WARD');
    }

}
