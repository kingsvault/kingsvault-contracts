// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ITicketsQueryable.sol";
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
    ) public view virtual override returns (TokenOwnership memory ownership) {
        unchecked {
            if (ticketId >= _startTicketId()) {
                if (ticketId > _ticketSequentialUpTo())
                    return _ownershipAt(ticketId);

                if (ticketId < _nextTicketId()) {
                    // If the `ticketId` is within bounds,
                    // scan backwards for the initialized ownership slot.
                    while (!_ownershipIsInitialized(ticketId)) --ticketId;
                    return _ownershipAt(ticketId);
                }
            }
        }
    }

    /**
     * @dev Returns an array of `TokenOwnership` structs at `ticketIds` in order.
     * See {TicketsQueryable-explicitOwnershipOf}
     */
    function explicitOwnershipsOf(
        uint256[] calldata ticketIds
    ) external view virtual override returns (TokenOwnership[] memory) {
        TokenOwnership[] memory ownerships;
        uint256 i = ticketIds.length;
        assembly {
            // Grab the free memory pointer.
            ownerships := mload(0x40)
            // Store the length.
            mstore(ownerships, i)
            // Allocate one word for the length,
            // `ticketIds.length` words for the pointers.
            i := shl(5, i) // Multiply `i` by 32.
            mstore(0x40, add(add(ownerships, 0x20), i))
        }
        while (i != 0) {
            uint256 ticketId;
            assembly {
                i := sub(i, 0x20)
                ticketId := calldataload(add(ticketIds.offset, i))
            }
            TokenOwnership memory ownership = explicitOwnershipOf(ticketId);
            assembly {
                // Store the pointer of `ownership` in the `ownerships` array.
                mstore(add(add(ownerships, 0x20), i), ownership)
            }
        }
        return ownerships;
    }

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
    ) external view virtual override returns (uint256[] memory) {
        return _tokensOfOwnerIn(owner, start, stop);
    }

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
    ) external view virtual override returns (uint256[] memory) {
        // If spot mints are enabled, full-range scan is disabled.
        if (_ticketSequentialUpTo() != type(uint256).max)
            _revert(NotCompatibleWithSpotMints.selector);
        uint256 start = _startTicketId();
        uint256 stop = _nextTicketId();
        uint256[] memory ticketIds;
        if (start != stop) ticketIds = _tokensOfOwnerIn(owner, start, stop);
        return ticketIds;
    }

    /**
     * @dev Helper function for returning an array of ticket IDs owned by `owner`.
     *
     * Note that this function is optimized for smaller bytecode size over runtime gas,
     * since it is meant to be called off-chain.
     */
    function _tokensOfOwnerIn(
        address owner,
        uint256 start,
        uint256 stop
    ) private view returns (uint256[] memory ticketIds) {
        unchecked {
            if (start >= stop) _revert(InvalidQueryRange.selector);
            // Set `start = max(start, _startTicketId())`.
            if (start < _startTicketId()) start = _startTicketId();
            uint256 nextTokenId = _nextTicketId();
            // If spot mints are enabled, scan all the way until the specified `stop`.
            uint256 stopLimit = _ticketSequentialUpTo() != type(uint256).max
                ? stop
                : nextTokenId;
            // Set `stop = min(stop, stopLimit)`.
            if (stop >= stopLimit) stop = stopLimit;
            // Number of tickets to scan.
            uint256 ticketIdsMaxLength = balanceOf(owner);
            // Set `ticketIdsMaxLength` to zero if the range contains no tickets.
            if (start >= stop) ticketIdsMaxLength = 0;
            // If there are one or more tickets to scan.
            if (ticketIdsMaxLength != 0) {
                // Set `ticketIdsMaxLength = min(balanceOf(owner), ticketIdsMaxLength)`.
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
                // We need to call `explicitOwnershipOf(start)`,
                // because the slot at `start` may not be initialized.
                TokenOwnership memory ownership = explicitOwnershipOf(start);
                address currOwnershipAddr;
                // If the starting slot exists (i.e. not burned),
                // initialize `currOwnershipAddr`.
                // `ownership.address` will not be zero,
                // as `start` is clamped to the valid ticket ID range.
                if (!ownership.burned) currOwnershipAddr = ownership.addr;
                uint256 ticketIdsIdx;
                // Use a do-while, which is slightly more efficient for this case,
                // as the array will at least contain one element.
                do {
                    if (_ticketSequentialUpTo() != type(uint256).max) {
                        // Skip the remaining unused sequential slots.
                        if (start == nextTokenId)
                            start = _ticketSequentialUpTo() + 1;
                        // Reset `currOwnershipAddr`, as each spot-minted ticket is a batch of one.
                        if (start > _ticketSequentialUpTo())
                            currOwnershipAddr = address(0);
                    }
                    ownership = _ownershipAt(start); // This implicitly allocates memory.
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
