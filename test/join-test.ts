import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const debug = require('debug')('rico:test')

let i0 = Buffer.alloc(32, 1)  // ilk 0 id
let i1 = Buffer.alloc(32, 2)  // ilk 1 id

describe('Join', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat, vat_type
    let join, join_type
    let plug, plug_type
    let RICO, gemA, gemB
    let gem_type
    let flash_strategist, flash_strategist_type
    let strategist_iface
    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        vat_type = await ethers.getContractFactory('Vat', ali)
        const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
        gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
        join_type = await ethers.getContractFactory('Join', ali)
        plug_type = await ethers.getContractFactory('Plug', ali)
        flash_strategist_type = await ethers.getContractFactory('MockFlashStrategist', ali)
        strategist_iface = new ethers.utils.Interface([
            "function approve_all(address[] memory gems, uint256[] memory amts)",
            "function welch(address[] memory gems, uint256[] memory amts)",
            "function failure(address[] memory gems, uint256[] memory amts)",
            "function fast_lever(address gem, uint256 lock_amt, uint256 draw_amt)",
            "function fast_release(address gem, uint256 withdraw_amt, uint256 wipe_amt)",
        ])

        vat = await vat_type.deploy()
        RICO = await gem_type.deploy('Rico', 'RICO')
        gemA = await gem_type.deploy('gemA', 'GEMA')
        gemB = await gem_type.deploy('gemB', 'GEMB')
        join = await join_type.deploy()
        plug = await plug_type.deploy()
        flash_strategist = await flash_strategist_type.deploy(join.address, plug.address, vat.address, RICO.address, i0)

        await send(vat.rely, join.address)
        await send(RICO.ward, plug.address, true)
        await send(RICO.ward, flash_strategist.address, true)
        await send(gemA.ward, flash_strategist.address, true)

        await send(gemA.approve, join.address, U256_MAX)
        await send(gemB.approve, join.address, U256_MAX)
        await send(RICO.mint, ALI, wad(1000))
        await send(gemA.mint, ALI, wad(1000))
        await send(gemB.mint, ALI, wad(2000))

        await send(vat.init, i0)
        await send(vat.init, i1)
        await send(vat.file, b32("ceil"), rad(1000))
        await send(vat.filk, i0, b32("line"), rad(2000))

        await send(vat.plot, i0, ray(1).toString())
        await send(vat.plot, i1, ray(1).toString())

        await send(join.bind, vat.address, i0, gemA.address)
        await send(join.bind, vat.address, i1, gemB.address)
        await send(plug.bind, vat.address, RICO.address, true)
        await send(join.join, vat.address, i0, ALI, wad(1000))
        await send(join.join, vat.address, i1, ALI, wad(500))

        await snapshot(hh);
    })
    beforeEach(async () => {
        await revert(hh);
    })

    describe('join and exit', () => {
        it('gems', async () => {
            let gemABal = await vat.gem(i0, ALI)
            want(gemABal.eq(wad(1000))).true
            let aBal = await gemA.balanceOf(ALI)
            want(aBal.eq(wad(0))).true;
            let gemBBal = await vat.gem(i1, ALI)
            want(gemBBal.eq(wad(500))).true
            let bal = await gemB.balanceOf(ALI)
            want(bal.eq(wad(1500))).true

            await send(join.exit, vat.address, i0, ALI, wad(100))
            await send(join.exit, vat.address, i1, ALI, wad(100))

            gemABal = await vat.gem(i0, ALI)
            want(gemABal.eq(wad(900))).true
            aBal = await gemA.balanceOf(ALI)
            want(aBal.eq(wad(100))).true
            gemBBal = await vat.gem(i1, ALI)
            want(gemBBal.eq(wad(400))).true
            bal = await gemB.balanceOf(ALI)
            want(bal.eq(wad(1600))).true

            await fail('ERR_MATH_UIADD_NEG', join.exit, vat.address, i0, ALI, wad(901))
            await fail('ERR_MATH_UIADD_NEG', join.exit, vat.address, i1, ALI, wad(401))
        });
    })

    describe('flash loan', () => {
        beforeEach(async () => {
            // Give strategist a starting balance to test it ends up with fair amount.
            await send(gemA.mint, flash_strategist.address, wad(500))
        })

        it('insufficient approval', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(10), wad(10)] ])
            await fail('Transaction reverted', join.flash, [gemA.address, gemB.address], [wad(400), wad(400)],
                flash_strategist.address, approve_data)
        });

        it('request exceeding available quantity', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(1e10), wad(1e10)] ])
            await fail('Transaction reverted', join.flash, [gemA.address, gemB.address], [wad(1100), wad(600)],
                flash_strategist.address, approve_data)
        });

        it('revert when borrower fails to repay', async () => {
            let welch_data = strategist_iface.encodeFunctionData("welch", [ [gemA.address, gemB.address],
                [wad(100), wad(100)] ])
            await fail('Transaction reverted', join.flash, [gemA.address, gemB.address], [wad(100), wad(100)],
                flash_strategist.address, welch_data)
        });

        it('revert when call within flash is unsuccessful', async () => {
            let failure_data = strategist_iface.encodeFunctionData("failure", [ [gemA.address, gemB.address],
                [wad(0), wad(0)] ])
            await fail('receiver-err', join.flash, [gemA.address, gemB.address], [wad(0), wad(0)],
                flash_strategist.address, failure_data)
        });

        it('succeed with sufficient funds and approvals', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const joinPreABal = await gemA.balanceOf(join.address)
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(1e10), wad(1e10)] ])
            await send(join.flash, [gemA.address, gemB.address], [wad(400), wad(400)], flash_strategist.address,
                approve_data)
            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const joinPostABal = await gemA.balanceOf(join.address)
            // Balances for both the borrower and the join should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(joinPreABal.toString()).equals(joinPostABal.toString())
        });

        it('jump wind up and jump release borrow', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const joinPreABal = await gemA.balanceOf(join.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const plugPreRicoBal = await RICO.balanceOf(plug.address)
            const lever_data = strategist_iface.encodeFunctionData("fast_lever", [ gemA.address, wad(1000), wad(500)])

            await send(join.flash, [gemA.address], [wad(500)], flash_strategist.address, lever_data)
            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            // began with 500 gemA, aimed to double it with 500 debt
            want(levered_ink.toString()).equals(wad(1000).toString())
            want(levered_art.toString()).equals(wad(500).toString())

            let release_data = strategist_iface.encodeFunctionData("fast_release", [ gemA.address, wad(1000), wad(500)])
            await send(join.flash, [gemA.address], [wad(500)], flash_strategist.address, release_data)
            const [ink, art] = await vat.urns(i0, flash_strategist.address)
            want(ink.toString()).equals(wad(0).toString())
            want(art.toString()).equals(wad(0).toString())

            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const joinPostABal = await gemA.balanceOf(join.address)
            const borrowerPostRicoBal = await RICO.balanceOf(flash_strategist.address)
            const plugPostRicoBal = await RICO.balanceOf(plug.address)
            // Balances for both the borrower and the join should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(joinPreABal.toString()).equals(joinPostABal.toString())
            want(borrowerPreRicoBal.toString()).equals(borrowerPostRicoBal.toString())
            want(plugPreRicoBal.toString()).equals(plugPostRicoBal.toString())
        });
    })
})
