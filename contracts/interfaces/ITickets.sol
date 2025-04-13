// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

/**
 * @dev Interface of Tickets.
 */
interface ITickets {
    /**
     * Cannot query the balance for the zero address.
     */
    error TicketsBalanceQueryForZeroAddress();

    /**
     * Cannot mint to the zero address.
     */
    error TicketsMintToZeroAddress();

    /**
     * The quantity of tickets minted must be more than zero.
     */
    error TicketsMintZeroQuantity();

    /**
     * The ticket does not exist.
     */
    error OwnerQueryForNonexistentTicket();

    struct TicketOwnership {
        // The address of the owner.
        address addr;
        // Stores the start time of ownership with minimal overhead for tokenomics.
        uint64 startTimestamp;
        // Whether the ticket has been burned.
        bool burned;
        // Arbitrary data similar to `startTimestamp` that can be set via {_extraData}.
        uint24 extraData;
    }

    /**
     * @dev Returns the total number of tickets in existence.
     * To get the total number of tickets minted.
     */
    function ticketsTotal() external view returns (uint256);

    /**
     * @dev Emitted when `ticketId` ticket is minted to `owner`.
     */
    event Ticket(address indexed owner, uint256 indexed ticketId);

    /**
     * @dev Returns the number of tickets in `owner`'s account.
     */
    function ticketsBalanceOf(
        address owner
    ) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `ticketId` ticket.
     *
     * Requirements:
     * - `ticketId` must exist.
     */
    function ticketsOwnerOf(
        uint256 ticketId
    ) external view returns (address owner);
}
