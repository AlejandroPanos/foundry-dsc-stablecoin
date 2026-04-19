// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Alejandro Paños
 * @dev This is a library that allows us to prevent getting stale data from the Aggregator contract.
 * We establish a stale time, and, if that stale time passes, the code will return an error. This is
 * done to prevent stale data from entering our DeFi protocol. We want all of our protocol to work with
 * the most updated data from Chainlink price feeds since not doing that could cause an exploit.
 */
library OracleLib {
    /* Errors */
    error OracleLib__StaleData();

    /* State variables */
    uint256 private constant TIMEOUT = 3 hours;

    /* Functions */
    function staleCheckLatestRound(AggregatorV3Interface _feed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            _feed.latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__StaleData();
        }

        uint256 secondsSinceUpdate = block.timestamp - updatedAt;
        if (secondsSinceUpdate > TIMEOUT) {
            revert OracleLib__StaleData();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /* Getter functions */
    function getTimeout() external view returns (uint256) {
        return TIMEOUT;
    }
}
