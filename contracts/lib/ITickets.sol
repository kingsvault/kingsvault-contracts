// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

/**
 * @dev Interface of Tickets.
 */
interface ITickets {
    /**
     * The caller must own the ticket or be an approved operator.
     */
    error ApprovalCallerNotOwnerNorApproved();

    /**
     * The ticket does not exist.
     */
    error ApprovalQueryForNonexistentToken();

    /**
     * Cannot query the balance for the zero address.
     */
    error BalanceQueryForZeroAddress();

    /**
     * Cannot mint to the zero address.
     */
    error MintToZeroAddress();

    /**
     * The quantity of tickets minted must be more than zero.
     */
    error MintZeroQuantity();

    /**
     * The ticket does not exist.
     */
    error OwnerQueryForNonexistentToken();

    /**
     * The caller must own the ticket or be an approved operator.
     */
    error TransferCallerNotOwnerNorApproved();

    /**
     * The ticket must be owned by `from`.
     */
    error TransferFromIncorrectOwner();

    /**
     * Cannot safely transfer to a contract that does not implement the
     * ERC721Receiver interface.
     */
    error TransferToNonERC721ReceiverImplementer();

    /**
     * Cannot transfer to the zero address.
     */
    error TransferToZeroAddress();

    /**
     * The ticket does not exist.
     */
    error URIQueryForNonexistentToken();

    /**
     * The `quantity` minted with ERC2309 exceeds the safety limit.
     */
    error MintERC2309QuantityExceedsLimit();

    /**
     * The `extraData` cannot be set on an unintialized ownership slot.
     */
    error OwnershipNotInitializedForExtraData();

    /**
     * `_ticketSequentialUpTo()` must be greater than `_startTicketId()`.
     */
    error SequentialUpToTooSmall();

    /**
     * The `ticketId` of a sequential mint exceeds `_ticketSequentialUpTo()`.
     */
    error SequentialMintExceedsLimit();

    /**
     * Spot minting requires a `ticketId` greater than `_ticketSequentialUpTo()`.
     */
    error SpotMintTokenIdTooSmall();

    /**
     * Cannot mint over a ticket that already exists.
     */
    error TokenAlreadyExists();

    /**
     * The feature is not compatible with spot mints.
     */
    error NotCompatibleWithSpotMints();

    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct TokenOwnership {
        // The address of the owner.
        address addr;
        // Stores the start time of ownership with minimal overhead for tokenomics.
        uint64 startTimestamp;
        // Whether the ticket has been burned.
        bool burned;
        // Arbitrary data similar to `startTimestamp` that can be set via {_extraData}.
        uint24 extraData;
    }

    // =============================================================
    //                         TOKEN COUNTERS
    // =============================================================

    /**
     * @dev Returns the total number of tickets in existence.
     * Burned tickets will reduce the count.
     * To get the total number of tickets minted, please see {_totalMinted}.
     */
    function totalSupply() external view returns (uint256);

    // =============================================================
    //                            IERC721
    // =============================================================

    /**
     * @dev Emitted when `ticketId` ticket is transferred from `from` to `to`.
     */
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed ticketId
    );

    /**
     * @dev Returns the number of tickets in `owner`'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `ticketId` ticket.
     *
     * Requirements:
     * - `ticketId` must exist.
     */
    function ownerOf(uint256 ticketId) external view returns (address owner);
}
