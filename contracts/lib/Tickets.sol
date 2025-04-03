// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ITickets.sol";
import {TicketsStorage} from "./TicketsStorage.sol";

/**
 * @title Tickets
 *
 * @dev Implementation of the [ERC721](https://eips.ethereum.org/EIPS/eip-721)
 * Non-Fungible Token Standard, including the Metadata extension.
 * Optimized for lower gas during batch mints.
 *
 * Token IDs are minted in sequential order (e.g. 0, 1, 2, 3, ...)
 * starting from `_startTicketId()`.
 *
 * The `_ticketSequentialUpTo()` function can be overriden to enable spot mints
 * (i.e. non-consecutive mints) for `ticketId`s greater than `_ticketSequentialUpTo()`.
 *
 * Assumptions:
 *
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

    // The `Transfer` event signature is given by:
    // `keccak256(bytes("Transfer(address,address,uint256)"))`.
    bytes32 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    function __Tickets_init() internal onlyInitializing {
        __Tickets_init_unchained();
    }

    function __Tickets_init_unchained() internal onlyInitializing {
        TicketsStorage.layout()._currentIndex = _startTicketId();

        if (_ticketSequentialUpTo() < _startTicketId())
            _revert(SequentialUpToTooSmall.selector);
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
     * @dev Returns the maximum ticket ID (inclusive) for sequential mints.
     *
     * Override this function to return a value less than 2**256 - 1,
     * but greater than `_startTicketId()`, to enable spot (non-sequential) mints.
     *
     * Note: The value returned must never change after any tickets have been minted.
     */
    function _ticketSequentialUpTo() internal view virtual returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Returns the next ticket ID to be minted.
     */
    function _nextTicketId() internal view virtual returns (uint256) {
        return TicketsStorage.layout()._currentIndex;
    }

    /**
     * @dev Returns the total number of tickets in existence.
     * To get the total number of tickets minted, please see {_totalMinted}.
     */
    function totalSupply()
        public
        view
        virtual
        override
        returns (uint256 result)
    {
        // more than `_currentIndex + _spotMinted - _startTicketId()` times.
        unchecked {
            // With spot minting, the intermediate `result` can be temporarily negative,
            // and the computation must be unchecked.
            result = TicketsStorage.layout()._currentIndex - _startTicketId();
            if (_ticketSequentialUpTo() != type(uint256).max)
                result += TicketsStorage.layout()._spotMinted;
        }
    }

    /**
     * @dev Returns the total amount of tickets minted in the contract.
     */
    function _totalMinted() internal view virtual returns (uint256 result) {
        // Counter underflow is impossible as `_currentIndex` does not decrement,
        // and it is initialized to `_startTicketId()`.
        unchecked {
            result = TicketsStorage.layout()._currentIndex - _startTicketId();
            if (_ticketSequentialUpTo() != type(uint256).max)
                result += TicketsStorage.layout()._spotMinted;
        }
    }

    /**
     * @dev Returns the total number of tickets that are spot-minted.
     */
    function _totalSpotMinted() internal view virtual returns (uint256) {
        return TicketsStorage.layout()._spotMinted;
    }

    // =============================================================
    //                    ADDRESS DATA OPERATIONS
    // =============================================================

    /**
     * @dev Returns the number of tickets in `owner`'s account.
     */
    function balanceOf(
        address owner
    ) public view virtual override returns (uint256) {
        if (owner == address(0)) _revert(BalanceQueryForZeroAddress.selector);
        return
            TicketsStorage.layout()._packedAddressData[owner] &
            _BITMASK_ADDRESS_DATA_ENTRY;
    }

    /**
     * Returns the number of tickets minted by `owner`.
     */
    function _numberMinted(address owner) internal view returns (uint256) {
        return
            (TicketsStorage.layout()._packedAddressData[owner] >>
                _BITPOS_NUMBER_MINTED) & _BITMASK_ADDRESS_DATA_ENTRY;
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
    function ownerOf(
        uint256 ticketId
    ) public view virtual override returns (address) {
        return address(uint160(_packedOwnershipOf(ticketId)));
    }

    /**
     * @dev Gas spent here starts off proportional to the maximum mint batch size.
     * It gradually moves to O(1) as tickets get transferred around over time.
     */
    function _ownershipOf(
        uint256 ticketId
    ) internal view virtual returns (TokenOwnership memory) {
        return _unpackedOwnership(_packedOwnershipOf(ticketId));
    }

    /**
     * @dev Returns the unpacked `TokenOwnership` struct at `index`.
     */
    function _ownershipAt(
        uint256 index
    ) internal view virtual returns (TokenOwnership memory) {
        return
            _unpackedOwnership(
                TicketsStorage.layout()._packedOwnerships[index]
            );
    }

    /**
     * @dev Returns whether the ownership slot at `index` is initialized.
     * An uninitialized slot does not necessarily mean that the slot has no owner.
     */
    function _ownershipIsInitialized(
        uint256 index
    ) internal view virtual returns (bool) {
        return TicketsStorage.layout()._packedOwnerships[index] != 0;
    }

    /**
     * @dev Initializes the ownership slot minted at `index` for efficiency purposes.
     */
    function _initializeOwnershipAt(uint256 index) internal virtual {
        if (TicketsStorage.layout()._packedOwnerships[index] == 0) {
            TicketsStorage.layout()._packedOwnerships[
                index
            ] = _packedOwnershipOf(index);
        }
    }

    /**
     * @dev Returns the packed ownership data of `ticketId`.
     */
    function _packedOwnershipOf(
        uint256 ticketId
    ) private view returns (uint256 packed) {
        if (_startTicketId() <= ticketId) {
            packed = TicketsStorage.layout()._packedOwnerships[ticketId];

            if (ticketId > _ticketSequentialUpTo()) {
                if (_packedOwnershipExists(packed)) return packed;
                _revert(OwnerQueryForNonexistentToken.selector);
            }

            // If the data at the starting slot does not exist, start the scan.
            if (packed == 0) {
                if (ticketId >= TicketsStorage.layout()._currentIndex)
                    _revert(OwnerQueryForNonexistentToken.selector);
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
                    _revert(OwnerQueryForNonexistentToken.selector);
                }
            }
            // Otherwise, the data exists and we can skip the scan.
            // This is possible because we have already achieved the target condition.
            // This saves 2143 gas on transfers of initialized tickets.
            // If the ticket is not burned, return `packed`. Otherwise, revert.
            if (packed & _BITMASK_BURNED == 0) return packed;
        }
        _revert(OwnerQueryForNonexistentToken.selector);
    }

    /**
     * @dev Returns the unpacked `TokenOwnership` struct from `packed`.
     */
    function _unpackedOwnership(
        uint256 packed
    ) private pure returns (TokenOwnership memory ownership) {
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
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     * Tokens start existing when they are minted. See {_mint}.
     */
    function _exists(
        uint256 ticketId
    ) internal view virtual returns (bool result) {
        if (_startTicketId() <= ticketId) {
            if (ticketId > _ticketSequentialUpTo())
                return
                    _packedOwnershipExists(
                        TicketsStorage.layout()._packedOwnerships[ticketId]
                    );

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

    /**
     * @dev Returns whether `packed` represents a ticket that exists.
     */
    function _packedOwnershipExists(
        uint256 packed
    ) private pure returns (bool result) {
        assembly {
            // The following is equivalent to `owner != address(0) && burned == false`.
            // Symbolically tested.
            result := gt(
                and(packed, _BITMASK_ADDRESS),
                and(packed, _BITMASK_BURNED)
            )
        }
    }

    /**
     * @dev Returns whether `msgSender` is equal to `approvedAddress` or `owner`.
     */
    function _isSenderApprovedOrOwner(
        address approvedAddress,
        address owner,
        address msgSender
    ) private pure returns (bool result) {
        assembly {
            // Mask `owner` to the lower 160 bits, in case the upper bits somehow aren't clean.
            owner := and(owner, _BITMASK_ADDRESS)
            // Mask `msgSender` to the lower 160 bits, in case the upper bits somehow aren't clean.
            msgSender := and(msgSender, _BITMASK_ADDRESS)
            // `msgSender == owner || msgSender == approvedAddress`.
            result := or(eq(msgSender, owner), eq(msgSender, approvedAddress))
        }
    }

    // =============================================================
    //                        MINT OPERATIONS
    // =============================================================

    /**
     * @dev Mints `quantity` tickets and transfers them to `to`.
     *
     * Requirements:
     * - `to` cannot be the zero address.
     * - `quantity` must be greater than 0.
     *
     * Emits a {Transfer} event for each mint.
     */
    function _mint(address to, uint256 quantity) internal virtual {
        uint256 startTokenId = TicketsStorage.layout()._currentIndex;
        if (quantity == 0) _revert(MintZeroQuantity.selector);

        _beforeTokenTransfers(address(0), to, startTokenId, quantity);

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
                startTokenId
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

            if (toMasked == 0) _revert(MintToZeroAddress.selector);

            uint256 end = startTokenId + quantity;
            uint256 ticketId = startTokenId;

            if (end - 1 > _ticketSequentialUpTo())
                _revert(SequentialMintExceedsLimit.selector);

            do {
                assembly {
                    // Emit the `Transfer` event.
                    log4(
                        0, // Start of data (0, since no data).
                        0, // End of data (0, since no data).
                        _TRANSFER_EVENT_SIGNATURE, // Signature.
                        0, // `address(0)`.
                        toMasked, // `to`.
                        ticketId // `ticketId`.
                    )
                }
                // The `!=` check ensures that large values of `quantity`
                // that overflows uint256 will make the loop run out of gas.
            } while (++ticketId != end);

            TicketsStorage.layout()._currentIndex = end;
        }
        _afterTokenTransfers(address(0), to, startTokenId, quantity);
    }

    /**
     * @dev Mints a single ticket at `ticketId`.
     *
     * Note: A spot-minted `ticketId` that has been burned can be re-minted again.
     *
     * Requirements:
     * - `to` cannot be the zero address.
     * - `ticketId` must be greater than `_ticketSequentialUpTo()`.
     * - `ticketId` must not exist.
     *
     * Emits a {Transfer} event for each mint.
     */
    function _mintSpot(address to, uint256 ticketId) internal virtual {
        if (ticketId <= _ticketSequentialUpTo())
            _revert(SpotMintTokenIdTooSmall.selector);
        uint256 prevOwnershipPacked = TicketsStorage.layout()._packedOwnerships[
            ticketId
        ];
        if (_packedOwnershipExists(prevOwnershipPacked))
            _revert(TokenAlreadyExists.selector);

        _beforeTokenTransfers(address(0), to, ticketId, 1);

        // Overflows are incredibly unrealistic.
        // The `numberMinted` for `to` is incremented by 1, and has a max limit of 2**64 - 1.
        // `_spotMinted` is incremented by 1, and has a max limit of 2**256 - 1.
        unchecked {
            // Updates:
            // - `address` to the owner.
            // - `startTimestamp` to the timestamp of minting.
            // - `burned` to `false`.
            // - `nextInitialized` to `true` (as `quantity == 1`).
            TicketsStorage.layout()._packedOwnerships[
                ticketId
            ] = _packOwnershipData(
                to,
                _nextInitializedFlag(1) |
                    _nextExtraData(address(0), to, prevOwnershipPacked)
            );

            // Updates:
            // - `balance += 1`.
            // - `numberMinted += 1`.
            //
            // We can directly add to the `balance` and `numberMinted`.
            TicketsStorage.layout()._packedAddressData[to] +=
                (1 << _BITPOS_NUMBER_MINTED) |
                1;

            // Mask `to` to the lower 160 bits, in case the upper bits somehow aren't clean.
            uint256 toMasked = uint256(uint160(to)) & _BITMASK_ADDRESS;

            if (toMasked == 0) _revert(MintToZeroAddress.selector);

            assembly {
                // Emit the `Transfer` event.
                log4(
                    0, // Start of data (0, since no data).
                    0, // End of data (0, since no data).
                    _TRANSFER_EVENT_SIGNATURE, // Signature.
                    0, // `address(0)`.
                    toMasked, // `to`.
                    ticketId // `ticketId`.
                )
            }

            ++TicketsStorage.layout()._spotMinted;
        }

        _afterTokenTransfers(address(0), to, ticketId, 1);
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
     *
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
     * @dev Converts a uint256 to its ASCII string decimal representation.
     */
    function _toString(
        uint256 value
    ) internal pure virtual returns (string memory str) {
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
            // We will need 1 word for the trailing zeros padding, 1 word for the length,
            // and 3 words for a maximum of 78 digits. Total: 5 * 0x20 = 0xa0.
            let m := add(mload(0x40), 0xa0)
            // Update the free memory pointer to allocate.
            mstore(0x40, m)
            // Assign the `str` to the end.
            str := sub(m, 0x20)
            // Zeroize the slot after the string.
            mstore(str, 0)

            // Cache the end of the memory to calculate the length later.
            let end := str

            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            // prettier-ignore
            for { let temp := value } 1 {} {
                str := sub(str, 1)
                // Write the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(str, add(48, mod(temp, 10)))
                // Keep dividing `temp` until zero.
                temp := div(temp, 10)
                // prettier-ignore
                if iszero(temp) { break }
            }

            let length := sub(end, str)
            // Move the pointer 32 bytes leftwards to make room for the length.
            str := sub(str, 0x20)
            // Store the length.
            mstore(str, length)
        }
    }

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
