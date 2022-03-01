import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const dpack = require('@etherpacks/dpack')

let i0 = Buffer.alloc(32, 1)  // ilk 0 id
let i1 = Buffer.alloc(32, 2)  // ilk 1 id

describe('Plug', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat
    let plug
    let port
    let RICO, gemA, gemB
    let gem_type
    let flash_strategist, flash_strategist_type
    let strategist_iface

    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        const pack = await hh.run('deploy-ricobank', { mock: 'true' })
        const dapp = await dpack.load(pack, ethers)
        const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
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

        plug = dapp.plug
        port = dapp.port
        vat = dapp.vat
        RICO = dapp.rico

        gemA = await gem_type.deploy('gemA', 'GEMA')
        gemB = await gem_type.deploy('gemB', 'GEMB')
        flash_strategist = await flash_strategist_type.deploy(plug.address, port.address, vat.address, RICO.address, i0)

        await send(RICO.ward, flash_strategist.address, true)
        await send(gemA.ward, flash_strategist.address, true)

        await send(gemA.approve, plug.address, U256_MAX)
        await send(gemB.approve, plug.address, U256_MAX)
        await send(RICO.mint, ALI, wad(1000))
        await send(gemA.mint, ALI, wad(1000))
        await send(gemB.mint, ALI, wad(2000))

        await send(vat.init, i0)
        await send(vat.init, i1)
        await send(vat.filk, i0, b32("line"), rad(2000))

        await send(vat.plot, i0, ray(1).toString())
        await send(vat.plot, i1, ray(1).toString())

        await send(plug.bind, vat.address, i0, gemA.address, true)
        await send(plug.bind, vat.address, i1, gemB.address, true)
        await send(plug.list, gemA.address, true)
        await send(plug.list, gemB.address, true)
        await send(port.bind, vat.address, RICO.address, true)
        await send(plug.join, vat.address, i0, gemA.address, ALI, wad(1000))
        await send(plug.join, vat.address, i1, gemB.address, ALI, wad(500))

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

            await send(plug.exit, vat.address, i0, gemA.address, ALI, wad(100))
            await send(plug.exit, vat.address, i1, gemB.address, ALI, wad(100))

            gemABal = await vat.gem(i0, ALI)
            want(gemABal.eq(wad(900))).true
            aBal = await gemA.balanceOf(ALI)
            want(aBal.eq(wad(100))).true
            gemBBal = await vat.gem(i1, ALI)
            want(gemBBal.eq(wad(400))).true
            bal = await gemB.balanceOf(ALI)
            want(bal.eq(wad(1600))).true

            await fail('ERR_MATH_UIADD_NEG', plug.exit, vat.address, i0, gemA.address, ALI, wad(901))
            await fail('ERR_MATH_UIADD_NEG', plug.exit, vat.address, i1, gemB.address, ALI, wad(401))
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
            await fail('Transaction reverted', plug.flash, [gemA.address, gemB.address], [wad(400), wad(400)],
                flash_strategist.address, approve_data)
        });

        it('request exceeding available quantity', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address, gemB.address], [wad(1e10), wad(1e10)] ])
            await fail('Transaction reverted', plug.flash, [gemA.address, gemB.address], [wad(1100), wad(600)],
                flash_strategist.address, approve_data)
        });

        it('request unsupported token', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address], [wad(1e10)] ])
            await send(plug.list, gemA.address, false)
            await fail('unsupported-token', plug.flash, [gemA.address], [wad(1)],
                flash_strategist.address, approve_data)
            await send(plug.list, gemA.address, true)
            await send(plug.flash, [gemA.address], [wad(1)], flash_strategist.address, approve_data)
        });

        it('revert when borrower fails to repay', async () => {
            let welch_data = strategist_iface.encodeFunctionData("welch",
                [ [gemA.address, gemB.address], [wad(100), wad(100)] ])
            await fail('Transaction reverted', plug.flash, [gemA.address, gemB.address], [wad(100), wad(100)],
                flash_strategist.address, welch_data)
        });

        it('revert when call within flash is unsuccessful', async () => {
            let failure_data = strategist_iface.encodeFunctionData("failure",
                [ [gemA.address, gemB.address], [wad(0), wad(0)] ])
            await fail('receiver-err', plug.flash, [gemA.address, gemB.address], [wad(0), wad(0)],
                flash_strategist.address, failure_data)
        });

        it('revert when call within flash attempts reentry', async () => {
            let reenter_data = strategist_iface.encodeFunctionData("reenter",
                [ [gemA.address, gemB.address], [wad(0), wad(0)] ])
            await fail('receiver-err', plug.flash, [gemA.address, gemB.address], [wad(0), wad(0)],
                flash_strategist.address, reenter_data)
        });

        it('succeed with sufficient funds and approvals', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(plug.address)
            let approve_data = strategist_iface.encodeFunctionData("approve_all",
                [ [gemA.address, gemB.address], [wad(1e10), wad(1e10)] ])
            await send(plug.flash, [gemA.address, gemB.address], [wad(400), wad(400)], flash_strategist.address,
                approve_data)
            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const plugPostABal = await gemA.balanceOf(plug.address)
            // Balances for both the borrower and the plug should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(plugPreABal.toString()).equals(plugPostABal.toString())
        });

        it('jump wind up and jump release borrow', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(plug.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPreRicoBal = await RICO.balanceOf(port.address)
            const lock_amt = wad(1000)
            const draw_amt = wad(500)
            const lever_data = strategist_iface.encodeFunctionData("plug_lever",
                [ gemA.address, lock_amt, draw_amt])

            await send(plug.flash, [gemA.address], [draw_amt], flash_strategist.address, lever_data)
            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            // began with 500 gemA, aimed to double it with 500 debt
            want(levered_ink.toString()).equals(lock_amt.toString())
            want(levered_art.toString()).equals(draw_amt.toString())

            let release_data = strategist_iface.encodeFunctionData("plug_release",
                [ gemA.address, lock_amt, draw_amt])
            await send(plug.flash, [gemA.address], [draw_amt], flash_strategist.address, release_data)
            const [ink, art] = await vat.urns(i0, flash_strategist.address)
            want(ink.toString()).equals(wad(0).toString())
            want(art.toString()).equals(wad(0).toString())

            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const plugPostABal = await gemA.balanceOf(plug.address)
            const borrowerPostRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPostRicoBal = await RICO.balanceOf(port.address)
            // Balances for both the borrower and the plug should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(plugPreABal.toString()).equals(plugPostABal.toString())
            want(borrowerPreRicoBal.toString()).equals(borrowerPostRicoBal.toString())
            want(portPreRicoBal.toString()).equals(portPostRicoBal.toString())
        });
    })
})
