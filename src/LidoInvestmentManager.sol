import { PolygonZkEVMBridgeInvestable, TOKEN_ETH_NATIVE } from "./PolygonZkEVMBridgeInvestable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { stETH, withdrawalQueue } from "./lido.sol";

uint256 constant TOTAL_BPS = 10_000;

contract LidoInvestmentManager is Ownable {
    error CannotRedeemLessThanMin();

    event UpdateReservePercent(uint256 newReservePercent);
    event UpdateTargetPercent(uint256 newTargetPercent);
    event UpdateExcessYieldRecipient(address newRecipient);
    event Invested(uint256);
    event QueueRedemptions(uint256 _totalAmount, uint256[] _amounts, uint256[] _requestIds);

    PolygonZkEVMBridgeInvestable public immutable bridge;
    uint256 public reservePercentBips;
    uint256 public targetPercentBips;
    address public excessYieldRecipient;

    uint256 public invested;
    uint256 public pendingRedemptions;
    uint256[] public redemptionRequests;
    uint256 public requestsClaimed;

    constructor(PolygonZkEVMBridgeInvestable _bridge) {
        bridge = _bridge;
    }

    function updateReservePercent(uint256 _newBps) external onlyOwner {
        reservePercentBips = _newBps;
        emit UpdateReservePercent(_newBps);
    }

    function updateTargetPercent(uint256 _newBps) external onlyOwner {
        targetPercentBips = _newBps;
        emit UpdateTargetPercent(_newBps);
    }

    function updateExcessYieldRecipient(address _newRecipient) external onlyOwner {
        excessYieldRecipient = _newRecipient;
        emit UpdateExcessYieldRecipient(_newRecipient);
    }

    function requestRedeem(uint256 _amount) external { }

    function redeem() external { }

    function invest() external {
        uint256 ethBalance = address(bridge).balance;
        uint256 totalEth = ethBalance + invested;
        uint256 percentLiquid = ethBalance * TOTAL_BPS / totalEth;
        if (percentLiquid > targetPercentBips) {
            uint256 targetBalance = ethBalance * targetPercentBips / TOTAL_BPS;
            uint256 investable = ethBalance - targetBalance;
            _pullAndInvest(investable);
        }
    }

    function sendExcessYield() external {
        uint256 currentBalance = stETH.balanceOf(address(this));
        uint256 excessYield = currentBalance - invested;
        // should this be in native eth?
        stETH.transfer(excessYieldRecipient, excessYield);
    }

    receive() external payable { }

    function _pullAndInvest(uint256 _amt) internal {
        invested += _amt;
        bridge.pullAsset(TOKEN_ETH_NATIVE, _amt, address(this));
        stETH.submit{ value: _amt }(address(this));
        emit Invested(_amt);
    }

    function _queueRedemption(uint256 _amt) internal {
        uint256 min = withdrawalQueue.MIN_STETH_WITHDRAWAL_AMOUNT();
        uint256 max = withdrawalQueue.MAX_STETH_WITHDRAWAL_AMOUNT();
        if (_amt < min) revert CannotRedeemLessThanMin();
        uint256 nRequests = _amt % max == 0 ? _amt / max : ((_amt / max) + 1);
        uint256[] memory amounts = new uint[](nRequests);
        uint256 amountLeft = _amt;
        for (uint256 i = 0; i < nRequests;) {
            amounts[i] = amountLeft > max ? max : amountLeft;
            unchecked {
                ++i;
                amountLeft -= amounts[i];
            }
        }
        invested -= _amt;
        pendingRedemptions += _amt;
        uint256[] memory requestIds = withdrawalQueue.requestWithdrawals(amounts, address(this));
        emit QueueRedemptions(_amt, amounts, requestIds);
    }

    function _claimRedemptions(uint256[] memory _requestIds, uint256[] memory _hints)
        internal
        returns (uint256 _claimedEth)
    {
        uint256 ethBefore = address(this).balance;
        withdrawalQueue.claimWithdrawals(_requestIds, _hints);
        uint256 ethAfter = address(this).balance;
        _claimedEth = ethAfter - ethBefore;
    }
}
