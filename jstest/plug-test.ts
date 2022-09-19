import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
const { hexZeroPad } = ethers.utils
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const dpack = require('@etherpacks/dpack')
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32, 1)  // ilk 0 id
const i1 = Buffer.alloc(32, 2)  // ilk 1 id
const atag = b32('GEMAUSD')
const btag = b32('GEMBUSD')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
}

describe('Plug', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat
    let dock
    let RICO, gemA, gemB
    let gem_type
    let fb
    let flash_strategist, flash_strategist_type
    let strategist_iface

    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        const pack = await hh.run('deploy-ricobank', { mock: 'true' })
        const dapp = await dpack.load(pack, ethers, ali)
        const gem_artifacts = require('../lib/gemfab/artifacts/src/gem.sol/Gem.json')
        gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
        flash_strategist_type = await ethers.getContractFactory('MockFlashStrategist', ali)
        strategist_iface = new ethers.utils.Interface([
            "function approve_all(address[] memory gems, uint256[] memory amts)",
            "function welch(address[] memory gems, uint256[] memory amts)",
            "function failure(address[] memory gems, uint256[] memory amts)",
            "function reenter(address[] memory gems, uint256[] memory amts)",
            "function plug_lever(address gem, uint256 lock_amt, uint256 draw_amt)",
            "function plug_release(address gem, uint256 free_amt, uint256 wipe_amt)",
        ])

        dock = dapp.dock
        vat = dapp.vat
        RICO = dapp.rico
        fb = dapp.feedbase

        gemA = await gem_type.deploy(b32('gemA'), b32('GEMA'))
        gemB = await gem_type.deploy(b32('gemB'), b32('GEMB'))
        flash_strategist = await flash_strategist_type.deploy(dock.address, vat.address, RICO.address, i0)

        await send(RICO.ward, flash_strategist.address, true)
        await send(gemA.ward, flash_strategist.address, true)

        await send(gemA.approve, dock.address, U256_MAX)
        await send(gemB.approve, dock.address, U256_MAX)
        await send(RICO.mint, ALI, wad(1000))
        await send(gemA.mint, ALI, wad(1000))
        await send(gemB.mint, ALI, wad(2000))

        await send(vat.init, i0, gemA.address, ALI, atag)
        await send(vat.init, i1, gemB.address, ALI, btag)
        await send(vat.filk, i0, b32("line"), rad(2000))

        const t1 = await gettime()
        await send(fb.push, atag, bn2b32(ray(1)), t1 + 1000)
        await send(fb.push, btag, bn2b32(ray(1)), t1 + 1000)

        await send(dock.bind_gem, vat.address, i0, gemA.address)
        await send(dock.bind_gem, vat.address, i1, gemB.address)
        await send(dock.list, gemA.address, true)
        await send(dock.list, gemB.address, true)
        await send(dock.join_gem, vat.address, i0, ALI, wad(1000))
        await send(dock.join_gem, vat.address, i1, ALI, wad(500))

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

            await send(dock.exit_gem, vat.address, i0, ALI, wad(100))
            await send(dock.exit_gem, vat.address, i1, ALI, wad(100))

            gemABal = await vat.gem(i0, ALI)
            want(gemABal.eq(wad(900))).true
            aBal = await gemA.balanceOf(ALI)
            want(aBal.eq(wad(100))).true
            gemBBal = await vat.gem(i1, ALI)
            want(gemBBal.eq(wad(400))).true
            bal = await gemB.balanceOf(ALI)
            want(bal.eq(wad(1600))).true

            await fail('ERR_MATH_UIADD_NEG', dock.exit_gem, vat.address, i0, ALI, wad(901))
            await fail('ERR_MATH_UIADD_NEG', dock.exit_gem, vat.address, i1, ALI, wad(401))
        });
    })

    describe('general flash loan', () => {
        beforeEach(async () => {
            // Give strategist a starting balance to test it ends up with fair amount.
            await send(gemA.mint, flash_strategist.address, wad(500))
        })

        it('insufficient approval', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [[gemA.address, gemB.address], [wad(10), wad(10)]])
            await fail('Transaction reverted', dock.flash, gemA.address, wad(400),
                flash_strategist.address, approve_data)
            await fail('Transaction reverted', dock.flash, gemB.address, wad(400),
                flash_strategist.address, approve_data)
        });

        it('request exceeding available quantity', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address, gemB.address], [wad(1e10), wad(1e10)] ])
            await fail('Transaction reverted', dock.flash, gemA.address, wad(1100),
                flash_strategist.address, approve_data)
            await fail('Transaction reverted', dock.flash, gemB.address, wad(600),
                flash_strategist.address, approve_data)
        });

        it('request unsupported token', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address], [wad(1e10)] ])
            await send(dock.list, gemA.address, false)
            await fail('', dock.flash, gemA.address, wad(1),
                flash_strategist.address, approve_data)
            await send(dock.list, gemA.address, true)
            await send(dock.flash, gemA.address, wad(1), flash_strategist.address, approve_data)
        });

        it('revert when borrower fails to repay', async () => {
            let welch_data = strategist_iface.encodeFunctionData("welch",
                [ [gemA.address, gemB.address], [wad(100), wad(100)] ])
            await fail('', dock.flash, gemA.address, wad(100),
                flash_strategist.address, welch_data)
            await fail('', dock.flash, gemB.address, wad(100),
                flash_strategist.address, welch_data)
        });

        it('revert when call within flash is unsuccessful', async () => {
            let failure_data = strategist_iface.encodeFunctionData("failure",
                [ [gemA.address, gemB.address], [wad(0), wad(0)] ])
            // receiver-err
            await fail('', dock.flash, gemA.address, wad(0),
                flash_strategist.address, failure_data)
            await fail('', dock.flash, gemB.address, wad(0),
                flash_strategist.address, failure_data)
        });

        it('revert when call within flash attempts reentry', async () => {
            let reenter_data = strategist_iface.encodeFunctionData("reenter",
                [ [gemA.address, gemB.address], [wad(0), wad(0)] ])
            await fail('', dock.flash, gemA.address, wad(0),
                flash_strategist.address, reenter_data)
            await fail('', dock.flash, gemB.address, wad(0),
                flash_strategist.address, reenter_data)
        });

        it('succeed with sufficient funds and approvals', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(dock.address)
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address, gemB.address], [wad(1e10), wad(1e10)] ])
            await send(dock.flash, gemA.address, wad(400), flash_strategist.address,
                approve_data)
            await send(dock.flash, gemB.address, wad(400), flash_strategist.address,
                approve_data)
            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const plugPostABal = await gemA.balanceOf(dock.address)
            // Balances for both the borrower and the plug should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(plugPreABal.toString()).equals(plugPostABal.toString())
        });

        it('jump wind up and jump release borrow', async () => {
            await send(vat.ward, dock.address, true)
            await send(vat.ward, dock.address, true)
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(dock.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPreRicoBal = await RICO.balanceOf(dock.address)
            const lock_amt = wad(1000)
            const draw_amt = wad(500)
            const lever_data = strategist_iface.encodeFunctionData("plug_lever",
                [ gemA.address, lock_amt, draw_amt])

            await send(dock.flash, gemA.address, draw_amt, flash_strategist.address, lever_data)
            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            // began with 500 gemA, aimed to double it with 500 debt
            want(levered_ink.toString()).equals(lock_amt.toString())
            want(levered_art.toString()).equals(draw_amt.toString())

            let release_data = strategist_iface.encodeFunctionData("plug_release",
                [ gemA.address, lock_amt, draw_amt])
            await send(dock.flash, gemA.address, draw_amt, flash_strategist.address, release_data)
            const [ink, art] = await vat.urns(i0, flash_strategist.address)
            want(ink.toString()).equals(wad(0).toString())
            want(art.toString()).equals(wad(0).toString())

            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const plugPostABal = await gemA.balanceOf(dock.address)
            const borrowerPostRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPostRicoBal = await RICO.balanceOf(dock.address)
            // Balances for both the borrower and the plug should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(plugPreABal.toString()).equals(plugPostABal.toString())
            want(borrowerPreRicoBal.toString()).equals(borrowerPostRicoBal.toString())
            want(portPreRicoBal.toString()).equals(portPostRicoBal.toString())
        });
    })
})
