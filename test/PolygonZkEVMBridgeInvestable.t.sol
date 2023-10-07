import { PolygonZkEVMBridgeInvestable, TOKEN_ETH_NATIVE } from "src/PolygonZkEVMBridgeInvestable.sol";
import { PolygonZkEVMGlobalExitRoot } from "zkevm-contracts/PolygonZkEVMGlobalExitRoot.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20("Mock", "MCK") { }

contract InvestmentManagerMock {
    PolygonZkEVMBridgeInvestable immutable bridge;

    constructor(PolygonZkEVMBridgeInvestable _bridge) {
        bridge = _bridge;
    }

    function pullAsset(address _token, uint256 _amount) external {
        bridge.pullAsset(_token, _amount, address(this));
    }

    receive() external payable { }
}

contract PolygonZkEVMBridgeInvestableTest is Test {
    PolygonZkEVMBridgeInvestable bridge;
    PolygonZkEVMGlobalExitRoot globalExitRootManager;

    InvestmentManagerMock investmentManager;
    ERC20Mock erc20Mock;

    function setUp() external {
        bridge = new PolygonZkEVMBridgeInvestable();
        address rollup = address(0);
        globalExitRootManager = new PolygonZkEVMGlobalExitRoot(address(0), address(bridge));
        bridge.initialize(1, globalExitRootManager, rollup);
        investmentManager = new InvestmentManagerMock(bridge);
        erc20Mock = new ERC20Mock();
    }

    function testUpdateInvestmentManger() external {
        vm.expectRevert(PolygonZkEVMBridgeInvestable.ZeroAddress.selector);
        bridge.updateInvestmentManager(address(0), address(1));
    }

    function testPullAsset() external {
        deal(address(bridge), 10 ether);
        vm.expectRevert(PolygonZkEVMBridgeInvestable.OnlyInvestmentManager.selector);
        bridge.pullAsset(TOKEN_ETH_NATIVE, 10 ether, address(this));

        // make investment manager for ether
        bridge.updateInvestmentManager(address(investmentManager), TOKEN_ETH_NATIVE);
        deal(address(bridge), 10 ether);
        investmentManager.pullAsset(TOKEN_ETH_NATIVE, 5 ether);
        assertEq(address(bridge).balance, 5 ether);

        // revoke investment management for ether
        bridge.updateInvestmentManager(address(investmentManager), address(0));
        vm.expectRevert(PolygonZkEVMBridgeInvestable.OnlyInvestmentManager.selector);
        investmentManager.pullAsset(TOKEN_ETH_NATIVE, 5 ether);

        // grant investment management for erc20
        deal(address(erc20Mock), address(bridge), 100 ether);
        bridge.updateInvestmentManager(address(investmentManager), address(erc20Mock));
        assertEq(erc20Mock.balanceOf(address(bridge)), 100 ether);
        investmentManager.pullAsset(address(erc20Mock), 10 ether);
        assertEq(erc20Mock.balanceOf(address(bridge)), 90 ether);
        assertEq(erc20Mock.balanceOf(address(investmentManager)), 10 ether);

        // revoke investment management for erc20
        bridge.updateInvestmentManager(address(investmentManager), address(0));
        vm.expectRevert(PolygonZkEVMBridgeInvestable.OnlyInvestmentManager.selector);
        investmentManager.pullAsset(address(erc20Mock), 10 ether);
    }

    receive() external payable { }
}
