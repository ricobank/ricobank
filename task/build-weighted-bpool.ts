import { task} from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { BigNumber} from 'ethers'

const dpack = require('@etherpacks/dpack')

task('build-weighted-bpool', 'create new balancer pool')
.setAction(async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
    const {ethers} = hre
    const [acct] = await hre.ethers.getSigners()
    const deployer = acct.address
    const balancer_dapp = await dpack.load(args.balancer_pack, ethers, acct)

    args.token_settings.sort((a, b) =>
        (BigNumber.from(a.token.address).gt(BigNumber.from(b.token.address))) ? 1 : -1)
    const tokens = args.token_settings.map(x => x.token.address)
    const weights = args.token_settings.map(x => x.weight);
    const amountsIn = args.token_settings.map(x => x.amountIn);

    let tx_create = await balancer_dapp.weighted_pool_factory.create(
        args.name, args.symbol,
        tokens,
        weights,
        args.swapFeePercentage,
        deployer
    )
    const res = await tx_create.wait()
    const event = res.events[res.events.length - 1]
    const pool_addr = event.args.pool
    const pool = balancer_dapp._types.WeightedPool.attach(pool_addr)
    const pool_id = await pool.getPoolId()
    const JOIN_KIND_INIT = 0
    const initUserData = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'uint256[]'], [JOIN_KIND_INIT, amountsIn]
    )
    const joinPoolRequest = {
        assets: tokens,
        maxAmountsIn: amountsIn,
        userData: initUserData,
        fromInternalBalance: false
    }
    const tx = await balancer_dapp.vault.joinPool(pool_id, deployer, deployer, joinPoolRequest)
    await tx.wait()

    return {pool_id: pool_id}
})
