// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../../interfaces/ITicketsQueryable.sol";
import "./Tickets.sol";

/**
 * @title TicketsQueryable.
 *
 * @dev Tickets subclass with convenience query functions.
 */
abstract contract TicketsQueryable is
    Initializable,
    Tickets,
    ITicketsQueryable
{
    function __TicketsQueryable_init() internal onlyInitializing {
        __TicketsQueryable_init_unchained();
    }

    function __TicketsQueryable_init_unchained() internal onlyInitializing {}

    /**
     * @dev Returns the `TicketOwnership` struct at `ticketId` without reverting.
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
    function ticketsExplicitOwnershipOf(
        uint256 ticketId
    ) public view virtual override returns (TicketOwnership memory ownership) {
        unchecked {
            if (ticketId >= _startTicketId()) {
                if (ticketId < _nextTicketId()) {
                    // If the `ticketId` is within bounds,
                    // scan backwards for the initialized ownership slot.
                    while (!_ticketOwnershipIsInitialized(ticketId)) --ticketId;
                    return _ticketOwnershipAt(ticketId);
                }
            }
        }
    }

    /**
     * @dev Returns an array of ticket IDs owned by `owner`,
     * in the range [`start`, `stop`)
     * (i.e. `start <= ticketId < stop`).
     *
     * This function allows for tickets to be queried if the collection
     * grows too big for a single call of {TicketsQueryable-ticketsOfOwner}.
     *
     * Requirements:
     * - `start < stop`
     */
    function ticketsOfOwnerIn(
        address owner,
        uint256 start,
        uint256 stop
    ) external view virtual override returns (uint256[] memory) {
        return _ticketsOfOwnerIn(owner, start, stop);
    }

    /**
     * @dev Returns an array of ticket IDs owned by `owner`.
     *
     * This function scans the ownership mapping and is O(`ticketsTotal`) in complexity.
     * It is meant to be called off-chain.
     *
     * See {TicketsQueryable-ticketsOfOwnerIn} for splitting the scan into
     * multiple smaller scans if the collection is large enough to cause
     * an out-of-gas error (10K collections should be fine).
     */
    function ticketsOfOwner(
        address owner
    ) external view virtual override returns (uint256[] memory) {
        uint256 start = _startTicketId();
        uint256 stop = _nextTicketId();
        uint256[] memory ticketIds;
        if (start != stop) ticketIds = _ticketsOfOwnerIn(owner, start, stop);
        return ticketIds;
    }

    /**
     * @dev Helper function for returning an array of ticket IDs owned by `owner`.
     *
     * Note that this function is optimized for smaller bytecode size over runtime gas,
     * since it is meant to be called off-chain.
     */
    function _ticketsOfOwnerIn(
        address owner,
        uint256 start,
        uint256 stop
    ) private view returns (uint256[] memory ticketIds) {
        unchecked {
            if (start >= stop) _revert(TicketsInvalidQueryRange.selector);
            // Set `start = max(start, _startTicketId())`.
            if (start < _startTicketId()) start = _startTicketId();
            uint256 nextTokenId = _nextTicketId();
            uint256 stopLimit = nextTokenId;
            // Set `stop = min(stop, stopLimit)`.
            if (stop >= stopLimit) stop = stopLimit;
            // Number of tickets to scan.
            uint256 ticketIdsMaxLength = ticketsBalanceOf(owner);
            // Set `ticketIdsMaxLength` to zero if the range contains no tickets.
            if (start >= stop) ticketIdsMaxLength = 0;
            // If there are one or more tickets to scan.
            if (ticketIdsMaxLength != 0) {
                // Set `ticketIdsMaxLength = min(ticketsBalanceOf(owner), ticketIdsMaxLength)`.
                if (stop - start <= ticketIdsMaxLength)
                    ticketIdsMaxLength = stop - start;
                uint256 m; // Start of available memory.
                assembly {
                    // Grab the free memory pointer.
                    ticketIds := mload(0x40)
                    // Allocate one word for the length, and `ticketIdsMaxLength` words
                    // for the data. `shl(5, x)` is equivalent to `mul(32, x)`.
                    m := add(ticketIds, shl(5, add(ticketIdsMaxLength, 1)))
                    mstore(0x40, m)
                }
                // We need to call `ticketsExplicitOwnershipOf(start)`,
                // because the slot at `start` may not be initialized.
                TicketOwnership memory ownership = ticketsExplicitOwnershipOf(
                    start
                );
                address currOwnershipAddr;
                // If the starting slot exists (i.e. not burned),
                // initialize `currOwnershipAddr`.
                // `ownership.addr` will not be zero,
                // as `start` is clamped to the valid ticket ID range.
                if (!ownership.burned) currOwnershipAddr = ownership.addr;
                uint256 ticketIdsIdx;
                // Use a do-while, which is slightly more efficient for this case,
                // as the array will at least contain one element.
                do {
                    ownership = _ticketOwnershipAt(start); // This implicitly allocates memory.
                    assembly {
                        switch mload(add(ownership, 0x40))
                        // if `ownership.burned == false`.
                        case 0 {
                            // if `ownership.addr != address(0)`.
                            // The `addr` already has it's upper 96 bits clearned,
                            // since it is written to memory with regular Solidity.
                            if mload(ownership) {
                                currOwnershipAddr := mload(ownership)
                            }
                            // if `currOwnershipAddr == owner`.
                            // The `shl(96, x)` is to make the comparison agnostic to any
                            // dirty upper 96 bits in `owner`.
                            if iszero(shl(96, xor(currOwnershipAddr, owner))) {
                                ticketIdsIdx := add(ticketIdsIdx, 1)
                                mstore(
                                    add(ticketIds, shl(5, ticketIdsIdx)),
                                    start
                                )
                            }
                        }
                        // Otherwise, reset `currOwnershipAddr`.
                        // This handles the case of batch burned tickets
                        // (burned bit of first slot set, remaining slots left uninitialized).
                        default {
                            currOwnershipAddr := 0
                        }
                        start := add(start, 1)
                        // Free temporary memory implicitly allocated for ownership
                        // to avoid quadratic memory expansion costs.
                        mstore(0x40, m)
                    }
                } while (
                    !(start == stop || ticketIdsIdx == ticketIdsMaxLength)
                );
                // Store the length of the array.
                assembly {
                    mstore(ticketIds, ticketIdsIdx)
                }
            }
        }
    }
}
