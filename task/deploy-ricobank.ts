import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'

task('deploy-ricobank', '')
  .addOptionalParam('mock', 'Ignore dependency args and deploy new mock dependencies')
  .addOptionalParam('dependencies', 'Pack with all required dependencies')
  .addOptionalParam('arb', 'Arbitrum deploy')
  .addOptionalParam('tokens', 'JSON file with token addresses')
  .addOptionalParam('writepack', 'write pack to pack dir')
  .addOptionalParam('gasLimit', 'per-tx gas limit')
  .addParam('netname', 'network name to load packs from')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const [ali] = await hre.ethers.getSigners()

    if (args.mock && args.dependencies) {
      throw new Error('Panic: don\'t use \'mock\' and \'dependencies\' together')
    }
    let deps
    if (args.dependencies) {
        try {
            deps = JSON.parse(args.dependencies);
        } catch (e) {
            // allow deps to be passed as ipfs CID
            deps = await dpack.getIpfsJson(args.dependencies);
        }
    } else if (args.mock) {
      deps = await hre.run('deploy-mock-dependencies', { tokens: args.tokens, netname: args.netname})
    } else {
      throw new Error('Panic: must provide either \'mock\' or \'dependencies\'')
    }

    const pb = new dpack.PackBuilder(hre.network.name)

    const agg_artifact = require('../lib/feedbase/artifacts/src/test/MockChainlinkAggregator.sol/MockChainlinkAggregator.json')
    const agg_type = hre.ethers.ContractFactory.fromSolidity(agg_artifact, ali)
    const agg_daiusd = await agg_type.deploy(deps.objects.feedbase.address, ali.address, b32('dai:usd'), 8, {gasLimit: args.gasLimit})
    const agg_xauusd = await agg_type.deploy(deps.objects.feedbase.address, ali.address, b32('xau:usd'), 8, {gasLimit: args.gasLimit})
    let fb = await hre.ethers.getContractAt('Feedbase', deps.objects.feedbase.address);
    let timestamp = (await hre.ethers.provider.getBlock('latest')).timestamp
    const bn2b32 = (bn) => hre.ethers.utils.hexZeroPad(bn.toHexString(), 32)
    await send(fb.push, b32('dai:usd'), bn2b32(hre.ethers.BigNumber.from('100000000')), timestamp * 2);
    await send(fb.push, b32('xau:usd'), bn2b32(hre.ethers.BigNumber.from('190000000000')), timestamp * 2);

    const diamond_artifact = require('../artifacts/src/diamond.sol/BankDiamond.json')
    const diamond_type = hre.ethers.ContractFactory.fromSolidity(diamond_artifact, ali)
    debug('deploying diamond')
    const diamond = await diamond_type.deploy({gasLimit: args.gasLimit})
    const ball_artifact = require('../artifacts/src/ball.sol/Ball.json')
    const ball_type = hre.ethers.ContractFactory.fromSolidity(ball_artifact, ali)
    timestamp = (await hre.ethers.provider.getBlock('latest')).timestamp

    debug('deploying erc20 hook')
    const tokhook_artifact = require('../artifacts/src/hook/erc20/ERC20Hook.sol/ERC20Hook.json')
    const tokhook_type = hre.ethers.ContractFactory.fromSolidity(tokhook_artifact, ali)
    const tokhook = await tokhook_type.deploy({gasLimit: args.gasLimit})

    debug('deploying uni hook')
    const unihook_artifact = require('../artifacts/src/hook/nfpm/UniV3NFTHook.sol/UniNFTHook.json')
    const unihook_type = hre.ethers.ContractFactory.fromSolidity(unihook_artifact, ali)
    const unihook = await unihook_type.deploy(deps.objects.nonfungiblePositionManager.address, {gasLimit: args.gasLimit})

    const ups = {
            ilk: b32(':uninft'),
            fee: hre.ethers.BigNumber.from("1000000001546067052200000000"),
            chop: ray(1),
            dust: rad(0.1),
            line: rad(10000),
            room: 8,
            uniwrapper: deps.objects.uniwrapper.address
    }

    const ballargs = {
        bank: diamond.address,
        feedbase: deps.objects.feedbase.address,
        uniadapt: deps.objects.uniswapv3adapter.address,
        divider: deps.objects.divider.address,
        multiplier: deps.objects.multiplier.address,
        cladapt: deps.objects.chainlinkadapter.address,
        tokhook: tokhook.address,
        unihook: unihook.address,
        rico: deps.objects.rico.address,
        risk: deps.objects.risk.address,
        ricodai: deps.objects.ricodai.address,
        ricorisk: deps.objects.ricorisk.address,
        dai: deps.objects.dai.address,
        dai_usd_agg: agg_daiusd.address,
        xau_usd_agg: agg_xauusd.address,
        par: ray(1),
        ceil: wad(100000),
        adaptrange: 1,
        adaptttl:   BANKYEAR / 4,
        daiusdttl:  BANKYEAR,
        xauusdttl:  BANKYEAR,
        twaprange:  500,
        twapttl:    BANKYEAR,
        platpep:    2,
        platpop:    ray(1),
        plotpep:    2,
        plotpop:    ray(1),
        mintramp:   { bel: timestamp, cel: 1, rel: ray(0.02).div(BANKYEAR), wel: ray(1) },
    }

    let ilks = []
    const tokens = args.tokens ? require(args.tokens)[args.netname] : {}
    for (let token in tokens) {
        const params = tokens[token];  
        let ilk = {
            ilk: b32(params.ilk),
            gem: deps.objects[token].address,
            gemethagg: params.gemethagg,
            gemusdagg: params.gemusdagg,
            chop: ray(params.chop),
            dust: rad(params.dust),
            fee: ray(params.fee),
            line: rad(params.line),
            liqr: ray(params.liqr),
            ttl: params.ttl,
            range: params.range
        }
        // create mock chainlink feed with price of 2000
        if (params.gemusdagg == '0x' + '00'.repeat(20)) {
            if(params.gemethagg == '0x' + '00'.repeat(20)){
                await send(fb.push, b32(token + ':usd'), bn2b32(hre.ethers.BigNumber.from('200000000000')), timestamp * 2);
                debug('deploying mock aggregator for token', token)
                const agg_tokenusd = await agg_type.deploy(deps.objects.feedbase.address, ali.address, b32(token + ':usd'), 8, {gasLimit: args.gasLimit})
                ilk.gemusdagg = agg_tokenusd.address;
            } else {
                ilk.gemusdagg = '0x' + '00'.repeat(20);
            }
        }
        ilks.push(ilk)
    }

    debug('deploying ball...')
    const ball = await ball_type.deploy(ballargs, {gasLimit: args.gasLimit})
    debug('transferring diamond to ball')
    await send(diamond.transferOwnership, ball.address)
    debug('add ball as ward in fb components')
    const deps_dapp = await dpack.load(deps, hre.ethers, ali)
    await send(deps_dapp.uniswapv3adapter.ward, ball.address, true)
    await send(deps_dapp.divider.ward, ball.address, true)
    await send(deps_dapp.multiplier.ward, ball.address, true)
    await send(deps_dapp.chainlinkadapter.ward, ball.address, true)

    debug('running ball setup...')
    await send(ball.setup, ballargs)
    debug(`done deploying ball at ${ball.address}...making ilks`)
    for (let ilk of ilks) {
        await send(ball.makeilk, ilk)
    }
    debug(`done making ilks...making uni hook`)
    await send(ball.makeuni, ups);
    await send(ball.approve, ali.address);
    debug('done making uni hook')
    debug('ward rico and risk')
    await send(deps_dapp.rico.ward, diamond.address, 1)
    await send(deps_dapp.risk.ward, diamond.address, 1)
    debug('accept ownership')
    await send(diamond.acceptOwnership)
    debug('creating pack')

    const getartifact = async (ty) => {
        debug(`getting artifact for ${ty}`)
        return dpack.getIpfsJson(deps.types[ty].artifact['/']);
    }

    debug('packing ball')
    await pb.packObject({
        objectname: 'ball',
        address: ball.address,
        typename: 'Ball',
        artifact: require('../artifacts/src/ball.sol/Ball.json')
    })

    debug('packing Ricobank diamond')
    let top_artifact = require('../artifacts/hardhat-diamond-abi/HardhatDiamondABI.sol/BankDiamond.json')
    top_artifact.deployedBytecode = diamond_artifact.deployedBytecode
    top_artifact.bytecode = diamond_artifact.bytecode
    top_artifact.linkReferences = diamond_artifact.linkReferences
    top_artifact.deployedLinkReferences = diamond_artifact.deployedLinkReferences
    top_artifact.abi = top_artifact.abi.filter((item, idx) => {
        return top_artifact.abi.findIndex(a => item.name == a.name) == idx
    })

    await pb.packObject({
        objectname: 'bank',
        address: diamond.address,
        typename: 'Ricobank',
        artifact: top_artifact
    }, true)
    debug('all packed, merging')

    const pack = (await pb.merge(deps)).build()
    if (args.writepack) {
        const outfile = require('path').join(
            __dirname, `../pack/ricobank_${hre.network.name}.dpack.json`
        )
        const packstr = JSON.stringify(pack, null, 2)
        require('fs').writeFileSync(outfile, packstr)
    }
    return pack
  })
