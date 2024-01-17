# zkevm-bridge-wsteth

This adds the functionality of `InvestmentManagers` to the `PolygonZkEVMBridge`.
It is a simple mapping of which address can manage which tokens.
Investment managers are able to pull tokens from bridge using `pullAsset(address,uint,address)` function.

We also add a [`Lido Investment Manager`](./src/LidoInvestmentManager.sol)
that will invest the ETH locked in the bridge in Lido stETH. Some configuration params
for the same are:

| Config                 | Description                                          |
| ---------------------- | ---------------------------------------------------- |
| `targetPercentBips`    | % of ETH above which it could be invested into stETH |
| `reservePercentBips`   | % of ETH below which redemptions can be queued       |
| `excessYieldRecipient` | address to which the ETH yield will be sent to       |

Features:

1. Anyone is able to call `invest()` function to invest the surplus ETH into stETH.
2. Anyone is able to call `redeem(uint)` function to redeem given amount of ETH if % liquid ETH is below `reservePercentBips`.
3. Lido withdrawals are 2 steps, so after requesting redemption, when they are available for claiming someone has to call either `claimNextNWithdrawals(uint)` or `claimWithdrawalsWithHints(uint[],uint[])`. The first is if you dont have hints. This will cost more gas. The second alternative is if you have hints. All the claimed ETH will be sent to the bridge with `depositETH` call.
