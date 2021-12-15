import {task} from 'hardhat/config'
import {HardhatRuntimeEnvironment, TaskArguments} from 'hardhat/types'

const balancer = require('@balancer-labs/v2-deployments')

task('deploy-balancer-pool', 'create new balancer pool')
    .setAction(async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const {ethers} = hre
        const [acct] = await hre.ethers.getSigners()
        const deployer = acct.address

        const pool_abi = await balancer.getBalancerContractAbi('20210418-weighted-pool', 'WeightedPool')
        const pool_code = await balancer.getBalancerContractBytecode('20210418-weighted-pool', 'WeightedPool')
        const pool_type = new ethers.ContractFactory(pool_abi, pool_code, acct)

        let tokens = [args.token_a.address, args.token_b.address]
        if (args.token_b.address < args.token_a.address) {
            tokens = [args.token_b.address, args.token_a.address]
        }
        let tx_create = await args.balancer_pack.poolfab.create(
            args.name, args.symbol,
            tokens,
            args.weights,
            args.swapFeePercentage,
            deployer
        )
        const res = await tx_create.wait()
        const event = res.events[res.events.length - 1]
        const pool_addr = event.args.pool
        const pool = pool_type.attach(pool_addr)
        const pool_id = await pool.getPoolId()
        const JOIN_KIND_INIT = 0
        const initUserData = ethers.utils.defaultAbiCoder.encode(
            ['uint256', 'uint256[]'], [JOIN_KIND_INIT, args.amountsIn]
        )
        const joinPoolRequest = {
            assets: tokens,
            maxAmountsIn: args.amountsIn,
            userData: initUserData,
            fromInternalBalance: false
        }
        const tx = await args.balancer_pack.vault.joinPool(pool_id, deployer, deployer, joinPoolRequest)
        await tx.wait()

        return {pool_id: pool_id}
    })
