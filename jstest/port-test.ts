import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
const { hexZeroPad } = ethers.utils
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const dpack = require('@etherpacks/dpack')
const debug = require('debug')('rico:test')

const i0 = Buffer.alloc(32, 1)  // ilk 0 id
const atag = b32('GEMAUSD')
const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const gettime = async () => {
    const blocknum = await ethers.provider.getBlockNumber()
    return (await ethers.provider.getBlock(blocknum)).timestamp
}

describe('Port', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat
    let dock
    let RICO, gemA
    let gem_type
    let fb
    let flash_strategist, flash_strategist_type
    let strategist_iface
    let FLASH

    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        const pack = await hh.run('deploy-ricobank', { mock: 'true' })
        const dapp = await dpack.load(pack, ethers, ali)
        const gem_artifacts = require('../lib/gemfab/artifacts/src/gem.sol/Gem.json')
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

        dock = dapp.dock
        vat = dapp.vat
        RICO = dapp.rico
        fb = dapp.feedbase
        gemA = await gem_type.deploy(b32('gemA'), b32('GEMA'))
        flash_strategist = await flash_strategist_type.deploy(dock.address, vat.address, RICO.address, i0)

        await send(RICO.ward, flash_strategist.address, true)
        await send(gemA.ward, flash_strategist.address, true)
        await send(vat.ward, dock.address, true)
        await send(gemA.approve, dock.address, U256_MAX)
        await send(RICO.mint, ALI, wad(10))
        await send(gemA.mint, ALI, wad(1000))
        await send(vat.init, i0, gemA.address, ALI, atag)
        await send(vat.filk, i0, b32("line"), rad(2000))
        const t1 = await gettime()
        await send(fb.push, atag, bn2b32(ray(1)), t1 + 1000)
        await send(dock.bind_gem, vat.address, i0, gemA.address)
        await send(dock.join_gem, vat.address, i0, ALI, wad(1000))
        await send(dock.list, gemA.address, true)
        FLASH = await dock.MINT()

        await snapshot(hh);
    })
    beforeEach(async () => {
        await revert(hh);
    })

    describe('join and exit', () => {
        it('joy', async () => {
            const ricoWad = wad(10)
            const initialRico = await RICO.balanceOf(ALI)

            await send(vat.frob, i0, ALI, wad(500), wad(0)) // await send(vat.lock, i0, wad(500))
            await send(vat.frob, i0, ALI, wad(0), ricoWad)// await send(vat.draw, i0, ricoWad)

            await fail('operation underflowed', dock.exit_rico, vat.address, RICO.address, ALI, wad(11))
            await send(dock.exit_rico, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', dock.exit_rico, vat.address, RICO.address, ALI, wad(1))
            const postExitRico = await RICO.balanceOf(ALI)

            want(postExitRico.sub(initialRico).toString()).equals(ricoWad.toString())

            await fail('operation underflowed', dock.join_rico, vat.address, RICO.address, ALI, wad(11))
            await send(dock.join_rico, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', dock.join_rico, vat.address, RICO.address, ALI, wad(1))
            const postJoinRico = await RICO.balanceOf(ALI)

            want(postJoinRico.toString()).equals(initialRico.toString())
        });
    })

    describe('flash mint', () => {
        it('succeed simple flash mint', async () => {
            const borrowerPreBal = await RICO.balanceOf(flash_strategist.address)
            const portPreBal = await RICO.balanceOf(dock.address)
            const preTotalSupply = await RICO.totalSupply()

            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await send(dock.flash, RICO.address, FLASH, flash_strategist.address, nop_data)

            const borrowerPostBal = await RICO.balanceOf(flash_strategist.address)
            const portPostBal = await RICO.balanceOf(dock.address)
            const postTotalSupply = await RICO.totalSupply()

            want(borrowerPreBal.toString()).equals(borrowerPostBal.toString())
            want(portPreBal.toString()).equals(portPostBal.toString())
            want(preTotalSupply.toString()).equals(postTotalSupply.toString())
        });

        it('revert when exceeding max supply', async () => {
            await send(RICO.mint, ALI, U256_MAX.sub(FLASH))
            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await fail('Transaction reverted', dock.flash, RICO.address, FLASH, flash_strategist.address, nop_data)
        });

        it('revert on repayment failure', async () => {
            const welch_data = strategist_iface.encodeFunctionData("welch",
                [ [RICO.address], [0] ])
            await fail('Transaction reverted', dock.flash, RICO.address, FLASH, flash_strategist.address, welch_data)
        });

        it('revert on wrong joy', async () => {
            const nop_data = strategist_iface.encodeFunctionData("nop", [])
            await fail('Transaction reverted', dock.flash, gemA.address, FLASH, flash_strategist.address, nop_data)
        });

        it('revert on handler error', async () => {
            const failure_data = strategist_iface.encodeFunctionData("failure", [ [], [] ])
            await fail('Transaction reverted', dock.flash, gemA.address, FLASH, flash_strategist.address, failure_data)
        });

        it('jump wind up and jump release borrow', async () => {
            await send(vat.ward, dock.address, true)
            await send(vat.ward, dock.address, true)
            await send(gemA.mint, flash_strategist.address, wad(100))

            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const plugPreABal = await gemA.balanceOf(dock.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const portPreRicoBal = await RICO.balanceOf(dock.address)
            const lock_amt = wad(300)
            const draw_amt = wad(200)

            const lever_data = strategist_iface.encodeFunctionData("port_lever",
                [ gemA.address, lock_amt, draw_amt])
            await send(dock.flash, RICO.address, FLASH, flash_strategist.address, lever_data)

            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            want(levered_ink.toString()).equals(lock_amt.toString())
            want(levered_art.toString()).equals(draw_amt.toString())

            let release_data = strategist_iface.encodeFunctionData("port_release",
                [ gemA.address, lock_amt, draw_amt])
            await send(dock.flash, RICO.address, FLASH, flash_strategist.address, release_data)

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
