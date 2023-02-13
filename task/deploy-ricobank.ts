import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, wad, BANKYEAR } from 'minihat'

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
    const timestamp = (await hre.ethers.provider.getBlock('latest')).timestamp
    const stdramp = {
        vel: wad(1), rel: wad(1), bel: timestamp,
        cel: 1, del: wad(0.01)
    }
    const ballargs = {
        gemfab: deps.objects.gemfab.address,
        feedbase: deps.objects.feedbase.address,
        weth: deps.objects.weth.address,
        factory: deps.objects.uniswapV3Factory.address,
        router: deps.objects.swapRouter.address,
        sqrtpar: ray(1),
        ceil: rad(100000),
        ricodairange: 20000,
        ricodaittl:   BANKYEAR / 4,
        daiusdttl:    BANKYEAR,
        xauusdttl:    BANKYEAR,
        twaprange:    10000,
        twapttl:      BANKYEAR,
        progstart:    timestamp,
        progend:      timestamp + BANKYEAR * 10,
        progperiod:   BANKYEAR / 12,
        ricoramp:     stdramp,
        riskramp:     stdramp,
        mintramp:     stdramp
    }

    const ilk = {
        ilk: b32('weth'),
        gem: deps.objects.weth.address,
        pool: "0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8",
        chop: rad(1),
        dust: rad(90),
        fee: hre.ethers.BigNumber.from("1000000001546067052200000000"),
        line: rad(100000),
        liqr: ray(1),
        ramp: {
            vel: wad(0.001), rel: wad(1), bel: timestamp,
            cel: 1, del: wad(0.01)
        },
        ttl: 20000,
        range: BANKYEAR / 4
    }
    const ball = await ball_type.deploy(
        ballargs, [ilk], { gasLimit: 50000000 }
    )
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
