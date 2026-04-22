# DSC — Decentralised Stable Coin

A minimal overcollateralised stablecoin pegged to USD built on Solidity. Users deposit WETH or WBTC as collateral and mint DSC tokens against it. The system enforces a 200% minimum collateralisation ratio at all times using Chainlink price feeds. Undercollateralised positions can be liquidated by anyone for a 10% bonus. Includes an OracleLib staleness check, a comprehensive unit and fuzz test suite, and invariant tests verifying the core solvency guarantee.

---

## What It Does

- Users deposit WETH or WBTC as collateral and mint DSC tokens pegged to $1 USD
- The system enforces a 200% overcollateralisation ratio — users must always hold twice the collateral value of their DSC debt
- Chainlink price feeds determine the real-time USD value of all collateral via an oracle library that reverts on stale data
- If a user's health factor falls below the minimum, anyone can liquidate their position by burning DSC on their behalf and receiving the collateral plus a 10% bonus
- The DSC token contract is owned by the engine — only the engine can mint or burn tokens
- Collateral is held in the engine contract and released only when positions are closed or liquidated

---

## Protocol Characteristics

- Exogenously collateralised — backed by external assets (WETH and WBTC)
- Pegged to USD — each DSC token targets a value of $1
- Fully algorithmic — no governance, no manual intervention, rules enforced entirely on-chain

---

## Project Structure

```
.
├── src/
│   ├── DecentralisedStableCoin.sol     # ERC20 stablecoin token with owner-restricted mint and burn
│   ├── DSCEngine.sol                   # Core protocol logic — collateral, minting, liquidation
│   └── libraries/
│       └── OracleLib.sol               # Chainlink staleness check library
├── script/
│   ├── DeployDSC.s.sol                 # Deploys both contracts and transfers DSC ownership to engine
│   └── HelperConfig.s.sol              # Network-specific configuration for Anvil and Sepolia
└── test/
    ├── mocks/
    │   └── ERC20Mock.sol               # Mock ERC20 token for local testing
    ├── unit/
    │   └── DSCEngineTest.t.sol         # Unit, fuzz, and getter tests
    └── invariant/
        ├── Handler.t.sol               # Invariant test handler
        └── Invariant.t.sol             # Invariant test contract
```

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed

### Install dependencies and build

```bash
forge install
forge build
```

### Run all tests

```bash
forge test
```

### Run unit tests only

```bash
forge test --match-path test/unit/*
```

### Run invariant tests only

```bash
forge test --match-path test/invariant/*
```

### Run tests with verbose output

```bash
forge test -vvvv
```

### Deploy to a local Anvil chain

In one terminal, start Anvil:

```bash
anvil
```

In another terminal:

```bash
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast
```

### Deploy to Sepolia

```bash
forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

---

## Contract Overview

### DecentralisedStableCoin

A standard ERC20 token with owner-restricted minting and burning. Ownership is transferred to the DSCEngine at deployment — the engine is the only address that can mint or burn DSC tokens.

| Function                 | Visibility | Description                                                                 |
| ------------------------ | ---------- | --------------------------------------------------------------------------- |
| `mint(address, uint256)` | `external` | Mints DSC to a given address. Owner (engine) only. Returns true on success. |
| `burn(uint256)`          | `public`   | Burns DSC from the caller's balance. Owner (engine) only.                   |

### DSCEngine

The core protocol contract. Manages all collateral deposits, DSC minting, redemptions, and liquidations.

| Constant                | Value | Description                                                        |
| ----------------------- | ----- | ------------------------------------------------------------------ |
| `LIQUIDATION_THRESHOLD` | 50    | Collateral must be 200% of DSC value (50/100 = 50% ratio inverted) |
| `LIQUIDATION_BONUS`     | 10    | Liquidators receive a 10% bonus on seized collateral               |
| `MIN_HEALTH_FACTOR`     | 1e18  | Minimum health factor below which positions can be liquidated      |

| Function                                              | Visibility    | Description                                                |
| ----------------------------------------------------- | ------------- | ---------------------------------------------------------- |
| `depositCollateral(address, uint256)`                 | `public`      | Deposits collateral into the engine                        |
| `mintDsc(uint256)`                                    | `public`      | Mints DSC against deposited collateral                     |
| `depositCollateralAndMint(address, uint256, uint256)` | `external`    | Deposits and mints in a single transaction                 |
| `redeemCollateral(address, uint256)`                  | `public`      | Withdraws collateral — health factor must remain healthy   |
| `burnDsc(uint256)`                                    | `public`      | Burns DSC to improve health factor                         |
| `redeemCollateralForDsc(address, uint256, uint256)`   | `external`    | Burns DSC and redeems collateral in a single transaction   |
| `liquidate(address, address, uint256)`                | `external`    | Liquidates an undercollateralised position for a 10% bonus |
| `getUsdValue(address, uint256)`                       | `public view` | Returns the USD value of a token amount using Chainlink    |
| `getCollateralInUsd(address)`                         | `public view` | Returns the total USD value of a user's collateral         |
| `getTokenAmountFromUsd(address, uint256)`             | `public view` | Converts a USD amount to the equivalent token amount       |

### OracleLib

A library attached to `AggregatorV3Interface` that wraps `latestRoundData()` with a staleness check. Reverts with `OracleLib__StalePrice()` if the price feed has not been updated within 3 hours.

---

## Health Factor

The health factor determines whether a position is solvent. It is calculated as:

```
adjustedCollateral = collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION
healthFactor = adjustedCollateral * PRECISION / totalDscMinted
```

A health factor at or above `1e18` (1.0) means the position is healthy. Below `1e18` the position is eligible for liquidation. A user with no DSC minted has a health factor of `type(uint256).max`.

---

## Liquidation Flow

```
1. User's collateral value drops below 200% of their DSC debt
2. Health factor falls below 1e18
3. Liquidator calls liquidate() with the amount of DSC to burn
4. Engine calculates equivalent collateral amount using Chainlink price
5. Engine adds 10% bonus to the collateral amount
6. Collateral is transferred from the liquidated user to the liquidator
7. DSC is burned from the liquidator's balance, reducing the liquidated user's debt
8. Engine verifies the liquidation improved the user's health factor
9. Engine verifies the liquidator's own health factor is not broken
```

---

## Tests

### Unit Tests

| Test                                        | What It Checks                                                              |
| ------------------------------------------- | --------------------------------------------------------------------------- |
| `testRevertsIfLengthsAreNotEqual`           | Constructor reverts when token and price feed arrays have different lengths |
| `testConstructorAddsToMapping`              | Constructor correctly maps tokens to their price feeds                      |
| `testConstructorAddsToArray`                | Constructor correctly populates the collateral tokens array                 |
| `testDepositCollateralAddsCollateral`       | Depositing collateral updates the user's balance in the engine              |
| `testDepositCollateralEmitsEvent`           | Depositing emits CollateralDeposited with correct parameters                |
| `testMintingAddsAmountMinted`               | Minting DSC updates the user's minted balance                               |
| `testMintRevertsIfHealthFactorBreaks`       | Minting too much DSC reverts with HealthFactorBelowMinimum                  |
| `testLiquidateReturnsIfHealthFactorIsOk`    | Liquidating a healthy position reverts with HealthFactorOk                  |
| `testLiquidateRevertsIfAmountIsZero`        | Liquidating with zero amount reverts with AmountShouldBeMoreThanZero        |
| `testLiquidatorReceivesCollateralPlusBonus` | Liquidator receives collateral plus 10% bonus                               |
| `testLiquidationImprovesHealthFactor`       | Liquidation improves the liquidated user's health factor                    |
| `testLiquidationReducesBobsDebt`            | Liquidation reduces the liquidated user's DSC debt                          |

### Fuzz Tests

| Test                                   | What It Checks                                                                                                                        |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `testFuzz_DepositCollateralAndMintDsc` | Minting reverts when it would break the health factor and succeeds when within safe limits, across random collateral and mint amounts |

### Invariant Tests

| Invariant                                                | What It Checks                                                                                                               |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `invariant_valueOfCollateralGreaterOrEqualToTotalSupply` | Total USD value of all collateral held by the engine always equals or exceeds total DSC supply — the core solvency guarantee |
| `invariant_healthFactorDoesNotFallBelowMinimum`          | No user's health factor falls below the minimum after any sequence of valid protocol operations                              |

---

## Supported Networks

| Network       | Chain ID | WETH Price Feed                            | WBTC Price Feed                            |
| ------------- | -------- | ------------------------------------------ | ------------------------------------------ |
| Anvil (local) | 31337    | MockV3Aggregator ($2000)                   | MockV3Aggregator ($1000)                   |
| Sepolia       | 11155111 | 0x694AA1769357215DE4FAC081bf1f309aDC325306 | 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 |

---

## Security Properties

- Reentrancy protection on all state-changing external functions via OpenZeppelin ReentrancyGuard
- CEI (Checks-Effects-Interactions) pattern applied throughout — state is updated before any external calls
- Oracle staleness protection via OracleLib — price feeds older than 3 hours cause reverts
- Health factor checked after every operation that could reduce collateralisation
- Liquidation bonus capped at 10% to prevent over-incentivising destabilising liquidations
- Liquidator's own health factor checked after liquidation to prevent cascading insolvency

---

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC20, ERC20Burnable, Ownable, ReentrancyGuard, IERC20
- [Chainlink EVM](https://github.com/smartcontractkit/chainlink-evm) — AggregatorV3Interface, MockV3Aggregator

---

## License

MIT
