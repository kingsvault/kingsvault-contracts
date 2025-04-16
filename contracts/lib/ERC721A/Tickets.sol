// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../../interfaces/ITickets.sol";
import {TicketsStorage} from "./TicketsStorage.sol";

/**
 * @title Tickets
 *
 * @dev Implementation of the [ERC721](https://eips.ethereum.org/EIPS/eip-721).
 * Optimized for lower gas during batch mints.
 *
 * Ticket IDs are minted in sequential order (e.g. 0, 1, 2, 3, ...)
 * starting from `_startTicketId()`.
 *
 * Assumptions:
 * - An owner cannot have more than 2**64 - 1 (max value of uint64) of supply.
 * - The maximum ticket ID cannot exceed 2**256 - 1 (max value of uint256).
 */
abstract contract Tickets is Initializable, ITickets {
    using TicketsStorage for TicketsStorage.Layout;

    // =============================================================
    //                           CONSTANTS
    // =============================================================

    // Mask of an entry in packed address data.
    uint256 private constant _BITMASK_ADDRESS_DATA_ENTRY = (1 << 64) - 1;

    // The bit position of `numberMinted` in packed address data.
    uint256 private constant _BITPOS_NUMBER_MINTED = 64;

    // The bit position of `startTimestamp` in packed ownership.
    uint256 private constant _BITPOS_START_TIMESTAMP = 160;

    // The bit mask of the `burned` bit in packed ownership.
    uint256 private constant _BITMASK_BURNED = 1 << 224;

    // The bit position of the `nextInitialized` bit in packed ownership.
    uint256 private constant _BITPOS_NEXT_INITIALIZED = 225;

    // The bit position of `extraData` in packed ownership.
    uint256 private constant _BITPOS_EXTRA_DATA = 232;

    // The mask of the lower 160 bits for addresses.
    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

    // The `Ticket` event signature is given by:
    // `keccak256(bytes("Ticket(address,uint256)"))`.
    //bytes32 private constant _TICKET_EVENT_SIGNATURE =
    //    0x465c8871fac6f7c7079924b414b86ec86be97dae9732142865b86c5d0cd8a1eb;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    function __Tickets_init() internal onlyInitializing {
        __Tickets_init_unchained();
    }

    function __Tickets_init_unchained() internal onlyInitializing {
        TicketsStorage.layout()._currentIndex = _startTicketId();
    }

    // =============================================================
    //                   TOKEN COUNTING OPERATIONS
    // =============================================================

    /**
     * @dev Returns the starting ticket ID for sequential mints.
     *
     * Override this function to change the starting ticket ID for sequential mints.
     *
     * Note: The value returned must never change after any tickets have been minted.
     */
    function _startTicketId() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev Returns the next ticket ID to be minted.
     */
    function _nextTicketId() internal view virtual returns (uint256) {
        return TicketsStorage.layout()._currentIndex;
    }

    /**
     * @dev Returns the total number of tickets in existence.
     * To get the total number of tickets minted.
     */
    function ticketsTotal()
        external
        view
        virtual
        override
        returns (uint256 result)
    {
        return _ticketsTotal();
    }

    /**
     * @dev Returns the total amount of tickets minted in the contract.
     */
    function _ticketsTotal() internal view virtual returns (uint256 result) {
        // Counter underflow is impossible as `_currentIndex` does not decrement,
        // and it is initialized to `_startTicketId()`.
        // more than `_currentIndex - _startTicketId()` times.
        unchecked {
            result = TicketsStorage.layout()._currentIndex - _startTicketId();
        }
    }

    // =============================================================
    //                    ADDRESS DATA OPERATIONS
    // =============================================================

    /**
     * @dev Returns the number of tickets in `owner`'s account.
     */
    function ticketsBalanceOf(
        address owner
    ) public view virtual override returns (uint256) {
        if (owner == address(0))
            _revert(TicketsBalanceQueryForZeroAddress.selector);
        return
            TicketsStorage.layout()._packedAddressData[owner] &
            _BITMASK_ADDRESS_DATA_ENTRY;
    }

    // =============================================================
    //                     OWNERSHIPS OPERATIONS
    // =============================================================

    /**
     * @dev Returns the owner of the `ticketId` ticket.
     *
     * Requirements:
     * - `ticketId` must exist.
     */
    function ticketsOwnerOf(
        uint256 ticketId
    ) public view virtual override returns (address) {
        return address(uint160(_packedOwnershipOf(ticketId)));
    }

    /**
     * @dev Returns the unpacked `TicketOwnership` struct at `index`.
     */
    function _ticketOwnershipAt(
        uint256 index
    ) internal view virtual returns (TicketOwnership memory) {
        return
            _unpackedOwnership(
                TicketsStorage.layout()._packedOwnerships[index]
            );
    }

    /**
     * @dev Returns whether the ownership slot at `index` is initialized.
     * An uninitialized slot does not necessarily mean that the slot has no owner.
     */
    function _ticketOwnershipIsInitialized(
        uint256 index
    ) internal view virtual returns (bool) {
        return TicketsStorage.layout()._packedOwnerships[index] != 0;
    }

    /**
     * @dev Returns the packed ownership data of `ticketId`.
     */
    function _packedOwnershipOf(
        uint256 ticketId
    ) private view returns (uint256 packed) {
        if (_startTicketId() <= ticketId) {
            packed = TicketsStorage.layout()._packedOwnerships[ticketId];

            // If the data at the starting slot does not exist, start the scan.
            if (packed == 0) {
                if (ticketId >= TicketsStorage.layout()._currentIndex)
                    _revert(OwnerQueryForNonexistentTicket.selector);
                // Invariant:
                // There will always be an initialized ownership slot
                // (i.e. `ownership.addr != address(0) && ownership.burned == false`)
                // before an unintialized ownership slot
                // (i.e. `ownership.addr == address(0) && ownership.burned == false`)
                // Hence, `ticketId` will not underflow.
                //
                // We can directly compare the packed value.
                // If the address is zero, packed will be zero.
                for (;;) {
                    unchecked {
                        packed = TicketsStorage.layout()._packedOwnerships[
                            --ticketId
                        ];
                    }
                    if (packed == 0) continue;
                    if (packed & _BITMASK_BURNED == 0) return packed;
                    // Otherwise, the ticket is burned, and we must revert.
                    // This handles the case of batch burned tickets, where only the burned bit
                    // of the starting slot is set, and remaining slots are left uninitialized.
                    _revert(OwnerQueryForNonexistentTicket.selector);
                }
            }
            // Otherwise, the data exists and we can skip the scan.
            // This is possible because we have already achieved the target condition.
            // This saves 2143 gas on transfers of initialized tickets.
            // If the ticket is not burned, return `packed`. Otherwise, revert.
            if (packed & _BITMASK_BURNED == 0) return packed;
        }
        _revert(OwnerQueryForNonexistentTicket.selector);
    }

    /**
     * @dev Returns the unpacked `TicketOwnership` struct from `packed`.
     */
    function _unpackedOwnership(
        uint256 packed
    ) private pure returns (TicketOwnership memory ownership) {
        ownership.addr = address(uint160(packed));
        ownership.startTimestamp = uint64(packed >> _BITPOS_START_TIMESTAMP);
        ownership.burned = packed & _BITMASK_BURNED != 0;
        ownership.extraData = uint24(packed >> _BITPOS_EXTRA_DATA);
    }

    /**
     * @dev Packs ownership data into a single uint256.
     */
    function _packOwnershipData(
        address owner,
        uint256 flags
    ) private view returns (uint256 result) {
        assembly {
            // Mask `owner` to the lower 160 bits, in case the upper bits somehow aren't clean.
            owner := and(owner, _BITMASK_ADDRESS)
            // `owner | (block.timestamp << _BITPOS_START_TIMESTAMP) | flags`.
            result := or(
                owner,
                or(shl(_BITPOS_START_TIMESTAMP, timestamp()), flags)
            )
        }
    }

    /**
     * @dev Returns the `nextInitialized` flag set if `quantity` equals 1.
     */
    function _nextInitializedFlag(
        uint256 quantity
    ) private pure returns (uint256 result) {
        // For branchless setting of the `nextInitialized` flag.
        assembly {
            // `(quantity == 1) << _BITPOS_NEXT_INITIALIZED`.
            result := shl(_BITPOS_NEXT_INITIALIZED, eq(quantity, 1))
        }
    }

    /**
     * @dev Returns whether `ticketId` exists.
     *
     * Tickets start existing when they are minted.
     */
    function _ticketExists(
        uint256 ticketId
    ) internal view virtual returns (bool result) {
        if (_startTicketId() <= ticketId) {
            if (ticketId < TicketsStorage.layout()._currentIndex) {
                uint256 packed;
                while (
                    (packed = TicketsStorage.layout()._packedOwnerships[
                        ticketId
                    ]) == 0
                ) --ticketId;
                result = packed & _BITMASK_BURNED == 0;
            }
        }
    }

    // =============================================================
    //                        MINT OPERATIONS
    // =============================================================

    /**
     * @dev Mints `quantity` tickets to `to`.
     *
     * Requirements:
     * - `to` cannot be the zero address.
     * - `quantity` must be greater than 0.
     *
     * Emits a {Ticket} event for each mint.
     */
    function _mintTickets(address to, uint256 quantity) internal virtual {
        uint256 startTicketId = TicketsStorage.layout()._currentIndex;
        if (quantity == 0) _revert(TicketsMintZeroQuantity.selector);

        // Overflows are incredibly unrealistic.
        // `balance` and `numberMinted` have a maximum limit of 2**64.
        // `ticketId` has a maximum limit of 2**256.
        unchecked {
            // Updates:
            // - `address` to the owner.
            // - `startTimestamp` to the timestamp of minting.
            // - `burned` to `false`.
            // - `nextInitialized` to `quantity == 1`.
            TicketsStorage.layout()._packedOwnerships[
                startTicketId
            ] = _packOwnershipData(
                to,
                _nextInitializedFlag(quantity) |
                    _nextExtraData(address(0), to, 0)
            );

            // Updates:
            // - `balance += quantity`.
            // - `numberMinted += quantity`.
            //
            // We can directly add to the `balance` and `numberMinted`.
            TicketsStorage.layout()._packedAddressData[to] +=
                quantity *
                ((1 << _BITPOS_NUMBER_MINTED) | 1);

            // Mask `to` to the lower 160 bits, in case the upper bits somehow aren't clean.
            uint256 toMasked = uint256(uint160(to)) & _BITMASK_ADDRESS;

            if (toMasked == 0) _revert(TicketsMintToZeroAddress.selector);

            //uint256 end = startTicketId + quantity;
            //uint256 ticketId = startTicketId;

            /*do {
                assembly {
                    // Emit the `Ticket` event.
                    log3(
                        0, // Start of data (0, since no data).
                        0, // End of data (0, since no data).
                        _TICKET_EVENT_SIGNATURE, // Signature.
                        toMasked, // `owner`.
                        ticketId // `ticketId`.
                    )
                }
                // The `!=` check ensures that large values of `quantity`
                // that overflows uint256 will make the loop run out of gas.
            } while (++ticketId != end);*/

            //TicketsStorage.layout()._currentIndex = end;
            TicketsStorage.layout()._currentIndex = startTicketId + quantity;
        }
    }

    // =============================================================
    //                     EXTRA DATA OPERATIONS
    // =============================================================

    /**
     * @dev Called during each ticket transfer to set the 24bit `extraData` field.
     * Intended to be overridden by the cosumer contract.
     *
     * `previousExtraData` - the value of `extraData` before transfer.
     *
     * Calling conditions:
     * - When `from` and `to` are both non-zero, `from`'s `ticketId` will be
     * transferred to `to`.
     * - When `from` is zero, `ticketId` will be minted for `to`.
     * - When `to` is zero, `ticketId` will be burned by `from`.
     * - `from` and `to` are never both zero.
     */
    function _extraData(
        address from,
        address to,
        uint24 previousExtraData
    ) internal view virtual returns (uint24) {}

    /**
     * @dev Returns the next extra data for the packed ownership data.
     * The returned result is shifted into position.
     */
    function _nextExtraData(
        address from,
        address to,
        uint256 prevOwnershipPacked
    ) private view returns (uint256) {
        uint24 extraData = uint24(prevOwnershipPacked >> _BITPOS_EXTRA_DATA);
        return uint256(_extraData(from, to, extraData)) << _BITPOS_EXTRA_DATA;
    }

    // =============================================================
    //                       OTHER OPERATIONS
    // =============================================================

    /**
     * @dev For more efficient reverts.
     */
    function _revert(bytes4 errorSelector) internal pure {
        assembly {
            mstore(0x00, errorSelector)
            revert(0x00, 0x04)
        }
    }
}
