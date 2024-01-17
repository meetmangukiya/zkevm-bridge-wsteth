pragma solidity ^0.8.20;

import { PolygonZkEVMBridgeInvestable, TOKEN_ETH_NATIVE } from "./PolygonZkEVMBridgeInvestable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { stETH, withdrawalQueue } from "./lido.sol";

uint256 constant TOTAL_BPS = 10_000;

contract LidoInvestmentManager is Ownable {
    error CannotRedeemLessThanMin();
    error TargetPercentCannotBeLessThanReservePercent();
    error ReservePercentCannotBeGreaterThanTargetPercent();
    error TooBigRedemption();
    error InvalidRequestId();
    error InvalidLength();

    event UpdateReservePercent(uint256 newReservePercent);
    event UpdateTargetPercent(uint256 newTargetPercent);
    event UpdateExcessYieldRecipient(address newRecipient);
    event Invested(uint256);
    event QueueRedemptions(uint256 totalAmount, uint256[] amounts, uint256[] requestIds);
    event SentExcessYield(address recipient, uint256 amt);

    PolygonZkEVMBridgeInvestable public immutable bridge;
    // @notice percent of ETH that _should_ be kept liquid
    // @dev % below which redemptions can be made. This is always less than targetPercentBips.
    uint256 public reservePercentBips;
    // @notice percent of ETH above which investments should be made
    // @dev % above which investments can be made. This is always more than reservePercentBips.
    uint256 public targetPercentBips;
    // @notice address to send excess yield to
    address public excessYieldRecipient;

    // @notice amount of ETH invested in stETH
    uint256 public invested;
    // @notice amount of ETH that is in withdrawal queue for redemptions.
    uint256 public pendingRedemptions;
    // @notice request ids for all redemptions that have ever been queued
    uint256[] public redemptionRequests;
    // @notice index of the next redemption request to claim
    uint256 public nextRequestIndexToClaim;

    constructor(
        PolygonZkEVMBridgeInvestable _bridge,
        uint256 _reserveBps,
        uint256 _targetBps,
        address _yieldRecipient
    ) {
        bridge = _bridge;

        if (_reserveBps >= _targetBps) revert ReservePercentCannotBeGreaterThanTargetPercent();

        reservePercentBips = _reserveBps;
        emit UpdateReservePercent(_reserveBps);

        targetPercentBips = _targetBps;
        emit UpdateTargetPercent(_targetBps);

        excessYieldRecipient = _yieldRecipient;
        emit UpdateExcessYieldRecipient(_yieldRecipient);
    }

    function updateReservePercent(uint256 _newBps) external onlyOwner {
        if (_newBps >= targetPercentBips) revert ReservePercentCannotBeGreaterThanTargetPercent();
        reservePercentBips = _newBps;
        emit UpdateReservePercent(_newBps);
    }

    function updateTargetPercent(uint256 _newBps) external onlyOwner {
        if (_newBps <= reservePercentBips) revert TargetPercentCannotBeLessThanReservePercent();
        targetPercentBips = _newBps;
        emit UpdateTargetPercent(_newBps);
    }

    function updateExcessYieldRecipient(address _newRecipient) external onlyOwner {
        excessYieldRecipient = _newRecipient;
        emit UpdateExcessYieldRecipient(_newRecipient);
    }

    function redeem(uint256 _amt) external {
        uint256 redeemable_ = redeemable();
        if (_amt > redeemable_) revert TooBigRedemption();
        _queueRedemption(_amt);
    }

    function invest() external {
        uint256 investable_ = investable();
        if (investable_ > 0) {
            _pullAndInvest(investable_);
        }
    }

    function sendExcessYield() external {
        uint256 yield = excessYield();
        stETH.transfer(excessYieldRecipient, yield);
        emit SentExcessYield(excessYieldRecipient, yield);
    }

    function claimNextNWithdrawals(uint256 _n) external {
        uint256 nextToClaim = nextRequestIndexToClaim;
        uint256[] memory requestIds = new uint[](_n);

        for (uint256 i = 0; i < _n;) {
            requestIds[i] = redemptionRequests[nextToClaim];
            if (requestIds[i] == 0) revert InvalidRequestId();

            unchecked {
                ++i;
                ++nextToClaim;
            }
        }

        uint256 lastCheckpointIndex = withdrawalQueue.getLastCheckpointIndex();
        uint256[] memory hints = withdrawalQueue.findCheckpointHints(requestIds, 1, lastCheckpointIndex);
        _claimRedemptions(requestIds, hints);

        // set the next request index to claim
        nextRequestIndexToClaim = nextToClaim;
    }

    function claimWithdrawalsWithHints(uint256[] memory _requestIds, uint256[] memory _hints) external {
        uint256 nextToClaim = nextRequestIndexToClaim;
        uint256 nRequests = _requestIds.length;
        if (_hints.length != nRequests) revert InvalidLength();

        // validate the request ids are all being claimed in same order
        // in which they were made without any being left to be claimed
        for (uint256 i = 0; i < nRequests;) {
            // uint requestId = nextToClaim
            uint256 requestIdCalldata = _requestIds[i];
            uint256 requestIdStorage = redemptionRequests[nextToClaim];
            if (requestIdCalldata != requestIdStorage) revert InvalidRequestId();
            unchecked {
                ++i;
                ++nextToClaim;
            }
        }

        _claimRedemptions(_requestIds, _hints);

        // set the next request index to claim
        nextRequestIndexToClaim = nextToClaim;
    }

    receive() external payable { }

    function investable() public view returns (uint256 _investable) {
        uint256 ethBalance = address(bridge).balance;
        uint256 totalEth = ethBalance + invested;
        uint256 targetLiquidEth = totalEth * targetPercentBips / TOTAL_BPS;
        if (ethBalance > targetLiquidEth) _investable = ethBalance - targetLiquidEth;
    }

    function redeemable() public view returns (uint256 _redeemable) {
        uint256 ethBalance = address(bridge).balance;
        uint256 totalEth = ethBalance + invested;
        uint256 reserveLiquidEth = totalEth * reservePercentBips / TOTAL_BPS;
        uint256 targetLiquidEth = totalEth * targetPercentBips / TOTAL_BPS;
        // if < reserve, reset is possible all the way to target, but not necessarily
        if (ethBalance < reserveLiquidEth) {
            uint256 maxRedeem = targetLiquidEth - ethBalance;
            _redeemable = invested > maxRedeem ? maxRedeem : invested;
        }
    }

    function excessYield() public view returns (uint256 _yield) {
        uint256 currentBalance = stETH.balanceOf(address(this));
        _yield = currentBalance - invested;
    }

    function _pullAndInvest(uint256 _amt) internal {
        bridge.pullAsset(TOKEN_ETH_NATIVE, _amt, address(this));
        uint256 shares = stETH.submit{ value: _amt }(address(this));
        invested += stETH.getPooledEthByShares(shares);
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
        // store the request ids
        for (uint256 i = 0; i < nRequests;) {
            redemptionRequests.push(requestIds[i]);
        }
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
        pendingRedemptions -= _claimedEth;
        bridge.depositEth{ value: _claimedEth }();
    }
}
