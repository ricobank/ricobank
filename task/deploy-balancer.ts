import {task} from 'hardhat/config'
import {HardhatRuntimeEnvironment, TaskArguments} from 'hardhat/types'

import {wad, send, U256_MAX} from 'minihat'

const balancer = require('@balancer-labs/v2-deployments')

task('deploy-balancer', 'deploys balancer vault')
    .setAction(async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const {ethers} = hre
        const [acct] = await hre.ethers.getSigners()
        const deployer = acct.address

        let vault
        let vault_type
        let poolfab
        let poolfab_type
        let pool
        let pool_type
        let poolId_weth_rico
        let poolId_risk_rico
        let RICO = args.RICO
        let RISK = args.RISK
        let WETH = args.WETH

        const vault_abi = await balancer.getBalancerContractAbi('20210418-vault', 'Vault')
        const vault_code = await balancer.getBalancerContractBytecode('20210418-vault', 'Vault')
        const pool_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPool')
        const pool_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPool')
        const poolfab_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPoolFactory')
        const poolfab_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPoolFactory')
        vault_type = new ethers.ContractFactory(vault_abi, vault_code, acct)
        poolfab_type = new ethers.ContractFactory(poolfab_abi, poolfab_code, acct)
        pool_type = new ethers.ContractFactory(pool_abi, pool_code, acct)

        vault = await vault_type.deploy(deployer, WETH.address, 1000, 1000)
        poolfab = await poolfab_type.deploy(vault.address)

        await send(WETH.approve, vault.address, U256_MAX)
        await send(RICO.approve, vault.address, U256_MAX)
        await send(RISK.approve, vault.address, U256_MAX)

        // create and add liquidity to weth-rico balancer pool
        let tokens = [WETH.address, RICO.address]
        if (RICO.address < WETH.address) {
            tokens = [RICO.address, WETH.address]
        }
        let tx_create = await poolfab.create(
            'mock', 'MOCK',
            tokens,
            [wad(0.5), wad(0.5)],
            wad(0.01),
            deployer
        )
        let res = await tx_create.wait()
        let event = res.events[res.events.length - 1]
        let pool_addr = event.args.pool
        pool = pool_type.attach(pool_addr)
        poolId_weth_rico = await pool.getPoolId()
        let JOIN_KIND_INIT = 0
        let initUserData = ethers.utils.defaultAbiCoder.encode(
            ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(2000), wad(2000)]]
        )
        let joinPoolRequest = {
            assets: tokens,
            maxAmountsIn: [wad(2000), wad(2000)],
            userData: initUserData,
            fromInternalBalance: false
        }
        let tx = await vault.joinPool(poolId_weth_rico, deployer, deployer, joinPoolRequest)
        await tx.wait()

        // create and add liquidity to risk-rico balancer pool
        tokens = [RICO.address, RISK.address]
        if (RISK.address < RICO.address) {
            tokens = [RISK.address, RICO.address]
        }
        tx_create = await poolfab.create(
            'mock', 'MOCK',
            tokens,
            [wad(0.5), wad(0.5)],
            wad(0.01),
            deployer
        )
        res = await tx_create.wait()
        event = res.events[res.events.length - 1]
        pool_addr = event.args.pool
        pool = pool_type.attach(pool_addr)
        poolId_risk_rico = await pool.getPoolId()
        JOIN_KIND_INIT = 0
        initUserData = ethers.utils.defaultAbiCoder.encode(
            ['uint256', 'uint256[]'], [JOIN_KIND_INIT, [wad(1000), wad(1000)]]
        )
        joinPoolRequest = {
            assets: tokens,
            maxAmountsIn: [wad(1000), wad(1000)],
            userData: initUserData,
            fromInternalBalance: false
        }
        tx = await vault.joinPool(poolId_risk_rico, deployer, deployer, joinPoolRequest)
        await tx.wait()
        return {vault: vault, poolId_weth_rico: poolId_weth_rico, poolId_risk_rico: poolId_risk_rico}
    })
