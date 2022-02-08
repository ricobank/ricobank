import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const dpack = require('dpack')

let i0 = Buffer.alloc(32, 1)  // ilk 0 id

describe('Port', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat
    let plug
    let port
    let RICO, gemA
    let gem_type
    let flash_strategist, flash_strategist_type
    let strategist_iface

    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        const pack = await hh.run('deploy-ricobank', { mock: 'true' })
        const dapp = await dpack.Dapp.loadFromPack(pack, ali, ethers)
        const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
        gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
        flash_strategist_type = await ethers.getContractFactory('MockFlashStrategist', ali)
        strategist_iface = new ethers.utils.Interface([
            "function nop()",
            "function approve_all(address[] memory gems, uint256[] memory amts)",
            "function welch(address[] memory gems, uint256[] memory amts)",
            "function failure(address[] memory gems, uint256[] memory amts)",
            "function reenter(address[] memory gems, uint256[] memory amts)",
            "function port_lever(address gem, uint256 lock_amt, uint256 draw_amt)",
            "function port_release(address gem, uint256 free_amt, uint256 wipe_amt)",
        ])

        plug = dapp.objects.plug
        port = dapp.objects.port
        vat = dapp.objects.vat
        RICO = dapp.objects.rico
        gemA = await gem_type.deploy('gemA', 'GEMA')
        flash_strategist = await flash_strategist_type.deploy(plug.address, port.address, vat.address, RICO.address, i0)

        await send(vat.ward, plug.address, true)
        await send(RICO.ward, port.address, true)
        await send(RICO.ward, flash_strategist.address, true)
        await send(gemA.ward, flash_strategist.address, true)
        await send(vat.trust, port.address, true)
        await send(gemA.approve, plug.address, U256_MAX)
        await send(RICO.mint, ALI, wad(10))
        await send(gemA.mint, ALI, wad(1000))
        await send(vat.init, i0)
        await send(vat.file, b32("ceil"), rad(1000))
        await send(vat.filk, i0, b32("line"), rad(2000))
        await send(vat.plot, i0, ray(1).toString())
        await send(plug.bind, vat.address, i0, gemA.address)
        await send(port.bind, vat.address, RICO.address, true)
        await send(plug.join, vat.address, i0, ALI, wad(1000))

        await snapshot(hh);
    })
    beforeEach(async () => {
        await revert(hh);
    })

    describe('join and exit', () => {
        it('joy', async () => {
            const ricoWad = wad(10)
            const initialRico = await RICO.balanceOf(ALI)

            await send(vat.lock, i0, wad(500))
            await send(vat.draw, i0, ricoWad)

            await fail('operation underflowed', port.exit, vat.address, RICO.address, ALI, wad(11))
            await send(port.exit, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', port.exit, vat.address, RICO.address, ALI, wad(1))
            const postExitRico = await RICO.balanceOf(ALI)

            want(postExitRico.sub(initialRico).toString()).equals(ricoWad.toString())

            await fail('operation underflowed', port.join, vat.address, RICO.address, ALI, wad(11))
            await send(port.join, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', port.join, vat.address, RICO.address, ALI, wad(1))
            const postJoinRico = await RICO.balanceOf(ALI)

            want(postJoinRico.toString()).equals(initialRico.toString())
        });
    })

    describe('flash mint', () => {
        it('succeed simple flash mint', async () => {
            const borrowerPreBal = await RICO.balanceOf(flash_strategist.address)
            const portPreBal = await RICO.balanceOf(port.address)
            const preTotalSupply = await RICO.totalSupply()

            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await send(port.flash, RICO.address, flash_strategist.address, nop_data)

            const borrowerPostBal = await RICO.balanceOf(flash_strategist.address)
            const portPostBal = await RICO.balanceOf(port.address)
            const postTotalSupply = await RICO.totalSupply()

            want(borrowerPreBal.toString()).equals(borrowerPostBal.toString())
            want(portPreBal.toString()).equals(portPostBal.toString())
            want(preTotalSupply.toString()).equals(postTotalSupply.toString())
        });

        it('revert when exceeding max supply', async () => {
            const FLASH = await port.FLASH()
            await send(RICO.mint, ALI, U256_MAX.sub(FLASH))
            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await fail('Transaction reverted', port.flash, RICO.address, flash_strategist.address, nop_data)
        });

        it('revert on repayment failure', async () => {
            const welch_data = strategist_iface.encodeFunctionData("welch",
                [ [RICO.address], [0] ])
            await fail('Transaction reverted', port.flash, RICO.address, flash_strategist.address, welch_data)
        });

        it('revert on wrong joy', async () => {
            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await fail('Transaction reverted', port.flash, gemA.address, flash_strategist.address, nop_data)
        });

        it('revert on handler error', async () => {
            const failure_data = strategist_iface.encodeFunctionData("failure", [ [], [] ])
            await fail('Transaction reverted', port.flash, gemA.address, flash_strategist.address, failure_data)
        });

        it('jump wind up and jump release borrow', async () => {
            await send(gemA.mint, flash_strategist.address, wad(100))

            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(plug.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPreRicoBal = await RICO.balanceOf(port.address)
            const lock_amt = wad(300)
            const draw_amt = wad(200)

            const lever_data = strategist_iface.encodeFunctionData("port_lever",
                [ gemA.address, lock_amt, draw_amt])
            await send(port.flash, RICO.address, flash_strategist.address, lever_data)

            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            want(levered_ink.toString()).equals(lock_amt.toString())
            want(levered_art.toString()).equals(draw_amt.toString())

            let release_data = strategist_iface.encodeFunctionData("port_release",
                [ gemA.address, lock_amt, draw_amt])
            await send(port.flash, RICO.address, flash_strategist.address, release_data)

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
