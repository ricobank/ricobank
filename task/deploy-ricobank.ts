import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray } from 'minihat'

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const [ali] = await hre.ethers.getSigners()

    if (args.mock && args.dependencies) {
      throw new Error('Panic: don\'t use \'mock\' and \'dependencies\' together')
    }
    let deps
    if (args.dependencies) {
      deps = args.dependencies
    } else if (args.mock) {
      deps = await hre.run('deploy-mock-dependencies')
    } else {
      throw new Error('Panic: must provide either \'mock\' or \'dependencies\'')
    }

    const pb = new dpack.PackBuilder(hre.network.name)

    const ball_artifact = require('../artifacts/src/ball.sol/Ball.json')
    const ball_type = hre.ethers.ContractFactory.fromSolidity(ball_artifact, ali)
    const ballargs = {
        gemfab: deps.objects.gemfab.address,
        feedbase: deps.objects.feedbase.address,
        weth: deps.objects.weth.address,
        factory: deps.objects.uniswapV3Factory.address,
        router: deps.objects.swapRouter.address,
        sqrtpar: ray(1),
        ilks: [b32('weth')],
        gems: [deps.objects.weth.address],
        pools: ["0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8"] // uni wethdai pool
    }
    const ball = await ball_type.deploy(ballargs,
        { gasLimit: 50000000 })
    const gem_artifact = await dpack.getIpfsJson(deps.types.Gem.artifact['/'])

    const contracts = [['flow', 'UniFlower', require('../artifacts/src/flow.sol/UniFlower.json')],
                       ['vat', 'Vat', require('../artifacts/src/vat.sol/Vat.json')],
                       ['vow', 'Vow', require('../artifacts/src/vow.sol/Vow.json')],
                       ['vox', 'Vox', require('../artifacts/src/vox.sol/Vox.json')],
                       ['rico', 'Gem', gem_artifact],
                       ['risk', 'Gem', gem_artifact]]

    for await (const [state_var, typename, artifact] of contracts) {
      const pack_type = typename != 'Gem'
      await pb.packObject({
        objectname: state_var,
        address: await ball[state_var](),
        typename: typename,
        artifact: artifact
      }, pack_type)
    }

    await pb.merge(deps)
    return await pb.build()
  })
