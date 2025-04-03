// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import "./ITickets.sol";

/**
 * @dev Interface of TicketsQueryable.
 */
interface ITicketsQueryable is ITickets {
    /**
     * Invalid query range (`start` >= `stop`).
     */
    error InvalidQueryRange();

    /**
     * @dev Returns the `TokenOwnership` struct at `ticketId` without reverting.
     *
     * If the `ticketId` is out of bounds:
     * - `addr = address(0)`
     * - `startTimestamp = 0`
     * - `burned = false`
     * - `extraData = 0`
     *
     * If the `ticketId` is burned:
     * - `addr = <Address of owner before ticket was burned>`
     * - `startTimestamp = <Timestamp when ticket was burned>`
     * - `burned = true`
     * - `extraData = <Extra data when ticket was burned>`
     *
     * Otherwise:
     * - `addr = <Address of owner>`
     * - `startTimestamp = <Timestamp of start of ownership>`
     * - `burned = false`
     * - `extraData = <Extra data at start of ownership>`
     */
    function explicitOwnershipOf(
        uint256 ticketId
    ) external view returns (TokenOwnership memory);

    /**
     * @dev Returns an array of `TokenOwnership` structs at `ticketIds` in order.
     * See {TicketsQueryable-explicitOwnershipOf}
     */
    function explicitOwnershipsOf(
        uint256[] memory ticketIds
    ) external view returns (TokenOwnership[] memory);

    /**
     * @dev Returns an array of ticket IDs owned by `owner`,
     * in the range [`start`, `stop`)
     * (i.e. `start <= ticketId < stop`).
     *
     * This function allows for tickets to be queried if the collection
     * grows too big for a single call of {TicketsQueryable-tokensOfOwner}.
     *
     * Requirements:
     * - `start < stop`
     */
    function tokensOfOwnerIn(
        address owner,
        uint256 start,
        uint256 stop
    ) external view returns (uint256[] memory);

    /**
     * @dev Returns an array of ticket IDs owned by `owner`.
     *
     * This function scans the ownership mapping and is O(`totalSupply`) in complexity.
     * It is meant to be called off-chain.
     *
     * See {TicketsQueryable-tokensOfOwnerIn} for splitting the scan into
     * multiple smaller scans if the collection is large enough to cause
     * an out-of-gas error (10K collections should be fine).
     */
    function tokensOfOwner(
        address owner
    ) external view returns (uint256[] memory);
}
