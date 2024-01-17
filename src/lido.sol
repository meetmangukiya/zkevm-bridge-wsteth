pragma solidity ^0.8.20;

interface IStETH {
    function balanceOf(address) external view returns (uint256);
    function submit(address _referral) external payable returns (uint256);
    function transfer(address _to, uint256 _amt) external;
    function getTotalShares() external view returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function sharesOf(address) external view returns (uint256);
    function getPooledEthByShares(uint256) external view returns (uint256);
}

interface IWithdrawalQueueERC721 {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function MAX_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function MIN_STETH_WITHDRAWAL_AMOUNT() external view returns (uint256);

    function requestWithdrawals(uint256[] memory _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawals(uint256[] memory _requestIds, uint256[] memory _hints) external;

    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);

    function claimWithdrawal(uint256 _requestId) external;

    function getLastFinalizedRequestId() external view returns (uint256);

    function getLastCheckpointIndex() external view returns (uint256);

    function findCheckpointHints(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds);
}

IStETH constant stETH = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
IWithdrawalQueueERC721 constant withdrawalQueue = IWithdrawalQueueERC721(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
