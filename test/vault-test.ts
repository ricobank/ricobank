import * as hh from 'hardhat'
import { ethers, network } from 'hardhat'
import { fail, N, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const debug = require('debug')('rico:test')

let i0 = Buffer.alloc(32, 1)  // ilk 0 id
let i1 = Buffer.alloc(32, 2)  // ilk 1 id

describe('Vault', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat, vat_type
    let vault, vault_type
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
        vault_type = await ethers.getContractFactory('Vault', ali)
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
        vault = await vault_type.deploy()
        flash_strategist = await flash_strategist_type.deploy(vault.address, vat.address, RICO.address, i0)

        await send(vat.hope, vault.address)
        await send(vat.rely, vault.address)
        await send(RICO.rely, vault.address)
        await send(gemA.rely, vault.address)
        await send(gemB.rely, vault.address)
        await send(RICO.rely, flash_strategist.address)
        await send(gemA.rely, flash_strategist.address)

        await send(RICO.approve, vault.address, U256_MAX)
        await send(gemA.approve, vault.address, U256_MAX)
        await send(gemB.approve, vault.address, U256_MAX)
        await send(RICO.mint, ALI, wad(1000))
        await send(gemA.mint, ALI, wad(1000))
        await send(gemB.mint, ALI, wad(2000))

        await send(vat.init, i0)
        await send(vat.init, i1)
        await send(vat.file, b32("ceil"), rad(1000))
        await send(vat.filk, i0, b32("line"), rad(1000))
        await send(vat.filk, i0, b32("line"), rad(2000))

        await send(vat.plot, i0, ray(1).toString())
        await send(vat.plot, i1, ray(1).toString())

        await send(vault.file_gem, i0, gemA.address)
        await send(vault.file_gem, i1, gemB.address)
        await send(vault.file_vat, vat.address, true)
        await send(vault.file_joy, RICO.address, true)
        await send(vault.gem_join, vat.address, i0, ALI, wad(1000))
        await send(vault.gem_join, vat.address, i1, ALI, wad(500))

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

            await send(vault.gem_exit, vat.address, i0, ALI, wad(100))
            await send(vault.gem_exit, vat.address, i1, ALI, wad(100))

            gemABal = await vat.gem(i0, ALI)
            want(gemABal.eq(wad(900))).true
            aBal = await gemA.balanceOf(ALI)
            want(aBal.eq(wad(100))).true
            gemBBal = await vat.gem(i1, ALI)
            want(gemBBal.eq(wad(400))).true
            bal = await gemB.balanceOf(ALI)
            want(bal.eq(wad(1600))).true

            await fail('ERR_MATH_UIADD_NEG', vault.gem_exit, vat.address, i0, ALI, wad(901))
            await fail('ERR_MATH_UIADD_NEG', vault.gem_exit, vat.address, i1, ALI, wad(401))
        });

        it('joy', async () => {
            const ricoWad = wad(10)
            const initialRico = await RICO.balanceOf(ALI)

            await send(vat.lock, i0, wad(500))
            await send(vat.draw, i0, ricoWad)

            await fail('operation underflowed', vault.joy_exit, vat.address, RICO.address, ALI, wad(11))
            await send(vault.joy_exit, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', vault.joy_exit, vat.address, RICO.address, ALI, wad(1))
            const postExitRico = await RICO.balanceOf(ALI)

            want(postExitRico.sub(initialRico).toString()).equals(ricoWad.toString())

            await fail('operation underflowed', vault.joy_join, vat.address, RICO.address, ALI, wad(11))
            await send(vault.joy_join, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', vault.joy_join, vat.address, RICO.address, ALI, wad(1))
            const postJoinRico = await RICO.balanceOf(ALI)

            want(postJoinRico.toString()).equals(initialRico.toString())
        });
        
        describe('when frozen', () => {
            beforeEach(async () => {
                await send(vat.lock, i0, wad(500))
                await send(vat.draw, i0, wad(10))
                await send(vault.joy_exit, vat.address, RICO.address, ALI, wad(1))
                await send(vault.cage)
            })

            it('additional joy must not leave system', async () => {
                await fail('not-live', vault.joy_exit, vat.address, RICO.address, ALI, wad(1))
            });

            it('joy can be returned', async () => {
                await send(vault.joy_join, vat.address, RICO.address, ALI, wad(1))
            });

            it('excess collateral can be withdrawn', async () => {
                await send(vault.gem_exit, vat.address, i0, ALI, wad(1))
            });

            it('no more collateral should be deposited', async () => {
                await fail('not-live', vault.gem_join, vat.address, i0, ALI, wad(1))
            });
        })
    })

    describe('flash loan', () => {
        beforeEach(async () => {
            // Give strategist a starting balance to test it ends up with fair amount.
            await send(gemA.mint, flash_strategist.address, wad(500))
        })

        it('insufficient approval', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(10), wad(10)] ])
            await fail('Transaction reverted', vault.flash, [gemA.address, gemB.address], [wad(400), wad(400)],
                flash_strategist.address, approve_data)
        });

        it('request exceeding available quantity', async () => {
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(1e10), wad(1e10)] ])
            await fail('Transaction reverted', vault.flash, [gemA.address, gemB.address], [wad(1100), wad(600)],
                flash_strategist.address, approve_data)
        });

        it('revert when borrower fails to repay', async () => {
            let welch_data = strategist_iface.encodeFunctionData("welch", [ [gemA.address, gemB.address],
                [wad(100), wad(100)] ])
            await fail('Transaction reverted', vault.flash, [gemA.address, gemB.address], [wad(100), wad(100)],
                flash_strategist.address, welch_data)
        });

        it('revert when call within flash is unsuccessful', async () => {
            let failure_data = strategist_iface.encodeFunctionData("failure", [ [gemA.address, gemB.address],
                [wad(0), wad(0)] ])
            await fail('receiver-err', vault.flash, [gemA.address, gemB.address], [wad(0), wad(0)],
                flash_strategist.address, failure_data)
        });

        it('succeed with sufficient funds and approvals', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const vaultPreABal = await gemA.balanceOf(vault.address)
            let approve_data = strategist_iface.encodeFunctionData("approve_all", [ [gemA.address, gemB.address],
                [wad(1e10), wad(1e10)] ])
            await send(vault.flash, [gemA.address, gemB.address], [wad(400), wad(400)], flash_strategist.address,
                approve_data)
            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const vaultPostABal = await gemA.balanceOf(vault.address)
            // Balances for both the borrower and the vault should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(vaultPreABal.toString()).equals(vaultPostABal.toString())
        });

        it('jump wind up and jump release borrow', async () => {
            const borrowerPreABal = await gemA.balanceOf(flash_strategist.address)
            const vaultPreABal = await gemA.balanceOf(vault.address)
            const borrowerPreRicoBal = await RICO.balanceOf(flash_strategist.address)
            const vaultPreRicoBal = await RICO.balanceOf(vault.address)

            let lever_data = strategist_iface.encodeFunctionData("fast_lever", [ gemA.address, wad(1000), wad(500)])
            await send(vault.flash, [gemA.address], [wad(500)], flash_strategist.address, lever_data)
            const [levered_ink, levered_art] = await vat.urns(i0, flash_strategist.address)
            // began with 500 gemA, aimed to double it with 500 debt
            want(levered_ink.toString()).equals(wad(1000).toString())
            want(levered_art.toString()).equals(wad(500).toString())

            let release_data = strategist_iface.encodeFunctionData("fast_release", [ gemA.address, wad(1000), wad(500)])
            await send(vault.flash, [gemA.address], [wad(500)], flash_strategist.address, release_data)
            const [ink, art] = await vat.urns(i0, flash_strategist.address)
            want(ink.toString()).equals(wad(0).toString())
            want(art.toString()).equals(wad(0).toString())

            const borrowerPostABal = await gemA.balanceOf(flash_strategist.address)
            const vaultPostABal = await gemA.balanceOf(vault.address)
            const borrowerPostRicoBal = await RICO.balanceOf(flash_strategist.address)
            const vaultPostRicoBal = await RICO.balanceOf(vault.address)
            // Balances for both the borrower and the vault should be unchanged after the loan is complete.
            want(borrowerPreABal.toString()).equals(borrowerPostABal.toString())
            want(vaultPreABal.toString()).equals(vaultPostABal.toString())
            want(borrowerPreRicoBal.toString()).equals(borrowerPostRicoBal.toString())
            want(vaultPreRicoBal.toString()).equals(vaultPostRicoBal.toString())
        });
    })
})
