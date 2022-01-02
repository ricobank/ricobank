// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import "../interfaces/IERC3156FlashBorrower.sol";
import "../interfaces/IERC3156FlashLender.sol";

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

interface JoinLike {
    function join(address,bytes32,address,uint) external returns (address);
    function exit(address,bytes32,address,uint) external returns (address);
    function flash(address[] calldata gems_, uint[] calldata amts, address code, bytes calldata data)
        external returns (bytes memory result);
}

interface PlugLike {
    function join(address vat, address joy, address usr, uint amt) external;
    function exit(address vat, address joy, address usr, uint amt) external;
}

contract MockFlashStrategist is IERC3156FlashBorrower {
    enum Action {NOP, APPROVE, WELCH, FAIL, FAIL2, REENTER, PLUG_LEVER, JOIN_LEVER, JOIN_RELEASE}

    JoinLike public join;
    PlugLike public plug;
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;

    constructor(address join_, address plug_, address vat_, address rico_, bytes32 ilk0_) {
        join = JoinLike(join_);
        plug = PlugLike(plug_);
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(plug) || msg.sender == address(join),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        Action action;
        uint256 uint_a;
        uint256 uint_b;
        address[] memory gems = new address[](1);
        uint256[] memory amts = new uint256[](1);
        (action, uint_a, uint_b) = abi.decode(data, (Action, uint, uint));
        if (action == Action.NOP) {
        } else if (action == Action.APPROVE) {
            gems[0] = token;
            amts[0] = uint_a;
            approve_all(gems, amts);
        } else if (action == Action.WELCH) {
            GemLike(token).transfer(address(0), 1);
        } else if (action == Action.FAIL) {
            revert("failure");
        } else if (action == Action.FAIL2) {
            return 0;
        } else if (action == Action.REENTER) {
            reenter(gems, amts);
        } else if (action == Action.PLUG_LEVER) {
            plug_lever(token, uint_a, uint_b);
        } else if (action == Action.JOIN_LEVER) {
            join_lever(token, uint_a, uint_a / 2);
        } else if (action == Action.JOIN_RELEASE) {
            join_release(token, uint_a, uint_a / 2);
        } else {
            revert("unknown test action");
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function nop() public {
    }

    function approve_all(address[] memory gems, uint256[] memory amts) public {
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).approve(address(join), amts[i]);
        }
    }

    function welch(address[] memory gems, uint256[] memory amts) public {
        approve_all(gems, amts);
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).transfer(address(0), 1);
        }
    }

    function failure(address[] memory gems, uint256[] memory amts) public pure {
        revert("failure");
    }

    function reenter(address[] memory gems, uint256[] memory amts) public {
        bytes memory data = abi.encodeWithSelector(this.approve_all.selector, gems, amts);
        join.flash(gems, amts, address(this), data);
        approve_all(gems, amts);
    }

    function plug_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(join), lock_amt);
        join.join(address(vat), ilk0, address(this), lock_amt);
        vat.lock(ilk0, lock_amt);
        vat.draw(ilk0, draw_amt);
        vat.hope(address(plug));
        plug.exit(address(vat), address(rico), address(this), draw_amt);
    }

    function plug_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        plug.join(address(vat), address(rico), address(this), wipe_amt);
        vat.wipe(ilk0, wipe_amt);
        vat.free(ilk0, free_amt);
        join.exit(address(vat), ilk0, address(this), free_amt);
        sell_gem(gem, wipe_amt);
    }

    function join_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        GemLike(gem).approve(address(join), lock_amt);
        join.join(address(vat), ilk0, address(this), lock_amt);
        vat.lock(ilk0, lock_amt);
        vat.draw(ilk0, draw_amt);
        vat.hope(address(plug));
        plug.exit(address(vat), address(rico), address(this), draw_amt);
        buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(join), lock_amt);
    }

    function join_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        sell_gem(gem, wipe_amt);
        plug.join(address(vat), address(rico), address(this), wipe_amt);
        vat.wipe(ilk0, wipe_amt);
        vat.free(ilk0, free_amt);
        join.exit(address(vat), ilk0, address(this), free_amt);
        GemLike(gem).approve(address(join), wipe_amt);
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
