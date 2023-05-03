import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'

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
      deps = JSON.parse(args.dependencies)
    } else if (args.mock) {
      deps = await hre.run('deploy-mock-dependencies')
    } else {
      throw new Error('Panic: must provide either \'mock\' or \'dependencies\'')
    }

    const pb = new dpack.PackBuilder(hre.network.name)

    const ball_artifact = require('../artifacts/src/ball.sol/Ball.json')
    const ball_type = hre.ethers.ContractFactory.fromSolidity(ball_artifact, ali)
    const timestamp = (await hre.ethers.provider.getBlock('latest')).timestamp
    const ballargs = {
        feedbase: deps.objects.feedbase.address,
        rico: deps.objects.rico.address,
        risk: deps.objects.risk.address,
        ricodai: deps.objects.ricodai.address,
        ricorisk: deps.objects.ricorisk.address,
        router: deps.objects.swapRouter.address,
        roll: ali.address,
        par: ray(1),
        ceil: wad(100000),
        adaptrange:   20000,
        adaptttl:     BANKYEAR / 4,
        daiusdttl:    BANKYEAR,
        xauusdttl:    BANKYEAR,
        twaprange:    10000,
        twapttl:      BANKYEAR,
        ricoramp: {
            fade : ray(0.999), tiny: wad(100), fuel: ray(1000), gain: ray(2),
            feed: deps.objects.feedbase.address,
            fsrc: hre.ethers.constants.AddressZero,
            ftag: hre.ethers.constants.HashZero
        },
        riskramp: {
            fade : ray(0.999), tiny: wad(100), fuel: ray(1000), gain: ray(2),
            feed: deps.objects.feedbase.address,
            fsrc: hre.ethers.constants.AddressZero,
            ftag: hre.ethers.constants.HashZero
        },
        mintramp:   { vel: wad(1), rel: wad(1), bel: timestamp, cel: 1 },
        ups: {
            nfpm: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            ilk: b32(':uninft'),
            fee: hre.ethers.BigNumber.from("1000000001546067052200000000"),
            gain: ray(2),
            fuel: ray(1000),
            fade: ray(0.999),
            chop: ray(1),
            room: 8
        }
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
            fade : ray(0.999), tiny: wad(0), fuel: ray(900), gain: ray(2),
            feed: deps.objects.feedbase.address,
            fsrc: hre.ethers.constants.AddressZero,
            ftag: hre.ethers.constants.HashZero
        },
        ttl: 20000,
        range: BANKYEAR / 4
    }

    const ball = await ball_type.deploy(ballargs, [ilk], { gasLimit: 50000000 })
    const vat_addr = await ball.vat()
    const vow_addr = await ball.vow()
    const deps_dapp = await dpack.load(deps, hre.ethers, ali)
    await send(deps_dapp.rico.ward, vat_addr, 1)
    await send(deps_dapp.risk.ward, vow_addr, 1)

    const mdn_artifact = await dpack.getIpfsJson(deps.types.Medianizer.artifact['/'])
    const div_artifact = await dpack.getIpfsJson(deps.types.Divider.artifact['/'])

    const contracts = [['flow', 'DutchFlower', require('../artifacts/src/flow.sol/DutchFlower.json')],
                       ['vat', 'Vat', require('../artifacts/src/vat.sol/Vat.json')],
                       ['vow', 'Vow', require('../artifacts/src/vow.sol/Vow.json')],
                       ['vox', 'Vox', require('../artifacts/src/vox.sol/Vox.json')],
                       ['mdn', 'Medianizer', mdn_artifact],
                       ['divider', 'Divider', div_artifact]]

    for await (const [state_var, typename, artifact] of contracts) {
      const pack_type = ['Gem', 'Divider', 'Medianizer'].indexOf(typename) == -1
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
