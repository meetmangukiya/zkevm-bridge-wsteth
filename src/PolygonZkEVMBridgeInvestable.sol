import { PolygonZkEVMBridge, IBasePolygonZkEVMGlobalExitRoot } from "zkevm-contracts/PolygonZkEVMBridge.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

address constant TOKEN_ETH_NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract PolygonZkEVMBridgeInvestable is PolygonZkEVMBridge, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error OnlyInvestmentManager();

    event UpdateInvestmentManager(address indexed _investmentManager, address indexed _tokenManaged);

    mapping(address => address) investmentManagers;

    /**
     * @param _networkID networkID
     * @param _globalExitRootManager global exit root manager address
     * @param _polygonZkEVMaddress polygonZkEVM address
     * @notice The value of `_polygonZkEVMaddress` on the L2 deployment of the contract will be address(0), so
     * emergency state is not possible for the L2 deployment of the bridge, intentionally
     */
    function initialize(
        uint32 _networkID,
        IBasePolygonZkEVMGlobalExitRoot _globalExitRootManager,
        address _polygonZkEVMaddress
    ) external override initializer {
        networkID = _networkID;
        globalExitRootManager = _globalExitRootManager;
        polygonZkEVMaddress = _polygonZkEVMaddress;

        // Initialize OZ contracts
        __ReentrancyGuard_init();
        __Ownable_init();
    }

    function updateInvestmentManager(address _investmentManager, address _token) external onlyOwner {
        if (_investmentManager == address(0)) revert ZeroAddress();
        investmentManagers[_investmentManager] = _token;
        emit UpdateInvestmentManager(_investmentManager, _token);
    }

    function pullAsset(address _token, uint256 _amount, address _receiver)
        external
        nonReentrant
        onlyInvestmentManager(msg.sender, _token)
    {
        if (_amount == 0) return;
        if (_token == TOKEN_ETH_NATIVE) {
            payable(_receiver).call{ value: _amount }("");
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }

    modifier onlyInvestmentManager(address _manager, address _token) {
        if (investmentManagers[_manager] != _token) revert OnlyInvestmentManager();
        _;
    }
}
