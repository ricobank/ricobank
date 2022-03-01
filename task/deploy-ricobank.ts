import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')

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

    const ball_artifact = require('../artifacts/sol/ball.sol/Ball.json')
    const ball_type = hre.ethers.ContractFactory.fromSolidity(ball_artifact, ali)
    const ball = await ball_type.deploy(deps.objects.gemfab.address, deps.objects.feedbase.address)
    const gem_artifact = await dpack.getIpfsJson(deps.types.Gem.artifact['/'])

    const contracts = [['flow', 'RicoFlowerV1', require('../artifacts/sol/flow.sol/RicoFlowerV1.json')],
                       ['plot', 'Plot', require('../artifacts/sol/plot.sol/Plot.json')],
                       ['plug', 'Plug', require('../artifacts/sol/plug.sol/Plug.json')],
                       ['port', 'Port', require('../artifacts/sol/port.sol/Port.json')],
                       ['vat', 'Vat', require('../artifacts/sol/vat.sol/Vat.json')],
                       ['vow', 'Vow', require('../artifacts/sol/vow.sol/Vow.json')],
                       ['vox', 'Vox', require('../artifacts/sol/vox.sol/Vox.json')],
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
