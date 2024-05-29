import '@nomiclabs/hardhat-ethers'
import '@nomicfoundation/hardhat-verify'

import './lib/gemfab/task/deploy-gemfab'
import './lib/weth/task/deploy-mock-weth'
import './lib/uniswapv3/task/deploy-uniswapv3'

import './task/combine-packs'
import './task/deploy-tokens'

import './task/deploy-dependencies'
import './task/deploy-ricobank'
import './task/make-usdc-ref'
import 'hardhat-diamond-abi'

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  diamondAbi: {
      name: 'BankDiamond',
      include: ['Vat', 'Vow', 'Vox', 'Bank', 'File', 'BankDiamond'],
      strict: false
  },
  solidity: {
    compilers: [
        {
            version: "0.8.25",
            settings: {
              optimizer: {
                enabled: true,
                runs: 10000
              },
              outputSelection: {
                "*": {
                  "*": ["storageLayout"]
                }
              }
            }
        },
        {
            version: "0.7.6",
            settings: {
              optimizer: {
                enabled: true,
                runs: 2000
              },
              outputSelection: {
                "*": {
                  "*": ["storageLayout"]
                }
              }
            }
        }
    ],
    overrides: {
        // hardhat overrides don't match regex
        '@openzeppelin/contracts/access/TimelockController.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/access/AccessControl.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/access/Ownable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/ProxyAdmin.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/UpgradeableProxy.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/IBeacon.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/Proxy.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/UpgradeableBeacon.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/BeaconProxy.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/Clones.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/proxy/Initializable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/IRelayHub.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/GSNRecipientSignature.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/IRelayRecipient.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/Context.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/GSNRecipientERC20Fee.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/GSN/GSNRecipient.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/IERC1820Registry.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/ERC165.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/IERC165.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/IERC1820Implementer.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/ERC1820Implementer.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/introspection/ERC165Checker.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/InitializableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/OwnableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/AddressImpl.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/GSNRecipientMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC721Mock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC1155Mock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/CountersImpl.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ArraysImpl.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC1820ImplementerMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ReentrancyAttack.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20DecimalsMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/Create2Impl.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC1155ReceiverMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/GSNRecipientSignatureMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/EnumerableSetMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC777SenderRecipientMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC721GSNRecipientMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ECDSAMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC1155PausableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC165/ERC165NotSupported.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC165/ERC165InterfacesSupported.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC1155BurnableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/EtherReceiverMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20PermitMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20BurnableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/CallReceiverMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/StringsMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/EIP712External.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/EnumerableMapMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ConditionalEscrowMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC165CheckerMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/PullPaymentMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/MerkleProofWrapper.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC721BurnableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ReentrancyMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/MultipleInheritanceInitializableMocks.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC721ReceiverMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC165Mock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/DummyImplementation.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20Mock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ClonesMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/PausableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20CappedMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ContextMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ClashingImplementation.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/SafeCastMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20SnapshotMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC20PausableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/SignedSafeMathMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC777Mock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/AccessControlMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/MathMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/ERC721PausableMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/BadBeacon.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/SafeERC20Helper.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/SingleInheritanceInitializableMocks.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/GSNRecipientERC20FeeMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/SafeMathMock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/mocks/RegressionImplementation.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/cryptography/MerkleProof.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/cryptography/ECDSA.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/ReentrancyGuard.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Strings.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/SafeCast.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Address.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Context.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Pausable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Arrays.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Create2.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/EnumerableMap.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/Counters.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/utils/EnumerableSet.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/math/SafeMath.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/math/Math.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/math/SignedSafeMath.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/presets/ERC721PresetMinterPauserAutoId.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/presets/ERC20PresetMinterPauser.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/presets/ERC777PresetFixedSupply.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/presets/ERC1155PresetMinterPauser.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/presets/ERC20PresetFixedSupply.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/ERC721Holder.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/IERC721.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/ERC721Pausable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/ERC721.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/ERC721Burnable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/ERC20Snapshot.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/ERC20Pausable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/ERC20Capped.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/ERC20.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/TokenTimelock.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/IERC20.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC20/SafeERC20.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/IERC1155.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/IERC1155MetadataURI.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/ERC1155Pausable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/ERC1155.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC1155/ERC1155Burnable.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC777/IERC777.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC777/ERC777.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC777/IERC777Sender.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/drafts/IERC20Permit.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/drafts/EIP712.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/drafts/ERC20Permit.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/payment/PullPayment.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/payment/escrow/ConditionalEscrow.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/payment/escrow/Escrow.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/payment/escrow/RefundEscrow.sol': { version: "0.7.6" },
        '@openzeppelin/contracts/payment/PaymentSplitter.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/libraries/SafeMath.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/libraries/Math.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/libraries/UQ112x112.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/test/ERC20.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/interfaces/IERC20.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/interfaces/IUniswapV2ERC20.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/UniswapV2Pair.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/UniswapV2Factory.sol': { version: "0.7.6" },
        '@uniswap/v2-core/contracts/UniswapV2ERC20.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/SafeERC20Namer.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/AddressStringUtil.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/Babylonian.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/TransferHelper.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/BitMath.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/FixedPoint.sol': { version: "0.7.6" },
        '@uniswap/lib/contracts/libraries/FullMath.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/PositionValue.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/HexStrings.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/PositionKey.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/ChainId.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/BytesLib.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/NFTDescriptor.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/Path.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/NFTSVG.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/SqrtPriceMathPartial.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/TokenRatioSortOrder.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/libraries/PoolTicksCounter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IERC20Metadata.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IERC721Permit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IMulticall.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/ISelfPermit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IPoolInitializer.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/ITickLens.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IPeripheryPaymentsWithFee.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IV3Migrator.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/INonfungibleTokenPositionDescriptor.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/external/IERC1271.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/external/IERC20PermitAllowed.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/PeripheryPayments.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/SelfPermit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/PeripheryPaymentsWithFee.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/ERC721Permit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/BlockTimestamp.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/PoolInitializer.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/PeripheryValidation.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/Multicall.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/OracleLibrary.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/PositionValue.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/HexStrings.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/PositionKey.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/ChainId.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/BytesLib.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/PoolAddress.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/CallbackValidation.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/Path.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/TransferHelper.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/NFTSVG.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/SqrtPriceMathPartial.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/LiquidityAmounts.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/TokenRatioSortOrder.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/libraries/PoolTicksCounter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IPeripheryImmutableState.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IQuoter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IERC20Metadata.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IERC721Permit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IMulticall.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/ISelfPermit.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IPoolInitializer.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/ITickLens.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IPeripheryPaymentsWithFee.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IQuoterV2.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungiblePositionManager.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IV3Migrator.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/IPeripheryPayments.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/INonfungibleTokenPositionDescriptor.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/external/IERC1271.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/external/IERC20PermitAllowed.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/interfaces/external/IWETH9.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/V3Migrator.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/lens/UniswapInterfaceMulticall.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/lens/Quoter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/lens/TickLens.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol': { version: "0.7.6" },
        '@uniswap/v3-periphery/artifacts/contracts/examples/PairFlash.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/SafeCast.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/SwapMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/Oracle.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/LiquidityMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/TransferHelper.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/BitMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/Position.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/TickMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/Tick.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/UnsafeMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/TickBitmap.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/FullMath.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/IUniswapV3PoolDeployer.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol': { version: "0.7.6" },
        '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3PoolDeployer.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/callback/IUniswapV3SwapCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/callback/IUniswapV3MintCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/callback/IUniswapV3FlashCallback.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/IERC20Minimal.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolState.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolEvents.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/pool/IUniswapV3PoolActions.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3Factory.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3Pool.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol': { version: "0.7.6" },
        '@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol': { version: "0.7.6" }
    }
 
  },
  paths: {
    sources: "./src"
  },
  networks: {
      hardhat: {
          forking: process.env["FORK_ARB"] ? {
            url: process.env["ARB_RPC_URL"], blockNumber: 202175244, chainId: 42161
          } : {
            url: process.env["RPC_URL"], blockNumber: 19060431, chainId: 1
          },
          accounts: {
              accountsBalance: '1000000000000000000000000000000'
          }
      },
      arbitrum_goerli: {
          url: process.env["ARB_GOERLI_RPC_URL"],
          accounts: {
            mnemonic: process.env["ARB_GOERLI_MNEMONIC"]
          },
          chainId: 421613
      },
      arbitrum_sepolia: {
          url: process.env["ARB_SEPOLIA_RPC_URL"],
          accounts: {
            mnemonic: process.env["ARB_SEPOLIA_MNEMONIC"]
          },
          chainId: 421614
      },
      sepolia: {
          url: process.env["SEPOLIA_RPC_URL"],
          accounts: {
            mnemonic: process.env["SEPOLIA_MNEMONIC"],
          },
          chainId: 11155111
      },
      arbitrum: {
        url: process.env["ARB_RPC_URL"],
        accounts: {
          mnemonic: process.env["ARB_MNEMONIC"]
        },
        chainId: 42161
      }
  },
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY
    }
  }

}
