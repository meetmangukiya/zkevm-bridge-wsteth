pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { LidoInvestmentManager } from "src/LidoInvestmentManager.sol";
import { PolygonZkEVMBridgeInvestable, TOKEN_ETH_NATIVE } from "src/PolygonZkEVMBridgeInvestable.sol";
import { PolygonZkEVMGlobalExitRoot } from "zkevm-contracts/PolygonZkEVMGlobalExitRoot.sol";
import { stETH } from "src/lido.sol";
import { StdStorage, stdStorage } from "forge-std/StdStorage.sol";

using stdStorage for StdStorage;

contract LidoInvestmentManagerTest is Test {
    LidoInvestmentManager investmentManager;
    PolygonZkEVMBridgeInvestable bridge;
    PolygonZkEVMGlobalExitRoot globalExitRootManager;

    address notOwner = makeAddr("notOwner");
    address yieldRecipient = makeAddr("yieldRecipient");

    uint256 targetBps = 100;
    uint256 reserveBps = 50;

    function setUp() external {
        bridge = new PolygonZkEVMBridgeInvestable();
        address rollup = address(0);
        globalExitRootManager = new PolygonZkEVMGlobalExitRoot(address(0), address(bridge));
        bridge.initialize(1, globalExitRootManager, rollup);

        investmentManager = new LidoInvestmentManager(bridge, reserveBps, targetBps, yieldRecipient);
        bridge.updateInvestmentManager(address(investmentManager), TOKEN_ETH_NATIVE);
    }

    function testUpdateReservePercent() external {
        uint256 prev = investmentManager.reservePercentBips();
        uint256 next = prev + 1;
        investmentManager.updateReservePercent(next);
        uint256 current = investmentManager.reservePercentBips();
        assertEq(current, next, "updateReservePercent didnt work");

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        investmentManager.updateReservePercent(current + 1);

        uint256 target = investmentManager.targetPercentBips();
        vm.expectRevert(LidoInvestmentManager.ReservePercentCannotBeGreaterThanTargetPercent.selector);
        investmentManager.updateReservePercent(target);

        vm.expectRevert(LidoInvestmentManager.ReservePercentCannotBeGreaterThanTargetPercent.selector);
        investmentManager.updateReservePercent(target + 1);
    }

    function testUpdateTargetPercent() external {
        uint256 prev = investmentManager.targetPercentBips();
        uint256 next = prev + 1;
        investmentManager.updateTargetPercent(next);
        uint256 current = investmentManager.targetPercentBips();
        assertEq(current, next, "updateTargetPercent didnt work");

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        investmentManager.updateTargetPercent(current + 1);

        uint256 reserve = investmentManager.reservePercentBips();
        vm.expectRevert(LidoInvestmentManager.TargetPercentCannotBeLessThanReservePercent.selector);
        investmentManager.updateTargetPercent(reserve);

        vm.expectRevert(LidoInvestmentManager.TargetPercentCannotBeLessThanReservePercent.selector);
        investmentManager.updateTargetPercent(reserve - 1);
    }

    function testUpdateExcessYieldRecipient() external {
        address newRecipient = address(uint160(yieldRecipient) + 1);

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        investmentManager.updateExcessYieldRecipient(newRecipient);

        investmentManager.updateExcessYieldRecipient(newRecipient);
        assertEq(newRecipient, investmentManager.excessYieldRecipient(), "yield recipient not set correctly");
    }

    function testInvestableRedeemable() external {
        // someone deposited 1000 ether
        _increaseEth(address(bridge), 1000 ether);
        assertEq(investmentManager.investable(), 990 ether, "tir: 1");

        // called invest
        _decreaseEth(address(bridge), 990 ether);
        _setInvested(990 ether);
        // already at target, investable should be 0
        assertEq(investmentManager.investable(), 0, "tir: 2");
        assertEq(investmentManager.redeemable(), 0, "tir: 3");

        // someone withdrew 2 ether, within reserve
        _decreaseEth(address(bridge), 2 ether);
        assertEq(investmentManager.investable(), 0, "tir: 4");
        assertEq(investmentManager.redeemable(), 0, "tir: 5");

        // someone withdraw 5 ether more, less than reserve
        _decreaseEth(address(bridge), 5 ether);
        // uint total = 990 invested + 3 in bridge = 993
        // uint targetEth = 9.93 ether
        // uint reserveEth = 4.965 ether
        // 6.93 is max redeemable
        assertEq(investmentManager.investable(), 0, "tir: 6");
        assertEq(investmentManager.redeemable(), 6.93 ether, "tir: 7");
    }

    function testSendExcessYield() external {
        _increaseEth(address(bridge), 1000 ether);
        investmentManager.invest();

        uint256 invested = investmentManager.invested();
        uint256 shares = stETH.sharesOf(address(investmentManager));
        uint256 totalShares = stETH.getTotalShares();
        assertEq(investmentManager.excessYield(), 0, "yield should be 0");
        _distributeEthYield(totalShares);
        uint256 yield = investmentManager.excessYield();
        assertEq(yield, shares, "yield should be = shares");

        uint256 prevBalance = stETH.balanceOf(yieldRecipient);
        investmentManager.sendExcessYield();
        uint256 nextBalance = stETH.balanceOf(yieldRecipient);
        assertApproxEqAbs(nextBalance, prevBalance + yield, 5, "excess yield not sent correctly");
    }

    function testInvest() external {
        // set bridge balance
        _increaseEth(address(bridge), 1000 ether);
        uint256 investable = investmentManager.investable();
        assertEq(investable, 990 ether, "incorrect investable for 100 bps target");
        uint256 stethBalanceBefore = stETH.balanceOf(address(investmentManager));
        assertEq(stethBalanceBefore, 0, "there should be no steth at this point");

        investmentManager.invest();
        // there should be `investable` amount of steth after invest call
        uint256 stethBalanceAfter = stETH.balanceOf(address(investmentManager));
        assertApproxEqAbs(stethBalanceAfter, investable, 1, "incorrect amount invested in steth");

        // there should be nothing investable right after an invest call
        assertEq(investmentManager.investable(), 1);

        // reduce bridge balance, at this point it should be 10 ether, reduce to 5 ether
        _decreaseEth(address(bridge), 5 ether);
        assertEq(investmentManager.investable(), 0, "< target, cannot invest");

        // increase eth balance, invested = 990, bridge balance = 5, increase 1005 for total of 2000
        _increaseEth(address(bridge), 1005 ether);
        assertApproxEqAbs(investmentManager.investable(), 990 ether, 5, "incorrect investable");
        investmentManager.invest();
        assertApproxEqAbs(stETH.balanceOf(address(investmentManager)), 1980 ether, 5, "incorrect invested");
    }

    function _setInvested(uint256 _invested) internal {
        stdstore.target(address(investmentManager)).sig(investmentManager.invested.selector).checked_write(_invested);
    }

    function _increaseEth(address _who, uint256 _amt) internal {
        uint256 next = _who.balance + _amt;
        vm.deal(_who, next);
    }

    function _decreaseEth(address _who, uint256 _amt) internal {
        uint256 next = _who.balance - _amt;
        vm.deal(_who, next);
    }

    function _distributeEthYield(uint256 _amt) internal {
        bytes32 storageSlot = keccak256("lido.Lido.beaconBalance");
        uint256 prev = uint256(vm.load(address(stETH), storageSlot));
        uint256 next = prev + _amt;
        vm.store(address(stETH), storageSlot, bytes32(next));
    }
}
